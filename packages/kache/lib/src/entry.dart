part of 'client.dart';

abstract class _KacheEntryBase {
  Type get valueType;

  KacheStorageMode get storageMode;

  String? get bindingFingerprint;

  Future<void> close();
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
      _didReadPersistence = query.storageMode != KacheStorageMode.persisted;

  final KacheClient client;
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
  bool _didReadPersistence;
  bool _isInvalidated = false;
  bool _isClosed = false;
  int _references = 0;
  Duration _maximumGcAfter = Duration.zero;
  int _persistenceOperation = 0;

  KacheSnapshot<T> get snapshot => _snapshot;

  Stream<KacheSnapshot<T>> get changes => _changes.stream;

  void addReference(Duration gcAfter) {
    _references += 1;
    if (gcAfter > _maximumGcAfter) {
      _maximumGcAfter = gcAfter;
    }
  }

  void removeReference() {
    if (_references > 0) {
      _references -= 1;
    }
  }

  Future<KacheSnapshot<T>> load(KacheQuery<T> query) {
    final existing = _loadFuture;
    if (existing != null) {
      return existing;
    }
    late final Future<KacheSnapshot<T>> tracked;
    tracked = _performLoad(query).whenComplete(() {
      if (identical(_loadFuture, tracked)) {
        _loadFuture = null;
      }
    });
    _loadFuture = tracked;
    return tracked;
  }

  Future<KacheSnapshot<T>> refresh(KacheQuery<T> query) {
    final fetcher = query.fetch;
    if (fetcher == null) {
      final failure = KacheFailure(
        kind: KacheFailureKind.fetchUnavailable,
        key: key,
        cause: const KacheFetchUnavailableException(),
        stackTrace: StackTrace.current,
      );
      _emitOperationFailure(failure, query.policy.retainDataOnError);
      return Future<KacheSnapshot<T>>.value(_snapshot);
    }
    return _fetch(query, fetcher);
  }

  Future<KacheSnapshot<T>> _performLoad(KacheQuery<T> query) async {
    if (!_didReadPersistence) {
      await _readPersistence(query);
    }
    if (_isClosed) {
      return _snapshot;
    }
    await _expireExisting(query.policy);
    if (_isClosed) {
      return _snapshot;
    }

    final hasData = _snapshot.hasData;
    if (query.policy.isCacheOnly) {
      final maintenance = _maintenanceFuture;
      if (maintenance != null) {
        await maintenance;
      }
      if (!_snapshot.hasData) {
        _emitCacheMiss();
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

  Future<void> _readPersistence(KacheQuery<T> query) async {
    _didReadPersistence = true;
    _setPersistence(
      const KachePersistenceState.reading(),
      emptyPhase: KachePhase.loading,
    );
    KachePersistenceRead<T>? read;
    try {
      read = await client.persistence!.read<T>(key: key, binding: binding!);
    } on Object catch (error, stackTrace) {
      if (_isClosed) {
        return;
      }
      final failure = _toPersistenceFailure(
        kind: KacheFailureKind.persistenceRead,
        error: error,
        stackTrace: stackTrace,
        fallbackStage: KachePersistenceStage.backend,
      );
      _setPersistence(KachePersistenceState.failed(failure));
      await _deleteAfterReadFailure();
      return;
    }
    if (_isClosed) {
      return;
    }
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
      await _deletePersisted();
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
      _startMaintenance(read);
    }
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
        _emitEmpty(const KachePersistenceState.writing());
        await _deletePersisted();
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
    tracked = _performFetch(query, fetcher).whenComplete(() {
      if (identical(_fetchFuture, tracked)) {
        _fetchFuture = null;
        _fetchCancellation = null;
      }
    });
    _fetchFuture = tracked;
    return tracked;
  }

  Future<KacheSnapshot<T>> _performFetch(
    KacheQuery<T> query,
    KacheFetcher<T> fetcher,
  ) async {
    final cancellation = KacheCancellationController();
    _fetchCancellation = cancellation;
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
      if (_isClosed) {
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
      if (storageMode == KacheStorageMode.persisted) {
        await _writePersisted(data, fetchedAt);
      }
    } on KacheCancelledException {
      return _snapshot;
    } on Object catch (error, stackTrace) {
      final failure = KacheFailure(
        kind: KacheFailureKind.fetch,
        key: key,
        cause: error,
        stackTrace: stackTrace,
      );
      _emitOperationFailure(failure, query.policy.retainDataOnError);
    }
    return _snapshot;
  }

  Future<void> _writePersisted(T data, DateTime fetchedAt) async {
    final operation = ++_persistenceOperation;
    try {
      await client.persistence!.write<T>(
        key: key,
        binding: binding!,
        entry: KachePersistedEntry<T>(
          data: data,
          metadata: KachePersistedMetadata(fetchedAt: fetchedAt),
        ),
      );
      if (!_isClosed && operation == _persistenceOperation) {
        _setPersistence(const KachePersistenceState.persisted());
      }
    } on Object catch (error, stackTrace) {
      if (!_isClosed && operation == _persistenceOperation) {
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

  void _startMaintenance(KachePersistenceRead<T> read) {
    final operation = ++_persistenceOperation;
    _setPersistence(const KachePersistenceState.writing());
    final future = _runMaintenance(read, operation);
    _maintenanceFuture = future;
    unawaited(future);
  }

  Future<void> _runMaintenance(
    KachePersistenceRead<T> read,
    int operation,
  ) async {
    try {
      await read.runMaintenance();
      if (!_isClosed && operation == _persistenceOperation) {
        _setPersistence(const KachePersistenceState.persisted());
      }
    } on Object catch (error, stackTrace) {
      if (!_isClosed && operation == _persistenceOperation) {
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
    }
  }

  Future<void> _deleteAfterReadFailure() async {
    try {
      await client.persistence!.delete(key: key);
    } on Object catch (error, stackTrace) {
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

  Future<void> _deletePersisted() async {
    final operation = ++_persistenceOperation;
    try {
      await client.persistence!.delete(key: key);
      if (!_isClosed && operation == _persistenceOperation) {
        _setPersistence(const KachePersistenceState.absent());
      }
    } on Object catch (error, stackTrace) {
      if (!_isClosed && operation == _persistenceOperation) {
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

  @override
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _fetchCancellation?.cancel();
    await _changes.close();
  }
}
