import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:kache/kache.dart';

import 'adapter_envelope.dart';
import 'codec.dart';
import 'envelope.dart';

part 'key_strategy.dart';
part 'binding.dart';
part 'adapter.dart';
part 'box_lease.dart';
part 'store_helpers.dart';

/// Determines whether a store closes an injected Hive box.
enum HiveCeBoxOwnership {
  /// The box lifecycle is managed by the caller.
  borrowed,

  /// The store closes the box when its own close completes.
  owned,
}

/// Reports a failure to open or lease a Hive CE box.
///
/// [toString] is intentionally sanitized: it never includes the box name, file
/// path, cipher details, or key strategy. Inspect [cause] and [stackTrace]
/// for programmatic diagnosis. This exception is separate from
/// [KachePersistenceException] and is never thrown for
/// [KachePersistenceOperation.close].
final class HiveCeOpenException implements Exception {
  HiveCeOpenException._(this.cause, this.stackTrace);

  /// The original failure object.
  final Object cause;

  /// The original stack trace associated with [cause].
  final StackTrace stackTrace;

  @override
  String toString() => 'HiveCeOpenException: failed to open a Hive CE box.';
}

/// A Hive CE persistence backend using one current byte-envelope format.
final class HiveCeKacheStore implements KachePersistenceBackend {
  HiveCeKacheStore._({
    required this.box,
    required this.hive,
    required this.boxOwnership,
    required Future<void> Function() releaseBox,
    required HiveCeKeyStrategy keyStrategy,
  })  : _releaseBox = releaseBox,
        _keyStrategy = keyStrategy;

  /// Wraps an already-open [box] with explicit lifecycle [ownership].
  ///
  /// Pass [keyStrategy] to control physical key derivation. Defaults to
  /// [HiveCeKeyStrategy.sha256]. See [HiveCeKeyStrategy] for security
  /// considerations.
  factory HiveCeKacheStore.fromBox(
    Box<Object?> box, {
    HiveCeBoxOwnership ownership = HiveCeBoxOwnership.borrowed,
    HiveInterface? hive,
    HiveCeKeyStrategy keyStrategy = const HiveCeKeyStrategy.sha256(),
  }) {
    final targetHive = hive ?? Hive;
    _validateBoxOwner(targetHive, box);
    return HiveCeKacheStore._(
      box: box,
      hive: targetHive,
      boxOwnership: ownership,
      releaseBox:
          ownership == HiveCeBoxOwnership.owned ? box.close : _completeVoid,
      keyStrategy: keyStrategy,
    );
  }

  /// Opens or leases a Hive box.
  ///
  /// Stores opened through this factory share a reference-counted lease. A box
  /// opened by this factory closes after the final lease. A box that was
  /// already open outside Kache is borrowed and remains open.
  ///
  /// Pass [keyStrategy] to control physical key derivation. Defaults to
  /// [HiveCeKeyStrategy.sha256]. Concurrent [open] calls sharing an active box
  /// lease must pass a strategy with the same identity.
  ///
  /// All failures during box acquisition — cipher lease mismatches, strategy
  /// lease mismatches, and asynchronous Hive I/O errors — are reported as
  /// [HiveCeOpenException]. Invalid [boxName] arguments throw [ArgumentError]
  /// before any Hive interaction.
  static Future<HiveCeKacheStore> open({
    required String boxName,
    HiveInterface? hive,
    HiveCipher? encryptionCipher,
    HiveCeKeyStrategy keyStrategy = const HiveCeKeyStrategy.sha256(),
    bool crashRecovery = true,
    String? path,
    Uint8List? bytes,
  }) async {
    _validateBoxName(boxName);
    final targetHive = hive ?? Hive;
    final lease = await _acquireHiveBox(
      hive: targetHive,
      boxName: boxName,
      encryptionCipher: encryptionCipher,
      keyStrategyIdentity: keyStrategy._identity,
      crashRecovery: crashRecovery,
      path: path,
      bytes: bytes,
    );
    return HiveCeKacheStore._(
      box: lease.box,
      hive: targetHive,
      boxOwnership: lease.isOwned
          ? HiveCeBoxOwnership.owned
          : HiveCeBoxOwnership.borrowed,
      releaseBox: lease.release,
      keyStrategy: keyStrategy,
    );
  }

  /// The physical Hive box used for byte or native adapter records.
  final Box<Object?> box;

  /// The Hive registry used by [box].
  final HiveInterface hive;

  /// Whether this store participates in closing [box].
  final HiveCeBoxOwnership boxOwnership;

  final Future<void> Function() _releaseBox;
  final Map<String, Type> _codecTypes = <String, Type>{};
  bool _isClosed = false;
  Future<void>? _closeFuture;
  final HiveCeKeyStrategy _keyStrategy;

  /// Creates a typed binding owned by this exact store.
  ///
  /// [codecId] is the sole identity of [codec]'s byte format. Change it when
  /// the encoded representation changes. An optional [migrate] callback can
  /// preserve offline data written under a previous codec identifier; without
  /// one, core recovery discards the incompatible cache record and refetches.
  HiveCeBinding<T> bind<T>({
    required String codecId,
    required HiveCeCodec<T> codec,
    HiveCeMigrator<T>? migrate,
  }) {
    _validateBindingConfiguration(codecId: codecId);
    final existingType = _codecTypes[codecId];
    final hasTypeConflict = existingType != null && existingType != T;
    _codecTypes.putIfAbsent(codecId, () => T);
    return HiveCeBinding<T>._(
      backend: this,
      codecId: codecId,
      codec: codec,
      migrate: migrate,
      hasTypeConflict: hasTypeConflict,
    );
  }

