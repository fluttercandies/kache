part of 'client.dart';

extension _KacheEntryCommandExtensions<T> on _KacheEntry<T> {
  Future<KacheSnapshot<T>> setData(T data) async {
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
    return _snapshot;
  }
}
