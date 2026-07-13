part of 'client.dart';

abstract class _KacheEntryBase {
  KacheKey get key;

  Type get valueType;

  KacheStorageMode get storageMode;

  String? get bindingFingerprint;

  bool get canCollect;

  void prepareForClear();

  void completeClear();

  void reportClearFailure(KacheFailure failure);

  Future<void> drainWrites();

  void prepareForClientClose({required bool cancelPendingWrites});

  Future<void> drainForClose();

  Future<void> finishClose();
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
  Future<KacheSnapshot<T>>? _loadFuture;
  Future<KacheSnapshot<T>>? _fetchFuture;
  Future<void>? _maintenanceFuture;
  KacheCancellationController? _fetchCancellation;
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

  KacheSnapshot<T> get snapshot => _snapshot;

  Stream<KacheSnapshot<T>> get changes => _changes.stream;

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

  Future<KacheSnapshot<T>> load(KacheQuery<T> query) {
    _ensureCommandAvailable();
    final existing = _loadFuture;
    if (existing != null) {
      return existing;
    }
    late final Future<KacheSnapshot<T>> tracked;
    _activeLoads += 1;
    tracked = _performLoad(query).whenComplete(() {
      if (identical(_loadFuture, tracked)) {
        _loadFuture = null;
      }
      _activeLoads -= 1;
      _operationSettled();
    });
    _loadFuture = tracked;
    return tracked;
  }

  Future<KacheSnapshot<T>> refresh(KacheQuery<T> query) {
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
        debugName: query.debugName,
      );
      return Future<KacheSnapshot<T>>.value(_snapshot);
    }
    return _fetch(query, fetcher);
  }

  Future<KacheSnapshot<T>> _performLoad(KacheQuery<T> query) async {
    if (!_didReadPersistence) {
      await _readPersistence(query);
    }
    if (_isClosed || client.isClosed) {
      return _snapshot;
    }
    await _expireExisting(query.policy);
    if (_isClosed || client.isClosed) {
      return _snapshot;
    }

    final hasData = _snapshot.hasData;
    if (query.policy.isCacheOnly) {
      final maintenance = _maintenanceFuture;
      if (maintenance != null) {
        await maintenance;
      }
      if (!_snapshot.hasData) {
        _emitCacheMiss(debugName: query.debugName);
      }
      return _snapshot;
    }

    final shouldFetch =
        !hasData ||
        switch (query.policy.refreshOnLoad) {
          KacheRevalidation.never => false,
          KacheRevalidation.ifStale =>
            _snapshot.freshness == KacheFreshness.stale,
          KacheRevalidation.always => true,
        };
    if (shouldFetch) {
      return _fetch(query, query.fetch!);
    }
    final maintenance = _maintenanceFuture;
    if (maintenance != null) {
      await maintenance;
    }
    return _snapshot;
  }

  Future<void> _expireExisting(KachePolicy policy) async {
    if (!_snapshot.hasData) {
      return;
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
        await _deletePersisted(version);
      } else {
        _emitEmpty(null);
      }
      _isInvalidated = false;
      return;
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
  }

  Future<KacheSnapshot<T>> _fetch(
    KacheQuery<T> query,
    KacheFetcher<T> fetcher,
  ) {
    final existing = _fetchFuture;
    if (existing != null) {
      return existing;
    }
    late final Future<KacheSnapshot<T>> tracked;
    _activeFetches += 1;
    tracked = _performFetch(query, fetcher).whenComplete(() {
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
  ) async {
    final version = _captureVersion();
    final cancellation = KacheCancellationController();
    _fetchCancellation = cancellation;
    client._emitEvent(
      kind: KacheEventKind.fetchStarted,
      key: key,
      debugName: query.debugName,
    );
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

    try {
      final data = await Future<T>.sync(
        () => fetcher(KacheFetchContext(cancellation: cancellation.token)),
      );
      cancellation.token.throwIfCancelled();
      if (!_isCurrent(version)) {
        return _snapshot;
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
      client._emitEvent(
        kind: KacheEventKind.fetchSucceeded,
        key: key,
        debugName: query.debugName,
      );
      if (storageMode == KacheStorageMode.persisted) {
        await _writePersisted(
          data,
          fetchedAt,
          version: version,
          isInvalidated: false,
        );
      }
    } on KacheCancelledException {
      return _snapshot;
    } on Object catch (error, stackTrace) {
      if (!_isCurrent(version)) {
        return _snapshot;
      }
      final failure = KacheFailure(
        kind: KacheFailureKind.fetch,
        key: key,
        cause: error,
        stackTrace: stackTrace,
      );
      _emitOperationFailure(
        failure,
        query.policy.retainDataOnError,
        debugName: query.debugName,
      );
    }
    return _snapshot;
  }

  _KacheOperationVersion _captureVersion() =>
      client._captureVersion(key, _generation);

  bool _isCurrent(_KacheOperationVersion version) =>
      !_isClosed &&
      version.generation == _generation &&
      client._isEpochCurrent(key, version);

  void _advanceGeneration() {
    _generation += 1;
    _fetchCancellation?.cancel();
    _fetchCancellation = null;
    _fetchFuture = null;
    _loadFuture = null;
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
    _advanceGeneration();
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
    _fetchCancellation?.cancel();
    if (cancelPendingWrites) {
      _writes.cancelPending();
    }
  }

  @override
  Future<void> drainForClose() => _writes.drain();

  @override
  Future<void> finishClose() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _fetchCancellation?.cancel();
    await _changes.close();
  }
}
