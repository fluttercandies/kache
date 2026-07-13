part of 'client.dart';

extension _KacheEntryPersistenceExtensions<T> on _KacheEntry<T> {
  Future<void> _readPersistence(KacheQuery<T> query) async {
    final version = _captureVersion();
    _didReadPersistence = true;
    client._emitEvent(
      kind: KacheEventKind.persistenceReadStarted,
      key: key,
      debugName: query.debugName,
    );
    _setPersistence(
      const KachePersistenceState.reading(),
      emptyPhase: KachePhase.loading,
    );
    KachePersistenceRead<T>? read;
    try {
      read = await client.persistence!.read<T>(key: key, binding: binding!);
    } on Object catch (error, stackTrace) {
      if (client.isClosed || !_isCurrent(version)) {
        return;
      }
      final failure = _toPersistenceFailure(
        kind: KacheFailureKind.persistenceRead,
        error: error,
        stackTrace: stackTrace,
        fallbackStage: KachePersistenceStage.backend,
      );
      _setPersistence(KachePersistenceState.failed(failure));
      await _deleteAfterReadFailure(version);
      return;
    }
    if (client.isClosed || !_isCurrent(version)) {
      return;
    }
    client._emitEvent(
      kind: KacheEventKind.persistenceReadSucceeded,
      key: key,
      debugName: query.debugName,
    );
    if (read == null) {
      _setPersistence(const KachePersistenceState.absent());
      return;
    }

    final metadata = read.entry.metadata;
    final freshness = query.policy.freshnessAt(
      fetchedAt: metadata.fetchedAt,
      now: client._now(),
      isInvalidated: metadata.isInvalidated,
    );
    if (freshness == null) {
      _emitEmpty(const KachePersistenceState.writing());
      await _deletePersisted(version);
      return;
    }

    _isInvalidated = metadata.isInvalidated;
    _emitReady(
      data: read.entry.data,
      freshness: freshness,
      source: KacheDataSource.persistence,
      fetchedAt: metadata.fetchedAt,
      persistence: const KachePersistenceState.persisted(),
    );
    if (read.hasMaintenance) {
      _startMaintenance(read, version);
    }
  }

  Future<void> _writePersisted(
    T data,
    DateTime fetchedAt, {
    required _KacheOperationVersion version,
    required bool isInvalidated,
  }) async {
    try {
      final executed = await _writes.schedule(
        isValid: () => _isCurrent(version),
        operation: () {
          client._emitEvent(
            kind: KacheEventKind.persistenceWriteStarted,
            key: key,
          );
          return client.persistence!.write<T>(
            key: key,
            binding: binding!,
            entry: KachePersistedEntry<T>(
              data: data,
              metadata: KachePersistedMetadata(
                fetchedAt: fetchedAt,
                isInvalidated: isInvalidated,
              ),
            ),
          );
        },
      );
      if (executed && _isCurrent(version)) {
        _setPersistence(const KachePersistenceState.persisted());
        client._emitEvent(
          kind: KacheEventKind.persistenceWriteSucceeded,
          key: key,
        );
      }
    } on Object catch (error, stackTrace) {
      if (_isCurrent(version)) {
        _setPersistence(
          KachePersistenceState.failed(
            _toPersistenceFailure(
              kind: KacheFailureKind.persistenceWrite,
              error: error,
              stackTrace: stackTrace,
              fallbackStage: KachePersistenceStage.backend,
            ),
          ),
        );
      }
    }
  }

  void _startMaintenance(
    KachePersistenceRead<T> read,
    _KacheOperationVersion version,
  ) {
    _setPersistence(const KachePersistenceState.writing());
    _maintenanceActive = true;
    final future = _runMaintenance(read, version);
    _maintenanceFuture = future;
    unawaited(future);
  }

  Future<void> _runMaintenance(
    KachePersistenceRead<T> read,
    _KacheOperationVersion version,
  ) async {
    try {
      final executed = await _writes.schedule(
        isValid: () => _isCurrent(version),
        operation: () {
          client._emitEvent(
            kind: KacheEventKind.persistenceWriteStarted,
            key: key,
          );
          return read.runMaintenance();
        },
      );
      if (executed && _isCurrent(version)) {
        _setPersistence(const KachePersistenceState.persisted());
        client._emitEvent(
          kind: KacheEventKind.persistenceWriteSucceeded,
          key: key,
        );
      }
    } on Object catch (error, stackTrace) {
      if (_isCurrent(version)) {
        _setPersistence(
          KachePersistenceState.failed(
            _toPersistenceFailure(
              kind: KacheFailureKind.persistenceRead,
              error: error,
              stackTrace: stackTrace,
              fallbackStage: KachePersistenceStage.migration,
            ),
          ),
        );
      }
    } finally {
      _maintenanceActive = false;
      _operationSettled();
    }
  }

  Future<void> _deleteAfterReadFailure(_KacheOperationVersion version) async {
    try {
      await _writes.schedule(
        isValid: () => _isCurrent(version),
        operation: () => client.persistence!.delete(key: key),
      );
    } on Object catch (error, stackTrace) {
      if (_isCurrent(version)) {
        _setPersistence(
          KachePersistenceState.failed(
            _toPersistenceFailure(
              kind: KacheFailureKind.delete,
              error: error,
              stackTrace: stackTrace,
              fallbackStage: KachePersistenceStage.backend,
            ),
          ),
        );
      }
    }
  }

  Future<void> _deletePersisted(_KacheOperationVersion version) async {
    try {
      final executed = await _writes.schedule(
        isValid: () => _isCurrent(version),
        operation: () => client.persistence!.delete(key: key),
      );
      if (executed && _isCurrent(version)) {
        _setPersistence(const KachePersistenceState.absent());
      }
    } on Object catch (error, stackTrace) {
      if (_isCurrent(version)) {
        _setPersistence(
          KachePersistenceState.failed(
            _toPersistenceFailure(
              kind: KacheFailureKind.delete,
              error: error,
              stackTrace: stackTrace,
              fallbackStage: KachePersistenceStage.backend,
            ),
          ),
        );
      }
    }
  }
}
