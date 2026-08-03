part of 'store.dart';

/// A binding that stores values through a registered Hive CE [TypeAdapter].
///
/// This binding follows the adapter's own binary compatibility contract and
/// does not add a Kache schema or migration hook. Use [HiveCeKacheStore.bind]
/// when the payload needs explicit schema versions and migrations.
final class HiveCeAdapterBinding<T> extends KachePersistenceBinding<T> {
  HiveCeAdapterBinding._({
    required super.backend,
    required this.typeId,
  }) : super(fingerprint: 'hive-ce:adapter:v1:$typeId');

  /// The external Hive CE type id used by the registered adapter.
  final int typeId;
}

extension _HiveCeAdapterStore on HiveCeKacheStore {
  Future<KachePersistenceRead<T>> _readAdapter<T>({
    required String physicalKey,
    required String? legacyKey,
    required HiveCeAdapterBinding<T> binding,
    required Object raw,
  }) async {
    late final HiveCeAdapterEnvelope envelope;
    try {
      envelope = HiveCeAdapterEnvelope.decode(raw);
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.decode,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (envelope.typeId != binding.typeId) {
      _throwCompatibility(KachePersistenceOperation.read);
    }
    final data = envelope.data;
    if (data is! T) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.decode,
        cause: StateError('Hive CE adapter value has an incompatible type.'),
        stackTrace: StackTrace.current,
      );
    }
    final entry = KachePersistedEntry<T>(
      data: data,
      metadata: KachePersistedMetadata(
        fetchedAt: envelope.fetchedAt,
        isInvalidated: envelope.isInvalidated,
      ),
    );
    if (legacyKey == null) {
      return KachePersistenceRead<T>(entry: entry);
    }
    return KachePersistenceRead<T>(
      entry: entry,
      maintenance: () => _rewriteAdapterKey(
        physicalKey: physicalKey,
        legacyKey: legacyKey,
        expectedRaw: raw,
      ),
    );
  }

  Future<void> _writeAdapter<T>({
    required String physicalKey,
    required String? legacyKey,
    required HiveCeAdapterBinding<T> binding,
    required KachePersistedEntry<T> entry,
  }) async {
    final record = HiveCeAdapterEnvelope.encode(
      fetchedAt: entry.metadata.fetchedAt,
      isInvalidated: entry.metadata.isInvalidated,
      typeId: binding.typeId,
      data: entry.data,
    );
    try {
      await box.put(physicalKey, record);
      if (legacyKey != null) {
        await box.delete(legacyKey);
      }
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.write,
        stage: KachePersistenceStage.backend,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _ensureExistingAdapterCompatible(
    String physicalKey,
    String? legacyKey,
    int typeId,
  ) {
    _checkAdapterAtKey(physicalKey, typeId);
    if (legacyKey != null) {
      _checkAdapterAtKey(legacyKey, typeId);
    }
  }

  void _checkAdapterAtKey(String key, int typeId) {
    final raw = _safeGet(key, KachePersistenceOperation.write);
    if (raw == null) {
      return;
    }
    if (raw is Uint8List) {
      _throwCompatibility(KachePersistenceOperation.write);
    }
    late final HiveCeAdapterEnvelope envelope;
    try {
      envelope = HiveCeAdapterEnvelope.decode(raw);
    } on Object {
      _throwCompatibility(KachePersistenceOperation.write);
    }
    if (envelope.typeId != typeId) {
      _throwCompatibility(KachePersistenceOperation.write);
    }
  }
}

void _validateAdapterTypeId(int typeId) {
  HiveCeAdapterEnvelope.validateTypeId(
    typeId,
    argumentName: 'adapter.typeId',
  );
}

void _validateBoxOwner(HiveInterface hive, Box<Object?> box) {
  try {
    if (!hive.isBoxOpen(box.name) ||
        !identical(hive.box<Object?>(box.name), box)) {
      throw ArgumentError('The Hive box belongs to another Hive interface.');
    }
  } on ArgumentError {
    rethrow;
  } on Object {
    throw ArgumentError('The Hive box belongs to another Hive interface.');
  }
}
