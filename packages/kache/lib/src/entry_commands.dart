part of 'client.dart';

extension _KacheEntryCommandExtensions<T> on _KacheEntry<T> {
  Future<KacheSnapshot<T>> setData(
    T data, {
    required KacheQuery<T> query,
    required _KacheTrace trace,
  }) async {
    _ensureCommandAvailable();
    _advanceGeneration(KacheCancelReason.dataSet);
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
    final span = trace.span(
      KacheEventKind.set,
      context: _eventContext(query),
    )..start(revision: _snapshot.revision);
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
    if (_isCurrent(version)) {
      span.succeed(revision: _snapshot.revision, data: data);
    } else {
      span.cancel(
        version.cancellation.reason ?? KacheCancelReason.close,
        revision: _snapshot.revision,
      );
    }
    return _snapshot;
  }

  Future<KacheSnapshot<T>> updateData(
    T Function(KacheSnapshot<T> snapshot) update, {
    required KacheQuery<T> query,
    required _KacheTrace trace,
  }) {
    _ensureCommandAvailable();
    final data = update(_snapshot);
    return setData(data, query: query, trace: trace);
  }

  Future<KacheSnapshot<T>> invalidate(
    KacheQuery<T> query, {
    required bool refetch,
    required _KacheTrace trace,
  }) async {
    _ensureCommandAvailable();
    _advanceGeneration(KacheCancelReason.invalidate);
    final version = _captureVersion();
    final span = trace.span(
      KacheEventKind.invalidate,
      context: _eventContext(query),
    );
    final hadData = _snapshot.hasData;
    late final T data;
    DateTime? fetchedAt;
    if (hadData) {
      data = _snapshot.requireData;
      fetchedAt = _snapshot.fetchedAt!;
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
    }
    span.start(revision: _snapshot.revision);
    if (hadData) {
      if (storageMode == KacheStorageMode.persisted) {
        await _writePersisted(
          data,
          fetchedAt!,
          version: version,
          isInvalidated: true,
          trace: trace,
          query: query,
        );
      }
    }
    if (!_isCurrent(version)) {
      span.cancel(
        version.cancellation.reason ?? KacheCancelReason.close,
        revision: _snapshot.revision,
      );
      return _snapshot;
    }
    if (refetch) {
      final snapshot = await refresh(query, trace: trace);
      span.succeed(revision: snapshot.revision);
      return snapshot;
    }
    span.succeed(revision: _snapshot.revision);
    return _snapshot;
  }

  Future<KacheSnapshot<T>> remove({required _KacheTrace trace}) async {
    _ensureCommandAvailable();
    _advanceGeneration(KacheCancelReason.remove);
    final version = _captureVersion();
    _didReadPersistence = true;
    _isInvalidated = false;
    if (storageMode == KacheStorageMode.persisted) {
      _emitEmpty(const KachePersistenceState.writing());
    } else {
      _emitEmpty(null);
    }
    final span = trace.span(KacheEventKind.remove)
      ..start(revision: _snapshot.revision);
    if (storageMode == KacheStorageMode.persisted) {
      await _deletePersisted(version, trace: trace);
    }
    if (_isCurrent(version)) {
      span.succeed(revision: _snapshot.revision);
    } else {
      span.cancel(
        version.cancellation.reason ?? KacheCancelReason.close,
        revision: _snapshot.revision,
      );
    }
    return _snapshot;
  }
}
