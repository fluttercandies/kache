part of 'client.dart';

abstract class _KacheEntryBase {
  KacheKey get key;

  Type get valueType;

  KacheStorageMode get storageMode;

  String? get bindingFingerprint;

  bool get canCollect;

  bool cancelFetch(KacheCancelReason reason);

  void prepareForClear();

  void completeClear();

  void reportClearFailure(KacheFailure failure);

  Future<void> drainWrites();

  void prepareForClientClose({required bool cancelPendingWrites});

  Future<void> drainForClose();

  Future<void> finishClose();
}

sealed class _KacheFetchOutcome<T> {
  const _KacheFetchOutcome();
}

final class _KacheFetchValue<T> extends _KacheFetchOutcome<T> {
  const _KacheFetchValue(this.data);

  final T data;
}

final class _KacheFetchError<T> extends _KacheFetchOutcome<T> {
  const _KacheFetchError(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

final class _KacheFetchCancelled<T> extends _KacheFetchOutcome<T> {
  const _KacheFetchCancelled(this.reason);

  final KacheCancelReason reason;
}

sealed class _KacheReadOutcome<T> {
  const _KacheReadOutcome();
}

final class _KacheReadValue<T> extends _KacheReadOutcome<T> {
  const _KacheReadValue(this.read);

  final KachePersistenceRead<T>? read;
}

final class _KacheReadError<T> extends _KacheReadOutcome<T> {
  const _KacheReadError(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

final class _KacheReadCancelled<T> extends _KacheReadOutcome<T> {
  const _KacheReadCancelled(this.reason);

  final KacheCancelReason reason;
}

final class _KacheEntry<T> implements _KacheEntryBase {
  _KacheEntry({required this.client, required KacheQuery<T> query})
      : key = query.key,
        storageMode = query.storageMode,
        binding = query.binding,
        _snapshot = KacheSnapshot<T>.idle(
          persistence: query.storageMode == KacheStorageMode.persisted
              ? const KachePersistenceState.idle()
              : null,
        ),
        _didReadPersistence = query.storageMode != KacheStorageMode.persisted {
    _writes = _KacheWriteQueue(onSettled: _operationSettled);
  }

  final KacheClient client;
  @override
  final KacheKey key;

  @override
  final KacheStorageMode storageMode;

  final KachePersistenceBinding<T>? binding;

  @override
  Type get valueType => T;

  @override
  String? get bindingFingerprint => binding?.fingerprint;

  final StreamController<KacheSnapshot<T>> _changes =
      StreamController<KacheSnapshot<T>>.broadcast(sync: true);
  KacheSnapshot<T> _snapshot;
  Future<void>? _readFuture;
  Future<void>? _readBackendFuture;
  Future<KacheSnapshot<T>>? _fetchFuture;
  Future<KacheSnapshot<T>>? _closeFetchFuture;
  Future<void>? _maintenanceFuture;
  DateTime? _lastFetchFinishedAt;
  KacheCancellationController? _fetchCancellation;
  KacheSnapshot<T>? _fetchFallback;
  late final _KacheWriteQueue _writes;
  KacheScheduledTask? _gcTask;
  bool _didReadPersistence;
  bool _isInvalidated = false;
  bool _isClosed = false;
  int _pendingClears = 0;
  bool _gcDue = false;
  bool _maintenanceActive = false;
  int _references = 0;
  int _activeFetches = 0;
  int _activeLoads = 0;
  Duration _maximumGcAfter = Duration.zero;
  int _generation = 0;
  KacheCancellationController _generationCancellation =
      KacheCancellationController();

  KacheSnapshot<T> get snapshot => _snapshot;

  Stream<KacheSnapshot<T>> get changes => _changes.stream;

  DateTime? get lastFetchFinishedAt => _lastFetchFinishedAt;

  bool get hasPendingClears => _pendingClears > 0;

  @override
  bool get canCollect =>
      _references == 0 &&
      _gcDue &&
      _activeFetches == 0 &&
      _activeLoads == 0 &&
      !_maintenanceActive &&
      _writes.isIdle;

  void addReference(Duration gcAfter) {
    _gcTask?.cancel();
    _gcTask = null;
    _gcDue = false;
    _references += 1;
    if (gcAfter > _maximumGcAfter) {
      _maximumGcAfter = gcAfter;
    }
  }

  void removeReference() {
    if (_references > 0) {
      _references -= 1;
    }
    if (_references == 0) {
      _gcTask?.cancel();
      _gcTask = client._scheduler(_maximumGcAfter, () {
        _gcTask = null;
        _gcDue = true;
        client._tryCollect(this);
      });
    }
  }

  _KacheEventContext _eventContext(KacheQuery<T> query) => _KacheEventContext(
        key: key,
        debugName: query.debugName,
        metadata: query.metadata,
      );

  Future<KacheSnapshot<T>> load(
    KacheQuery<T> query, {
    required _KacheTrace trace,
  }) {
    _ensureCommandAvailable();
    _activeLoads += 1;
    return _performLoad(query, trace).whenComplete(() {
      _activeLoads -= 1;
      _operationSettled();
    });
  }

  Future<KacheSnapshot<T>> refresh(
    KacheQuery<T> query, {
    required _KacheTrace trace,
  }) {
    _ensureCommandAvailable();
    final fetcher = query.fetch;
    if (fetcher == null) {
      final failure = KacheFailure(
        kind: KacheFailureKind.fetchUnavailable,
        key: key,
        cause: const KacheFetchUnavailableException(),
        stackTrace: StackTrace.current,
      );
      _emitOperationFailure(
        failure,
        query.policy.retainDataOnError,
      );
      trace
          .span(KacheEventKind.fetch, context: _eventContext(query))
          .fail(failure, revision: _snapshot.revision);
      return Future<KacheSnapshot<T>>.value(_snapshot);
    }
    return _fetch(query, fetcher, trace);
  }

  Future<KacheSnapshot<T>> revalidate(
    KacheQuery<T> query,
    KacheRevalidation mode, {
    required _KacheTrace trace,
  }) async {
    _ensureCommandAvailable();
    final classification = await _expireExisting(
      query.policy,
      query: query,
      trace: trace,
    );
    if (query.policy.isCacheOnly || mode == KacheRevalidation.never) {
      return _snapshot;
    }
    final shouldFetch = !_snapshot.hasData ||
        mode == KacheRevalidation.always ||
        classification.freshness == KacheFreshness.stale;
    return shouldFetch ? refresh(query, trace: trace) : _snapshot;
  }

  Future<KacheSnapshot<T>> _performLoad(
    KacheQuery<T> query,
    _KacheTrace trace,
  ) async {
    final readPersistence = await _awaitInitialRead(query, trace);
    if (_isClosed || client.isClosed) {
      return _snapshot;
    }
    final classification = await _expireExisting(
      query.policy,
      query: query,
      trace: trace,
    );
    if (_isClosed || client.isClosed) {
      return _snapshot;
    }
    if (!readPersistence &&
        !classification.expired &&
        storageMode != KacheStorageMode.none) {
      final lookup = trace.span(
        KacheEventKind.lookup,
        layer: KacheLayer.memory,
        context: _eventContext(query),
      );
      if (_snapshot.hasData) {
        lookup.succeed(
          lookup: KacheLookupResult.hit,
          revision: _snapshot.revision,
          data: _snapshot.requireData,
        );
      } else {
        lookup.succeed(
          lookup: KacheLookupResult.miss,
          revision: _snapshot.revision,
        );
      }
    }

    final hasData = _snapshot.hasData;
    if (query.policy.isCacheOnly) {
      final maintenance = _maintenanceFuture;
      if (maintenance != null) {
        await maintenance;
      }
      if (!_snapshot.hasData) {
        _emitCacheMiss(_cacheMissFailure());
      }
      return _snapshot;
    }

    final shouldFetch = !hasData ||
        switch (query.policy.refreshOnLoad) {
          KacheRevalidation.never => false,
          KacheRevalidation.ifStale =>
            classification.freshness == KacheFreshness.stale,
          KacheRevalidation.always => true,
        };
    if (shouldFetch) {
      return _fetch(query, query.fetch!, trace);
    }
    final maintenance = _maintenanceFuture;
    if (maintenance != null) {
      await maintenance;
    }
    return _snapshot;
  }

  Future<bool> _awaitInitialRead(
    KacheQuery<T> query,
    _KacheTrace trace,
  ) async {
    final existing = _readFuture;
    if (existing != null) {
      await existing;
      return false;
    }
    if (_didReadPersistence) {
      return false;
    }
    late final Future<void> tracked;
    tracked = _readPersistence(query, trace).whenComplete(() {
      if (identical(_readFuture, tracked)) {
        _readFuture = null;
      }
    });
    _readFuture = tracked;
    await tracked;
    return true;
  }

  Future<({bool expired, KacheFreshness? freshness})> _expireExisting(
    KachePolicy policy, {
    required KacheQuery<T> query,
    required _KacheTrace trace,
  }) async {
    if (!_snapshot.hasData) {
      return (expired: false, freshness: null);
    }
    final freshness = policy.freshnessAt(
      fetchedAt: _snapshot.fetchedAt!,
      now: client._now(),
      isInvalidated: _isInvalidated,
    );
    if (freshness == null) {
      if (storageMode == KacheStorageMode.persisted) {
        final version = _captureVersion();
        _emitEmpty(const KachePersistenceState.writing());
        trace
            .span(
              KacheEventKind.lookup,
              layer: KacheLayer.memory,
              context: _eventContext(query),
            )
            .succeed(
              lookup: KacheLookupResult.expired,
              revision: _snapshot.revision,
            );
        await _deletePersisted(version, trace: trace, query: query);
      } else {
        _emitEmpty(null);
        trace
            .span(
              KacheEventKind.lookup,
              layer: KacheLayer.memory,
              context: _eventContext(query),
            )
            .succeed(
              lookup: KacheLookupResult.expired,
              revision: _snapshot.revision,
            );
      }
      _isInvalidated = false;
      return (expired: true, freshness: null);
    }
    if (freshness != _snapshot.freshness) {
      _emitReady(
        data: _snapshot.requireData,
        freshness: freshness,
        source: _snapshot.source!,
        fetchedAt: _snapshot.fetchedAt!,
        failure: _snapshot.failure,
        persistence: _snapshot.persistence,
      );
    }
    return (expired: false, freshness: freshness);
  }

  Future<KacheSnapshot<T>> _fetch(
    KacheQuery<T> query,
    KacheFetcher<T> fetcher,
    _KacheTrace trace,
  ) {
    final existing = _fetchFuture;
    if (existing != null) {
      return existing;
    }
    late final Future<KacheSnapshot<T>> tracked;
    _activeFetches += 1;
    tracked = _performFetch(query, fetcher, trace).whenComplete(() {
      _lastFetchFinishedAt = client._now();
      if (identical(_fetchFuture, tracked)) {
        _fetchFuture = null;
        _fetchCancellation = null;
      }
      _activeFetches -= 1;
      _operationSettled();
    });
    _fetchFuture = tracked;
    return tracked;
  }

  Future<KacheSnapshot<T>> _performFetch(
    KacheQuery<T> query,
    KacheFetcher<T> fetcher,
    _KacheTrace trace,
  ) async {
    final version = _captureVersion();
    final cancellation = KacheCancellationController();
    final fallback = _snapshot;
    _fetchCancellation = cancellation;
    _fetchFallback = fallback;
    if (_snapshot.hasData) {
      _emitReady(
        data: _snapshot.requireData,
        freshness: _snapshot.freshness!,
        source: _snapshot.source!,
        fetchedAt: _snapshot.fetchedAt!,
        isRefreshing: true,
        persistence: _snapshot.persistence,
      );
    } else {
      _emitLoading(_snapshot.persistence);
    }
    final span = trace.span(
      KacheEventKind.fetch,
      context: _eventContext(query),
    )..start(revision: _snapshot.revision);

    final fetch = Future<T>.sync(
      () => fetcher(KacheFetchContext(cancellation: cancellation.token)),
    ).then<_KacheFetchOutcome<T>>(
      _KacheFetchValue<T>.new,
      onError: (Object error, StackTrace stackTrace) =>
          _KacheFetchError<T>(error, stackTrace),
    );
    final cancelled = cancellation.token.whenCancelled
        .then<_KacheFetchOutcome<T>>(_KacheFetchCancelled<T>.new);
    final outcome = await Future.any<_KacheFetchOutcome<T>>(
      <Future<_KacheFetchOutcome<T>>>[fetch, cancelled],
    );

    switch (outcome) {
      case _KacheFetchCancelled<T>(:final reason):
        span.cancel(reason, revision: _snapshot.revision);
        break;
      case _KacheFetchError<T>(:final error, :final stackTrace):
        if (error case final KacheCancelledException cancelledError) {
          cancelFetch(cancelledError.reason);
          span.cancel(cancelledError.reason, revision: _snapshot.revision);
        } else if (!_isCurrent(version)) {
          span.cancel(
            version.cancellation.reason ?? KacheCancelReason.close,
            revision: _snapshot.revision,
          );
        } else {
          final failure = KacheFailure(
            kind: KacheFailureKind.fetch,
            key: key,
            cause: error,
            stackTrace: stackTrace,
          );
          _emitOperationFailure(failure, query.policy.retainDataOnError);
          span.fail(failure, revision: _snapshot.revision);
        }
        break;
      case _KacheFetchValue<T>(:final data):
        if (!_isCurrent(version) || cancellation.token.isCancelled) {
          span.cancel(
            cancellation.token.reason ?? KacheCancelReason.close,
            revision: _snapshot.revision,
          );
          break;
        }
        if (identical(_fetchCancellation, cancellation)) {
          _fetchCancellation = null;
          _fetchFallback = null;
        }
        final fetchedAt = client._now();
        _isInvalidated = false;
        final persistence = storageMode == KacheStorageMode.persisted
            ? const KachePersistenceState.writing()
            : null;
        _emitReady(
          data: data,
          freshness: KacheFreshness.fresh,
          source: KacheDataSource.fetch,
          fetchedAt: fetchedAt,
          persistence: persistence,
        );
        span.succeed(revision: _snapshot.revision, data: data);
        if (storageMode == KacheStorageMode.persisted) {
          await _writePersisted(
            data,
            fetchedAt,
            version: version,
            isInvalidated: false,
            trace: trace,
            query: query,
          );
        }
        break;
    }
    return _snapshot;
  }

  _KacheOperationVersion _captureVersion() =>
      client._captureVersion(key, _generation, _generationCancellation.token);

  bool _isCurrent(_KacheOperationVersion version) =>
      !_isClosed &&
      version.generation == _generation &&
      client._isEpochCurrent(key, version);

  void _advanceGeneration(KacheCancelReason reason) {
    final generationCancellation = _generationCancellation;
    final fetchCancellation = _fetchCancellation;
    _generation += 1;
    _generationCancellation = KacheCancellationController();
    _fetchCancellation = null;
    _fetchFallback = null;
    _fetchFuture = null;
    generationCancellation.cancel(reason);
    fetchCancellation?.cancel(reason);
  }

  @override
  bool cancelFetch(KacheCancelReason reason) {
    final cancellation = _fetchCancellation;
    final generationCancellation = _generationCancellation;
    final fallback = _fetchFallback;
    if (cancellation == null || fallback == null) {
      return false;
    }
    _generation += 1;
    _generationCancellation = KacheCancellationController();
    _fetchCancellation = null;
    _fetchFallback = null;
    _fetchFuture = null;
    if (reason == KacheCancelReason.manual) {
      _restoreSnapshot(fallback);
    }
    generationCancellation.cancel(reason);
    cancellation.cancel(reason);
    return true;
  }

  void _cancelFetchOnly(KacheCancelReason reason) {
    final cancellation = _fetchCancellation;
    _fetchCancellation = null;
    _fetchFallback = null;
    _fetchFuture = null;
    cancellation?.cancel(reason);
  }

  void _operationSettled() {
    if (_gcDue) {
      client._tryCollect(this);
    }
  }

  void _ensureCommandAvailable() {
    if (_pendingClears > 0) {
      throw const KacheLifecycleException(
        'clear_in_progress',
        'A clear operation is in progress for this cache entry.',
      );
    }
  }

  @override
  void prepareForClear() {
    _pendingClears += 1;
    _advanceGeneration(KacheCancelReason.clear);
    _didReadPersistence = true;
    _isInvalidated = false;
    _emitEmpty(
      storageMode == KacheStorageMode.persisted
          ? const KachePersistenceState.writing()
          : null,
    );
  }

  @override
  void completeClear() {
    if (_pendingClears > 0) {
      _pendingClears -= 1;
    }
    if (storageMode == KacheStorageMode.persisted) {
      _setPersistence(const KachePersistenceState.absent());
    }
  }

  @override
  void reportClearFailure(KacheFailure failure) {
    if (_pendingClears > 0) {
      _pendingClears -= 1;
    }
    if (storageMode == KacheStorageMode.persisted) {
      _setPersistence(KachePersistenceState.failed(failure));
    }
  }

  @override
  Future<void> drainWrites() => _writes.drain();

  @override
  void prepareForClientClose({required bool cancelPendingWrites}) {
    _gcTask?.cancel();
    _gcTask = null;
    _closeFetchFuture = _fetchFuture;
    if (cancelPendingWrites) {
      _advanceGeneration(KacheCancelReason.close);
      _writes.cancelPending();
    } else {
      _cancelFetchOnly(KacheCancelReason.close);
    }
  }

  @override
  Future<void> drainForClose() async {
    final fetch = _closeFetchFuture;
    if (fetch != null) {
      await fetch;
    }
    await _writes.drain();
  }

  @override
  Future<void> finishClose() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    final read = _readFuture;
    _cancelFetchOnly(KacheCancelReason.close);
    _generationCancellation.cancel(KacheCancelReason.close);
    if (read != null) {
      await read;
    }
    final backendRead = _readBackendFuture;
    if (backendRead != null) {
      await backendRead;
    }
    await _changes.close();
  }
}
