import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';
import 'package:kache/kache.dart';

import 'codec.dart';
import 'envelope.dart';

part 'binding.dart';
part 'box_lease.dart';
part 'store_helpers.dart';

/// Determines whether a store closes an injected Hive box.
enum HiveCeBoxOwnership {
  /// The box lifecycle is managed by the caller.
  borrowed,

  /// The store closes the box when its own close completes.
  owned,
}

/// A Hive CE persistence backend using versioned byte envelopes.
final class HiveCeKacheStore implements KachePersistenceBackend {
  HiveCeKacheStore._({
    required this.box,
    required this.boxOwnership,
    required Future<void> Function() releaseBox,
  }) : _releaseBox = releaseBox;

  /// Wraps an already-open [box] with explicit lifecycle [ownership].
  factory HiveCeKacheStore.fromBox(
    Box<Object?> box, {
    HiveCeBoxOwnership ownership = HiveCeBoxOwnership.borrowed,
  }) =>
      HiveCeKacheStore._(
        box: box,
        boxOwnership: ownership,
        releaseBox:
            ownership == HiveCeBoxOwnership.owned ? box.close : _completeVoid,
      );

  /// Opens or leases a Hive box.
  ///
  /// Stores opened through this factory share a reference-counted lease. A box
  /// opened by this factory closes after the final lease. A box that was
  /// already open outside Kache is borrowed and remains open.
  static Future<HiveCeKacheStore> open({
    required String boxName,
    HiveInterface? hive,
    HiveCipher? encryptionCipher,
    bool crashRecovery = true,
    String? path,
    Uint8List? bytes,
  }) async {
    final targetHive = hive ?? Hive;
    final lease = await _acquireHiveBox(
      hive: targetHive,
      boxName: boxName,
      encryptionCipher: encryptionCipher,
      crashRecovery: crashRecovery,
      path: path,
      bytes: bytes,
    );
    return HiveCeKacheStore._(
      box: lease.box,
      boxOwnership: lease.isOwned
          ? HiveCeBoxOwnership.owned
          : HiveCeBoxOwnership.borrowed,
      releaseBox: lease.release,
    );
  }

  /// The physical Hive box. Kache writes only [Uint8List] values.
  final Box<Object?> box;

  /// Whether this store participates in closing [box].
  final HiveCeBoxOwnership boxOwnership;

  final Future<void> Function() _releaseBox;
  final Map<String, Type> _codecTypes = <String, Type>{};
  bool _isClosed = false;
  Future<void>? _closeFuture;

  /// Creates a typed binding owned by this exact store.
  HiveCeBinding<T> bind<T>({
    required String codecId,
    required int schema,
    required HiveCeCodec<T> codec,
    HiveCeMigrator<T>? migrate,
  }) {
    _validateBindingConfiguration(codecId: codecId, schema: schema);
    final existingType = _codecTypes[codecId];
    final hasTypeConflict = existingType != null && existingType != T;
    _codecTypes.putIfAbsent(codecId, () => T);
    return HiveCeBinding<T>._(
      backend: this,
      codecId: codecId,
      schema: schema,
      codec: codec,
      migrate: migrate,
      hasTypeConflict: hasTypeConflict,
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
    late final Object? raw;
    try {
      raw = box.get(key.storageKey);
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.backend,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (raw == null) {
      return null;
    }
    if (raw is! Uint8List) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.decode,
        cause: const FormatException('Hive CE value is not a byte record.'),
        stackTrace: StackTrace.current,
      );
    }
    final rawBytes = raw;
    final envelope = _decodeEnvelope(rawBytes);
    if (envelope.codecId != hiveBinding.codecId) {
      _throwCompatibility(KachePersistenceOperation.read);
    }
    if (envelope.schema > hiveBinding.schema) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.migration,
        cause: StateError('Stored schema is newer than the binding schema.'),
        stackTrace: StackTrace.current,
      );
    }

    final T data;
    if (envelope.schema == hiveBinding.schema) {
      data = _decodeCurrent(hiveBinding, envelope.payload);
    } else {
      data = _migrate(hiveBinding, envelope.payload, envelope.schema);
    }
    final entry = KachePersistedEntry<T>(
      data: data,
      metadata: KachePersistedMetadata(
        fetchedAt: envelope.fetchedAt,
        isInvalidated: envelope.isInvalidated,
      ),
    );
    if (envelope.schema == hiveBinding.schema) {
      return KachePersistenceRead<T>(entry: entry);
    }
    return KachePersistenceRead<T>(
      entry: entry,
      maintenance: () => _rewriteMigrated(key, hiveBinding, entry, rawBytes),
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
    _ensureExistingCodecCompatible(key, hiveBinding.codecId);
    late final Uint8List payload;
    try {
      payload = Uint8List.fromList(hiveBinding.codec.encode(entry.data));
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
      schema: hiveBinding.schema,
      codecId: hiveBinding.codecId,
      payload: payload,
    );
    try {
      await box.put(key.storageKey, record);
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.write,
        stage: KachePersistenceStage.backend,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> delete({required KacheKey key}) async {
    _ensureOpen(KachePersistenceOperation.delete);
    await _runBackend(
      KachePersistenceOperation.delete,
      () => box.delete(key.storageKey),
    );
  }

  @override
  Future<void> clearNamespace({required KacheNamespace namespace}) async {
    _ensureOpen(KachePersistenceOperation.clearNamespace);
    late final List<String> keys;
    try {
      keys = box.keys
          .whereType<String>()
          .where((key) => key.startsWith(namespace.storagePrefix))
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
    await _runBackend(KachePersistenceOperation.clear, () async {
      await box.clear();
    });
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
