part of 'store.dart';

extension _HiveCeKacheStoreHelpers on HiveCeKacheStore {
  HiveCeBinding<T> _ensureBinding<T>(
    KachePersistenceBinding<T> binding,
    KachePersistenceOperation operation,
  ) {
    binding.ensureBackend(this);
    if (binding is! HiveCeBinding<T> || binding._hasTypeConflict) {
      _throwCompatibility(operation);
    }
    return binding;
  }

  HiveCeEnvelope _decodeEnvelope(Uint8List raw) {
    try {
      return HiveCeEnvelope.decode(raw);
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.decode,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  T _decodeCurrent<T>(HiveCeBinding<T> binding, Uint8List payload) {
    try {
      return binding.codec.decode(Uint8List.fromList(payload));
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.decode,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  T _migrate<T>(HiveCeBinding<T> binding, Uint8List payload, int fromSchema) {
    final migrate = binding.migrate;
    if (migrate == null) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.migration,
        cause: StateError('No migration is configured for the stored schema.'),
        stackTrace: StackTrace.current,
      );
    }
    try {
      return migrate(Uint8List.fromList(payload), fromSchema);
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.migration,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _rewriteMigrated<T>(
    KacheKey key,
    HiveCeBinding<T> binding,
    KachePersistedEntry<T> entry,
    Uint8List expectedRecord,
  ) async {
    try {
      _ensureOpen(KachePersistenceOperation.read);
      final current = box.get(key.storageKey);
      if (current is! Uint8List || !_bytesEqual(current, expectedRecord)) {
        return;
      }
      final payload = Uint8List.fromList(binding.codec.encode(entry.data));
      final record = HiveCeEnvelope.encode(
        fetchedAt: entry.metadata.fetchedAt,
        isInvalidated: entry.metadata.isInvalidated,
        schema: binding.schema,
        codecId: binding.codecId,
        payload: payload,
      );
      await box.put(key.storageKey, record);
    } on KachePersistenceException catch (error) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.migration,
        cause: error.cause,
        stackTrace: error.stackTrace,
      );
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.migration,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _ensureExistingCodecCompatible(KacheKey key, String codecId) {
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
    if (raw is! Uint8List) {
      _throwCompatibility(KachePersistenceOperation.write);
    }
    try {
      final envelope = HiveCeEnvelope.decode(raw);
      if (envelope.codecId != codecId) {
        _throwCompatibility(KachePersistenceOperation.write);
      }
    } on KachePersistenceException {
      rethrow;
    } on Object {
      _throwCompatibility(KachePersistenceOperation.write);
    }
  }

  Future<void> _runBackend(
    KachePersistenceOperation operation,
    Future<void> Function() callback,
  ) async {
    try {
      await callback();
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: operation,
        stage: KachePersistenceStage.backend,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Never _throwCompatibility(KachePersistenceOperation operation) =>
      _throwPersistence(
        operation: operation,
        stage: KachePersistenceStage.backend,
        cause: StateError('Hive CE binding is incompatible with the record.'),
        stackTrace: StackTrace.current,
      );
}

bool _bytesEqual(Uint8List first, Uint8List second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

Never _throwPersistence({
  required KachePersistenceOperation operation,
  required KachePersistenceStage stage,
  required Object cause,
  required StackTrace stackTrace,
}) {
  throw KachePersistenceException(
    operation: operation,
    stage: stage,
    cause: cause,
    stackTrace: stackTrace,
  );
}