  /// Creates a binding using an already registered Hive CE [adapter].
  ///
  /// The adapter is not registered or owned by this store. Its type id must be
  /// registered on [hive] before this method is called.
  HiveCeAdapterBinding<T> bindAdapter<T>(TypeAdapter<dynamic> adapter) {
    if (adapter is! TypeAdapter<T>) {
      throw ArgumentError(
        'The Hive CE TypeAdapter cannot encode the binding value type.',
        'adapter',
      );
    }
    _validateAdapterTypeId(adapter.typeId);
    if (!hive.isAdapterRegistered(adapter.typeId)) {
      throw ArgumentError.value(
        adapter.typeId,
        'adapter',
        'The Hive CE TypeAdapter must be registered before binding.',
      );
    }
    return HiveCeAdapterBinding<T>._(
      backend: this,
      typeId: adapter.typeId,
    );
  }

  @override
  Future<KachePersistenceRead<T>?> read<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
  }) async {
    _ensureOpen(KachePersistenceOperation.read);
    final hiveBinding = _ensureBinding<T>(
      binding,
      KachePersistenceOperation.read,
    );
    final physicalKey = _physicalKeyOf(key);
    final raw = _safeGet(physicalKey, KachePersistenceOperation.read);
    if (raw == null) {
      return null;
    }

    if (hiveBinding is HiveCeAdapterBinding<T>) {
      return _readAdapter<T>(binding: hiveBinding, raw: raw);
    }
    if (raw is! Uint8List) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.decode,
        cause: const FormatException('Hive CE value is not a byte record.'),
        stackTrace: StackTrace.current,
      );
    }
    final byteBinding = hiveBinding as HiveCeBinding<T>;
    final envelope = _decodeEnvelope(raw);
    final isCurrentFormat = envelope.codecId == byteBinding.codecId;
    final data = isCurrentFormat
        ? _decodeCurrent(byteBinding, envelope.payload)
        : _migrate(byteBinding, envelope.payload, envelope.codecId);
    final entry = KachePersistedEntry<T>(
      data: data,
      metadata: KachePersistedMetadata(
        fetchedAt: envelope.fetchedAt,
        isInvalidated: envelope.isInvalidated,
      ),
    );
    if (isCurrentFormat) {
      return KachePersistenceRead<T>(entry: entry);
    }
    final expectedRecord = Uint8List.fromList(raw);
    return KachePersistenceRead<T>(
      entry: entry,
      maintenance: () => _rewriteMigrated<T>(
        byteBinding,
        entry,
        expectedRecord,
        physicalKey: physicalKey,
      ),
    );
  }

  @override
  Future<void> write<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
    required KachePersistedEntry<T> entry,
  }) async {
    _ensureOpen(KachePersistenceOperation.write);
    final hiveBinding = _ensureBinding<T>(
      binding,
      KachePersistenceOperation.write,
    );
    final physicalKey = _physicalKeyOf(key);
    if (hiveBinding is HiveCeAdapterBinding<T>) {
      await _writeAdapter<T>(
        physicalKey: physicalKey,
        binding: hiveBinding,
        entry: entry,
      );
      return;
    }
    final byteBinding = hiveBinding as HiveCeBinding<T>;
    late final Uint8List payload;
    try {
      payload = Uint8List.fromList(byteBinding.codec.encode(entry.data));
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.write,
        stage: KachePersistenceStage.encode,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    final record = HiveCeEnvelope.encode(
      fetchedAt: entry.metadata.fetchedAt,
      isInvalidated: entry.metadata.isInvalidated,
      codecId: byteBinding.codecId,
      payload: payload,
    );
    await _runBackend(
      KachePersistenceOperation.write,
      () => box.put(physicalKey, record),
    );
  }

  @override
  Future<void> delete({required KacheKey key}) async {
    _ensureOpen(KachePersistenceOperation.delete);
    await _runBackend(
      KachePersistenceOperation.delete,
      () => box.delete(_physicalKeyOf(key)),
    );
  }

  @override
  Future<void> clearNamespace({required KacheNamespace namespace}) async {
    _ensureOpen(KachePersistenceOperation.clearNamespace);
    final prefix = _physicalNamespacePrefix(namespace);
    late final List<String> keys;
    try {
      keys = box.keys
          .whereType<String>()
          .where((key) => _isManagedNamespaceKey(key, prefix))
          .toList(growable: false);
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.clearNamespace,
        stage: KachePersistenceStage.backend,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    await _runBackend(
      KachePersistenceOperation.clearNamespace,
      () => box.deleteAll(keys),
    );
  }

  @override
  Future<void> clear() async {
    _ensureOpen(KachePersistenceOperation.clear);
    late final List<String> keys;
    try {
      keys = box.keys
          .whereType<String>()
          .where(_isManagedKey)
          .toList(growable: false);
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.clear,
        stage: KachePersistenceStage.backend,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    await _runBackend(
      KachePersistenceOperation.clear,
      () => box.deleteAll(keys),
    );
  }

  @override
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    _isClosed = true;
    final future = _performClose();
    _closeFuture = future;
    return future;
  }

  Future<void> _performClose() async {
    try {
      await _releaseBox();
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.close,
        stage: KachePersistenceStage.backend,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _ensureOpen(KachePersistenceOperation operation) {
    if (_isClosed) {
      _throwPersistence(
        operation: operation,
        stage: KachePersistenceStage.backend,
        cause: StateError('Hive CE Kache store is closed.'),
        stackTrace: StackTrace.current,
      );
    }
  }
}

Future<void> _completeVoid() => Future<void>.value();
