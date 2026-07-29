part of 'client.dart';

extension _KacheEntrySnapshotExtensions<T> on _KacheEntry<T> {
  KacheFailure _cacheMissFailure() => KacheFailure(
        kind: KacheFailureKind.cacheMiss,
        key: key,
        cause: const KacheCacheMissException(),
        stackTrace: StackTrace.current,
      );

  void _emitCacheMiss(KacheFailure failure) {
    _emitFailed(failure, _snapshot.persistence);
  }

  void _emitOperationFailure(
    KacheFailure failure,
    bool retainData,
  ) {
    if (_snapshot.hasData && retainData) {
      _emitReady(
        data: _snapshot.requireData,
        freshness: KacheFreshness.stale,
        source: _snapshot.source!,
        fetchedAt: _snapshot.fetchedAt!,
        failure: failure,
        persistence: _snapshot.persistence,
      );
    } else {
      _emitFailed(failure, _snapshot.persistence);
    }
  }

  KacheFailure _toPersistenceFailure({
    required KacheFailureKind kind,
    required Object error,
    required StackTrace stackTrace,
    required KachePersistenceOperation expectedOperation,
    required KachePersistenceStage fallbackStage,
  }) {
    final details = _normalizePersistenceError(
      error: error,
      stackTrace: stackTrace,
      expectedOperation: expectedOperation,
      fallbackStage: fallbackStage,
    );
    return KacheFailure(
      kind: kind,
      key: key,
      cause: details.cause,
      stackTrace: details.stackTrace,
      persistenceStage: details.stage,
    );
  }

  void _setPersistence(
    KachePersistenceState persistence, {
    KachePhase emptyPhase = KachePhase.idle,
  }) {
    if (_snapshot.hasData) {
      _emitReady(
        data: _snapshot.requireData,
        freshness: _snapshot.freshness!,
        source: _snapshot.source!,
        fetchedAt: _snapshot.fetchedAt!,
        isRefreshing: _snapshot.isRefreshing,
        failure: _snapshot.failure,
        persistence: persistence,
      );
    } else if (_snapshot.phase == KachePhase.failure) {
      _emitFailed(_snapshot.failure!, persistence);
    } else if (emptyPhase == KachePhase.loading) {
      _emitLoading(persistence);
    } else {
      _emitEmpty(persistence);
    }
  }

  void _emitReady({
    required T data,
    required KacheFreshness freshness,
    required KacheDataSource source,
    required DateTime fetchedAt,
    bool isRefreshing = false,
    KacheFailure? failure,
    required KachePersistenceState? persistence,
  }) =>
      _emit(
        KacheSnapshot<T>.ready(
          data: data,
          freshness: freshness,
          source: source,
          fetchedAt: fetchedAt,
          isRefreshing: isRefreshing,
          failure: failure,
          revision: _snapshot.revision + 1,
          persistence: persistence,
        ),
      );

  void _emitLoading(KachePersistenceState? persistence) => _emit(
        KacheSnapshot<T>.loading(
          revision: _snapshot.revision + 1,
          persistence: persistence,
        ),
      );

  void _emitEmpty(KachePersistenceState? persistence) => _emit(
        KacheSnapshot<T>.idle(
          revision: _snapshot.revision + 1,
          persistence: persistence,
        ),
      );

  void _emitFailed(KacheFailure failure, KachePersistenceState? persistence) =>
      _emit(
        KacheSnapshot<T>.failed(
          failure: failure,
          revision: _snapshot.revision + 1,
          persistence: persistence,
        ),
      );

  void _emit(KacheSnapshot<T> next) {
    if (_isClosed) {
      return;
    }
    _snapshot = next;
    _changes.add(next);
  }

  void _restoreSnapshot(KacheSnapshot<T> previous) {
    final revision = _snapshot.revision + 1;
    if (previous.hasData) {
      _emit(
        KacheSnapshot<T>.ready(
          data: previous.requireData,
          freshness: previous.freshness!,
          source: previous.source!,
          fetchedAt: previous.fetchedAt!,
          isRefreshing: previous.isRefreshing,
          failure: previous.failure,
          revision: revision,
          persistence: previous.persistence,
        ),
      );
      return;
    }
    switch (previous.phase) {
      case KachePhase.idle:
        _emit(
          KacheSnapshot<T>.idle(
            revision: revision,
            persistence: previous.persistence,
          ),
        );
        return;
      case KachePhase.loading:
        _emit(
          KacheSnapshot<T>.loading(
            revision: revision,
            persistence: previous.persistence,
          ),
        );
        return;
      case KachePhase.ready:
        throw StateError('A ready KacheSnapshot must contain data.');
      case KachePhase.failure:
        _emit(
          KacheSnapshot<T>.failed(
            failure: previous.failure!,
            revision: revision,
            persistence: previous.persistence,
          ),
        );
        return;
    }
  }
}
