part of 'client.dart';

extension _KacheEntryPersistenceExtensions<T> on _KacheEntry<T> {
  Future<void> _readPersistence(
    KacheQuery<T> query,
    _KacheTrace trace,
  ) async {
    final version = _captureVersion();
    _didReadPersistence = true;
    final span = trace.span(
      KacheEventKind.read,
      layer: KacheLayer.persistence,
      context: _eventContext(query),
    );
    _setPersistence(
      const KachePersistenceState.reading(),
      emptyPhase: KachePhase.loading,
    );
    span.start(revision: _snapshot.revision);
    final readOperation = Future<KachePersistenceRead<T>?>.sync(
      () => client.persistence!.read<T>(key: key, binding: binding!),
    ).then<_KacheReadOutcome<T>>(
      _KacheReadValue<T>.new,
      onError: (Object error, StackTrace stackTrace) =>
          _KacheReadError<T>(error, stackTrace),
    );
    late final Future<void> backendRead;
    backendRead = readOperation.then<void>((_) {}).whenComplete(() {
      if (identical(_readBackendFuture, backendRead)) {
        _readBackendFuture = null;
      }
    });
    _readBackendFuture = backendRead;
    final cancellation = version.cancellation.whenCancelled
        .then<_KacheReadOutcome<T>>(_KacheReadCancelled<T>.new);
    final outcome = await Future.any<_KacheReadOutcome<T>>(
      <Future<_KacheReadOutcome<T>>>[readOperation, cancellation],
    );
    KachePersistenceRead<T>? read;
    switch (outcome) {
      case _KacheReadCancelled<T>(:final reason):
        span.cancel(reason, revision: _snapshot.revision);
        return;
      case _KacheReadError<T>(:final error, :final stackTrace):
        if (client.isClosed || !_isCurrent(version)) {
          span.cancel(
            version.cancellation.reason ?? KacheCancelReason.close,
            revision: _snapshot.revision,
          );
          return;
        }
        final failure = _toPersistenceFailure(
          kind: KacheFailureKind.persistenceRead,
          error: error,
          stackTrace: stackTrace,
          expectedOperation: KachePersistenceOperation.read,
          fallbackStage: KachePersistenceStage.backend,
        );
        _setPersistence(KachePersistenceState.failed(failure));
        span.fail(failure, revision: _snapshot.revision);
        await _deleteAfterReadFailure(
          version,
          trace: trace,
          query: query,
        );
        return;
      case _KacheReadValue<T>(read: final value):
        if (client.isClosed || !_isCurrent(version)) {
          span.cancel(
            version.cancellation.reason ?? KacheCancelReason.close,
            revision: _snapshot.revision,
          );
          return;
        }
        read = value;
        break;
    }
    if (read == null) {
      _setPersistence(const KachePersistenceState.absent());
      span.succeed(revision: _snapshot.revision);
      trace
          .span(
            KacheEventKind.lookup,
            layer: KacheLayer.persistence,
            context: _eventContext(query),
          )
          .succeed(
            lookup: KacheLookupResult.miss,
            revision: _snapshot.revision,
          );
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
      span.succeed(revision: _snapshot.revision);
      trace
          .span(
            KacheEventKind.lookup,
            layer: KacheLayer.persistence,
            context: _eventContext(query),
          )
          .succeed(
            lookup: KacheLookupResult.expired,
            revision: _snapshot.revision,
          );
      await _deletePersisted(version, trace: trace, query: query);
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
    span.succeed(revision: _snapshot.revision, data: read.entry.data);
    trace
        .span(
          KacheEventKind.lookup,
          layer: KacheLayer.persistence,
          context: _eventContext(query),
        )
        .succeed(
          lookup: KacheLookupResult.hit,
          revision: _snapshot.revision,
          data: read.entry.data,
        );
    if (read.hasMaintenance) {
      _startMaintenance(read, version, query);
    }
  }

  Future<void> _writePersisted(
    T data,
    DateTime fetchedAt, {
    required _KacheOperationVersion version,
    required bool isInvalidated,
    required _KacheTrace trace,
    required KacheQuery<T> query,
  }) async {
    final span = trace.span(
      KacheEventKind.write,
      layer: KacheLayer.persistence,
      context: _eventContext(query),
    );
    try {
      final executed = await _writes.schedule(
        isValid: () => _isCurrent(version),
        operation: () async {
          span.start(revision: _snapshot.revision);
          await client.persistence!.write<T>(
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
        span.succeed(revision: _snapshot.revision, data: data);
      } else if (executed) {
        span.cancel(
          version.cancellation.reason ?? KacheCancelReason.close,
          revision: _snapshot.revision,
        );
      }
    } on Object catch (error, stackTrace) {
      if (_isCurrent(version)) {
        final failure = _toPersistenceFailure(
          kind: KacheFailureKind.persistenceWrite,
          error: error,
          stackTrace: stackTrace,
          expectedOperation: KachePersistenceOperation.write,
          fallbackStage: KachePersistenceStage.backend,
        );
        _setPersistence(KachePersistenceState.failed(failure));
        span.fail(failure, revision: _snapshot.revision);
      } else if (span._started) {
        span.cancel(
          version.cancellation.reason ?? KacheCancelReason.close,
          revision: _snapshot.revision,
        );
      }
    }
  }

  void _startMaintenance(
    KachePersistenceRead<T> read,
    _KacheOperationVersion version,
    KacheQuery<T> query,
  ) {
    _setPersistence(const KachePersistenceState.writing());
    _maintenanceActive = true;
    final future = _runMaintenance(
      read,
      version,
      client._trace(KacheEventTrigger.maintenance, query: query),
      query,
    );
    _maintenanceFuture = future;
    unawaited(future);
  }

  Future<void> _runMaintenance(
    KachePersistenceRead<T> read,
    _KacheOperationVersion version,
    _KacheTrace trace,
    KacheQuery<T> query,
  ) async {
    final span = trace.span(
      KacheEventKind.write,
      layer: KacheLayer.persistence,
      context: _eventContext(query),
    );
    try {
      final executed = await _writes.schedule(
        isValid: () => _isCurrent(version),
        operation: () async {
          span.start(revision: _snapshot.revision);
          await read.runMaintenance();
        },
      );
      if (executed && _isCurrent(version)) {
        _setPersistence(const KachePersistenceState.persisted());
        span.succeed(
          revision: _snapshot.revision,
          data: _snapshot.hasData ? _snapshot.requireData : _noEventData,
        );
      } else if (executed) {
        span.cancel(
          version.cancellation.reason ?? KacheCancelReason.close,
          revision: _snapshot.revision,
        );
      }
    } on Object catch (error, stackTrace) {
      if (_isCurrent(version)) {
        final failure = _toPersistenceFailure(
          kind: KacheFailureKind.persistenceRead,
          error: error,
          stackTrace: stackTrace,
          expectedOperation: KachePersistenceOperation.read,
          fallbackStage: KachePersistenceStage.migration,
        );
        _setPersistence(KachePersistenceState.failed(failure));
        span.fail(failure, revision: _snapshot.revision);
      } else if (span._started) {
        span.cancel(
          version.cancellation.reason ?? KacheCancelReason.close,
          revision: _snapshot.revision,
        );
      }
    } finally {
      _maintenanceActive = false;
      _operationSettled();
    }
  }

  Future<void> _deleteAfterReadFailure(
    _KacheOperationVersion version, {
    required _KacheTrace trace,
    required KacheQuery<T> query,
  }) async {
    final span = trace.span(
      KacheEventKind.delete,
      layer: KacheLayer.persistence,
      context: _eventContext(query),
    );
    try {
      final executed = await _writes.schedule(
        isValid: () => _isCurrent(version),
        operation: () async {
          span.start(revision: _snapshot.revision);
          await client.persistence!.delete(key: key);
        },
      );
      if (executed && _isCurrent(version)) {
        span.succeed(revision: _snapshot.revision);
      } else if (executed) {
        span.cancel(
          version.cancellation.reason ?? KacheCancelReason.close,
          revision: _snapshot.revision,
        );
      }
    } on Object catch (error, stackTrace) {
      if (_isCurrent(version)) {
        final failure = _toPersistenceFailure(
          kind: KacheFailureKind.delete,
          error: error,
          stackTrace: stackTrace,
          expectedOperation: KachePersistenceOperation.delete,
          fallbackStage: KachePersistenceStage.backend,
        );
        _setPersistence(KachePersistenceState.failed(failure));
        span.fail(failure, revision: _snapshot.revision);
      } else if (span._started) {
        span.cancel(
          version.cancellation.reason ?? KacheCancelReason.close,
          revision: _snapshot.revision,
        );
      }
    }
  }

  Future<void> _deletePersisted(
    _KacheOperationVersion version, {
    required _KacheTrace trace,
    KacheQuery<T>? query,
  }) async {
    final span = trace.span(
      KacheEventKind.delete,
      layer: KacheLayer.persistence,
      context: query == null ? null : _eventContext(query),
    );
    try {
      final executed = await _writes.schedule(
        isValid: () => _isCurrent(version),
        operation: () async {
          span.start(revision: _snapshot.revision);
          await client.persistence!.delete(key: key);
        },
      );
      if (executed && _isCurrent(version)) {
        _setPersistence(const KachePersistenceState.absent());
        span.succeed(revision: _snapshot.revision);
      } else if (executed) {
        span.cancel(
          version.cancellation.reason ?? KacheCancelReason.close,
          revision: _snapshot.revision,
        );
      }
    } on Object catch (error, stackTrace) {
      if (_isCurrent(version)) {
        final failure = _toPersistenceFailure(
          kind: KacheFailureKind.delete,
          error: error,
          stackTrace: stackTrace,
          expectedOperation: KachePersistenceOperation.delete,
          fallbackStage: KachePersistenceStage.backend,
        );
        _setPersistence(KachePersistenceState.failed(failure));
        span.fail(failure, revision: _snapshot.revision);
      } else if (span._started) {
        span.cancel(
          version.cancellation.reason ?? KacheCancelReason.close,
          revision: _snapshot.revision,
        );
      }
    }
  }
}
