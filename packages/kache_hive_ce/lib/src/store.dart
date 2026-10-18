import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:kache/kache.dart';

import 'adapter_envelope.dart';
import 'background.dart';
import 'codec.dart';
import 'envelope.dart';

part 'key_strategy.dart';
part 'binding.dart';
part 'adapter.dart';
part 'box_lease.dart';
part 'store_helpers.dart';
part 'codec_runner.dart';

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
    required this.isolateThreshold,
  })  : _releaseBox = releaseBox,
        _keyStrategy = keyStrategy;

  /// Wraps an already-open [box] with explicit lifecycle [ownership].
  ///
  /// Pass [keyStrategy] to control physical key derivation. Defaults to
  /// [HiveCeKeyStrategy.sha256]. See [HiveCeKeyStrategy] for security
  /// considerations. See [isolateThreshold] for background codec work.
  factory HiveCeKacheStore.fromBox(
    Box<Object?> box, {
    HiveCeBoxOwnership ownership = HiveCeBoxOwnership.borrowed,
    HiveInterface? hive,
    HiveCeKeyStrategy keyStrategy = const HiveCeKeyStrategy.sha256(),
    int? isolateThreshold = _defaultIsolateThreshold,
  }) {
    _validateIsolateThreshold(isolateThreshold);
    final targetHive = hive ?? Hive;
    _validateBoxOwner(targetHive, box);
    return HiveCeKacheStore._(
      box: box,
      hive: targetHive,
      boxOwnership: ownership,
      releaseBox:
          ownership == HiveCeBoxOwnership.owned ? box.close : _completeVoid,
      keyStrategy: keyStrategy,
      isolateThreshold: isolateThreshold,
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
  /// [HiveCeOpenException]. Invalid [boxName] or [isolateThreshold] arguments
  /// throw [ArgumentError] before any Hive interaction. See [isolateThreshold]
  /// for background codec work.
  static Future<HiveCeKacheStore> open({
    required String boxName,
    HiveInterface? hive,
    HiveCipher? encryptionCipher,
    HiveCeKeyStrategy keyStrategy = const HiveCeKeyStrategy.sha256(),
    bool crashRecovery = true,
    String? path,
    Uint8List? bytes,
    int? isolateThreshold = _defaultIsolateThreshold,
  }) async {
    _validateBoxName(boxName);
    _validateIsolateThreshold(isolateThreshold);
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
      isolateThreshold: isolateThreshold,
    );
  }

  /// The physical Hive box used for byte or native adapter records.
  final Box<Object?> box;

  /// The Hive registry used by [box].
  final HiveInterface hive;

  /// Whether this store participates in closing [box].
  final HiveCeBoxOwnership boxOwnership;

  /// Record size in bytes at which byte-codec work runs on a background
  /// isolate, or `null` to always run it inline.
  ///
  /// Reads compare the stored record size. Writes compare the larger of the
  /// record already stored for the key and the last record size seen for the
  /// codec, so the first write of a codec runs inline. Defaults to 64 KiB.
  ///
  /// Below the threshold, a cached value is decoded within the caller's
  /// synchronous stack and can render in the first frame. Above it, decoding
  /// completes on another isolate and the value arrives a few milliseconds
  /// later without blocking the caller.
  ///
  /// Background work requires codec callbacks whose captured state can be
  /// sent to another isolate; top-level or static functions always qualify.
  /// A codec that cannot run on another isolate falls back to inline work
  /// automatically and stays inline for the lifetime of this store. Codec
  /// callbacks must be free of side effects because a fallback repeats them.
  /// On Web, codec work always runs inline. Flutter widget tests run under a
  /// fake clock that never completes isolate work; pass `null` there or keep
  /// test payloads below the threshold.
  final int? isolateThreshold;

  final Future<void> Function() _releaseBox;
  final Map<String, Type> _codecTypes = <String, Type>{};
  final Set<Object> _inlineCodecs = Set<Object>.identity();
  final Map<String, int> _recordSizeHints = <String, int>{};
  final Map<String, Future<void>> _pendingWrites = <String, Future<void>>{};
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
    final pending = _pendingWrites[physicalKey];
    if (pending != null) {
      await pending;
      _ensureOpen(KachePersistenceOperation.read);
    }
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
    final header = _parseHeader(raw);
    final data = await _decodePayload<T>(byteBinding, raw, header);
    final entry = KachePersistedEntry<T>(
      data: data,
      metadata: KachePersistedMetadata(
        fetchedAt: header.fetchedAt,
        isInvalidated: header.isInvalidated,
      ),
    );
    if (header.codecId == byteBinding.codecId) {
      return KachePersistenceRead<T>(entry: entry);
    }
    return KachePersistenceRead<T>(
      entry: entry,
      maintenance: () => _rewriteMigrated<T>(
        byteBinding,
        entry,
        raw,
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
      Future<void> store() => _writeAdapter<T>(
            physicalKey: physicalKey,
            binding: hiveBinding,
            entry: entry,
          );
      await (_pendingWrites.containsKey(physicalKey)
          ? _runInOrder(physicalKey, store)
          : store());
      return;
    }
    final byteBinding = hiveBinding as HiveCeBinding<T>;
    final record = _encodeRecord<T>(
      byteBinding,
      entry,
      estimatedBytes: _estimateWriteBytes(physicalKey, byteBinding.codecId),
      operation: KachePersistenceOperation.write,
      stage: KachePersistenceStage.encode,
    );
    if (record is Uint8List && !_pendingWrites.containsKey(physicalKey)) {
      await _putRecord(physicalKey, record);
      return;
    }
    final encoded = Future<Uint8List>.value(record);
    // Observe failures now; the ordered store reports them to the caller.
    unawaited(
        encoded.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    await _runInOrder(
      physicalKey,
      () async => _putRecord(physicalKey, await encoded),
    );
  }

  @override
  Future<void> delete({required KacheKey key}) async {
    _ensureOpen(KachePersistenceOperation.delete);
    final physicalKey = _physicalKeyOf(key);
    Future<void> remove() => _runBackend(
          KachePersistenceOperation.delete,
          () => box.delete(physicalKey),
        );
    await (_pendingWrites.containsKey(physicalKey)
        ? _runInOrder(physicalKey, remove)
        : remove());
  }

  @override
  Future<void> clearNamespace({required KacheNamespace namespace}) async {
    _ensureOpen(KachePersistenceOperation.clearNamespace);
    await _drainPendingWrites();
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
    await _drainPendingWrites();
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
    // Writes accepted before close keep their completion guarantee. The lease
    // release must otherwise start synchronously so a concurrent reopen sees
    // the closing lease.
    if (_pendingWrites.isNotEmpty) {
      await _drainPendingWrites();
    }
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
