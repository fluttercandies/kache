part of 'store.dart';

/// A binding that stores values through a registered Hive CE [TypeAdapter].
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
    required KacheKey key,
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
    return KachePersistenceRead<T>(
      entry: KachePersistedEntry<T>(
        data: data,
        metadata: KachePersistedMetadata(
          fetchedAt: envelope.fetchedAt,
          isInvalidated: envelope.isInvalidated,
        ),
      ),
    );
  }

  Future<void> _writeAdapter<T>({
    required KacheKey key,
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

  void _ensureExistingAdapterCompatible(KacheKey key, int typeId) {
    late final Object? raw;
    try {
      raw = box.get(key.storageKey);
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.write,
        stage: KachePersistenceStage.backend,
        cause: error,
        stackTrace: stackTrace,
      );
    }
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
  if (typeId < 0 || typeId > 223) {
    throw ArgumentError.value(
      typeId,
      'adapter.typeId',
      'Must be an external Hive CE type id from 0 through 223.',
    );
  }
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
