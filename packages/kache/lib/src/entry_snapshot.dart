part of 'client.dart';

extension _KacheEntrySnapshotExtensions<T> on _KacheEntry<T> {
  void _emitCacheMiss({String? debugName}) {
    final failure = KacheFailure(
      kind: KacheFailureKind.cacheMiss,
      key: key,
      cause: const KacheCacheMissException(),
      stackTrace: StackTrace.current,
    );
    client._reportFailure(failure, debugName: debugName);
    _emitFailed(failure, _snapshot.persistence);
  }

  void _emitOperationFailure(
    KacheFailure failure,
    bool retainData, {
    String? debugName,
  }) {
    client._reportFailure(failure, debugName: debugName);
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
    required KachePersistenceStage fallbackStage,
  }) {
    if (error case final KachePersistenceException persistenceError) {
      return KacheFailure(
        kind: kind,
        key: key,
        cause: persistenceError.cause,
        stackTrace: persistenceError.stackTrace,
        persistenceStage: persistenceError.stage,
      );
    }
    return KacheFailure(
      kind: kind,
      key: key,
      cause: error,
      stackTrace: stackTrace,
      persistenceStage: fallbackStage,
    );
  }

  void _setPersistence(
    KachePersistenceState persistence, {
    KachePhase emptyPhase = KachePhase.idle,
  }) {
    final failure = persistence.failure;
    if (failure != null) {
      client._reportFailure(failure);
    }
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
}
