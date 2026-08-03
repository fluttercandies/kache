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
    HiveCeBinding<T> binding,
    KachePersistedEntry<T> entry,
    Uint8List expectedRecord, {
    required String physicalKey,
    required String? legacyKey,
  }) async {
    try {
      _ensureOpen(KachePersistenceOperation.read);
      final sourceKey = legacyKey ?? physicalKey;
      final current = box.get(sourceKey);
      if (current is! Uint8List || !_bytesEqual(current, expectedRecord)) {
        return;
      }
      if (legacyKey != null) {
        final existingPhysical = box.get(physicalKey);
        if (existingPhysical != null) {
          await box.delete(legacyKey);
          return;
        }
      }
      final payload = Uint8List.fromList(binding.codec.encode(entry.data));
      final record = HiveCeEnvelope.encode(
        fetchedAt: entry.metadata.fetchedAt,
        isInvalidated: entry.metadata.isInvalidated,
        schema: binding.schema,
        codecId: binding.codecId,
        payload: payload,
      );
      final latestSource = box.get(sourceKey);
      if (latestSource is! Uint8List ||
          !_bytesEqual(latestSource, expectedRecord)) {
        return;
      }
      if (legacyKey != null && box.get(physicalKey) != null) {
        await box.delete(legacyKey);
        return;
      }
      await box.put(physicalKey, record);
      if (legacyKey != null) {
        await box.delete(legacyKey);
      }
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

  Future<void> _rewriteAdapterKey({
    required String physicalKey,
    required String legacyKey,
    required Object expectedRaw,
  }) async {
    try {
      _ensureOpen(KachePersistenceOperation.read);
      final current = box.get(legacyKey);
      if (current == null || !identical(current, expectedRaw)) {
        return;
      }
      final existingPhysical = box.get(physicalKey);
      if (existingPhysical != null) {
        await box.delete(legacyKey);
        return;
      }
      await box.put(physicalKey, expectedRaw);
      await box.delete(legacyKey);
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

  void _ensureExistingCodecCompatible(
    String physicalKey,
    String? legacyKey,
    String codecId,
  ) {
    _checkCodecAtKey(physicalKey, codecId);
    if (legacyKey != null) {
      _checkCodecAtKey(legacyKey, codecId);
    }
  }

  void _checkCodecAtKey(String key, String codecId) {
    final raw = _safeGet(key, KachePersistenceOperation.write);
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

  String? _legacyKeyOf(KacheKey key) {
    final canonical = key.storageKey;
    if (canonical.length <= 255) {
      return canonical;
    }
    return null;
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
