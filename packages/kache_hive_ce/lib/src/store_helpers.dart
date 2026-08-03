part of 'store.dart';

extension _HiveCeKacheStoreHelpers on HiveCeKacheStore {
  KachePersistenceBinding<T> _ensureBinding<T>(
    KachePersistenceBinding<T> binding,
    KachePersistenceOperation operation,
  ) {
    binding.ensureBackend(this);
    if (binding is HiveCeBinding<T>) {
      if (binding._hasTypeConflict) {
        _throwCompatibility(operation);
      }
      return binding;
    }
    if (binding is HiveCeAdapterBinding<T>) {
      return binding;
    }
    _throwCompatibility(operation);
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

  T _migrate<T>(
    HiveCeBinding<T> binding,
    Uint8List payload,
    String fromCodecId,
  ) {
    final migrate = binding.migrate;
    if (migrate == null) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.migration,
        cause: StateError('No migration is configured for the stored codec.'),
        stackTrace: StackTrace.current,
      );
    }
    try {
      return migrate(Uint8List.fromList(payload), fromCodecId);
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
    HiveCeBinding<T> binding,
    KachePersistedEntry<T> entry,
    Uint8List expectedRecord, {
    required String physicalKey,
  }) async {
    try {
      _ensureOpen(KachePersistenceOperation.read);
      final current = box.get(physicalKey);
      if (current is! Uint8List || !_bytesEqual(current, expectedRecord)) {
        return;
      }
      final payload = Uint8List.fromList(binding.codec.encode(entry.data));
      final record = HiveCeEnvelope.encode(
        fetchedAt: entry.metadata.fetchedAt,
        isInvalidated: entry.metadata.isInvalidated,
        codecId: binding.codecId,
        payload: payload,
      );
      final latest = box.get(physicalKey);
      if (latest is! Uint8List || !_bytesEqual(latest, expectedRecord)) {
        return;
      }
      await box.put(physicalKey, record);
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

  Object? _safeGet(String key, KachePersistenceOperation operation) {
    try {
      return box.get(key);
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: operation,
        stage: KachePersistenceStage.backend,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  String _physicalKeyOf(KacheKey key) => _keyStrategy._formatKey(key);

  String _physicalNamespacePrefix(KacheNamespace namespace) =>
      _keyStrategy._formatNamespacePrefix(namespace);

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
