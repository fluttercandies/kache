part of 'store.dart';

/// A binding that stores values through a registered Hive CE [TypeAdapter].
///
/// The adapter's type id identifies its native binary format. Change the type
/// id whenever the adapter changes how stored bytes are interpreted.
final class HiveCeAdapterBinding<T> extends KachePersistenceBinding<T> {
  HiveCeAdapterBinding._({
    required super.backend,
    required this.typeId,
  }) : super(fingerprint: 'hive-ce:adapter:v1:$typeId');

  /// The external Hive CE type id used by the registered adapter.
  final int typeId;
}

extension _HiveCeAdapterStore on HiveCeKacheStore {
  KachePersistenceRead<T> _readAdapter<T>({
    required HiveCeAdapterBinding<T> binding,
    required Object raw,
  }) {
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
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.decode,
        cause: StateError('Hive CE adapter type does not match the binding.'),
        stackTrace: StackTrace.current,
      );
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
    required String physicalKey,
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
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.write,
        stage: KachePersistenceStage.backend,
        cause: error,
        stackTrace: stackTrace,
      );
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
