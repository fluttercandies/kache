part of 'client.dart';

extension _KacheEntryCommandExtensions<T> on _KacheEntry<T> {
  Future<KacheSnapshot<T>> setData(
    T data, {
    required KacheQuery<T> query,
  }) async {
    _ensureCommandAvailable();
    _advanceGeneration();
    final version = _captureVersion();
    final fetchedAt = client._now();
    _isInvalidated = false;
    _emitReady(
      data: data,
      freshness: KacheFreshness.fresh,
      source: KacheDataSource.manual,
      fetchedAt: fetchedAt,
      persistence: storageMode == KacheStorageMode.persisted
          ? const KachePersistenceState.writing()
          : null,
    );
    client._emitEvent(
      kind: KacheEventKind.dataSet,
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
    return _snapshot;
  }

  Future<KacheSnapshot<T>> updateData(
    T Function(KacheSnapshot<T> snapshot) update, {
    required KacheQuery<T> query,
  }) {
    _ensureCommandAvailable();
    final data = update(_snapshot);
    return setData(data, query: query);
  }

  Future<KacheSnapshot<T>> invalidate(
    KacheQuery<T> query, {
    required bool refetch,
  }) async {
    _ensureCommandAvailable();
    _advanceGeneration();
    final version = _captureVersion();
    if (_snapshot.hasData) {
      final data = _snapshot.requireData;
      final fetchedAt = _snapshot.fetchedAt!;
      _isInvalidated = true;
      _emitReady(
        data: data,
        freshness: KacheFreshness.stale,
        source: _snapshot.source!,
        fetchedAt: fetchedAt,
        persistence: storageMode == KacheStorageMode.persisted
            ? const KachePersistenceState.writing()
            : null,
      );
      if (storageMode == KacheStorageMode.persisted) {
        await _writePersisted(
          data,
          fetchedAt,
          version: version,
          isInvalidated: true,
        );
      }
    }
    client._emitEvent(
      kind: KacheEventKind.invalidated,
      key: key,
      debugName: query.debugName,
    );
    if (refetch) {
      return refresh(query);
    }
    return _snapshot;
  }

  Future<KacheSnapshot<T>> remove() async {
    _ensureCommandAvailable();
    _advanceGeneration();
    final version = _captureVersion();
    _didReadPersistence = true;
    _isInvalidated = false;
    if (storageMode == KacheStorageMode.persisted) {
      _emitEmpty(const KachePersistenceState.writing());
      await _deletePersisted(version);
    } else {
      _emitEmpty(null);
    }
    client._emitEvent(kind: KacheEventKind.removed, key: key);
    return _snapshot;
  }
}
