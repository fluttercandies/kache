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

  HiveCeEnvelopeHeader _parseHeader(Uint8List raw) {
    try {
      return HiveCeEnvelopeHeader.parse(raw);
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.decode,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Stores an encoded record.
  ///
  /// Accepted writes complete even when [close] starts while they encode,
  /// because close drains them before releasing the box.
  Future<void> _putRecord(String physicalKey, Uint8List record) {
    return _runBackend(
      KachePersistenceOperation.write,
      () => box.put(physicalKey, record),
    );
  }

  /// Rewrites a migrated value in the current codec format.
  ///
  /// Hive replaces a key's in-memory value instance on every put, so the
  /// record is unchanged exactly when the box still holds [readRecord].
  Future<void> _rewriteMigrated<T>(
    HiveCeBinding<T> binding,
    KachePersistedEntry<T> entry,
    Uint8List readRecord, {
    required String physicalKey,
  }) async {
    try {
      _ensureOpen(KachePersistenceOperation.read);
      if (!identical(box.get(physicalKey), readRecord)) {
        return;
      }
      final record = await _encodeRecord<T>(
        binding,
        entry,
        estimatedBytes: readRecord.length,
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.migration,
      );
      _ensureOpen(KachePersistenceOperation.read);
      if (!identical(box.get(physicalKey), readRecord)) {
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
