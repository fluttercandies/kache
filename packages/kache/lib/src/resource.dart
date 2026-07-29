part of 'client.dart';

abstract interface class _KacheResourceBase {
  KacheKey get key;

  Future<void> _revalidateAfterClear(_KacheTrace trace);

  Future<void> revalidateOnResume();

  Future<void> _revalidateOnReconnect(_KacheTrace trace);

  Future<void> refreshActive();

  bool cancel();

  void pausePolling();

  void resumePolling();

  void dispose();
}

/// A disposable handle that observes and controls one [KacheQuery].
final class KacheResource<T> implements _KacheResourceBase {
  KacheResource._({
    required KacheClient client,
    required _KacheEntry<T> entry,
    required KacheQuery<T> query,
  })  : _client = client,
        _entry = entry,
        _query = query {
    _entry.addReference(query.policy.gcAfter);
    _entrySubscription = _entry.changes.listen(
      _updates.add,
      onDone: _closeUpdates,
    );
    _stream = Stream<KacheSnapshot<T>>.multi((controller) {
      if (_isDisposed) {
        controller.close();
        return;
      }
      controller.add(snapshot);
      final subscription = _updates.stream.listen(
        controller.add,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
      _startAutomaticLoad();
    }, isBroadcast: true);
  }

  final KacheClient _client;
  final _KacheEntry<T> _entry;

  KacheQuery<T> _query;

  /// The immutable declaration currently used by this handle.
  KacheQuery<T> get query => _query;

  @override
  KacheKey get key => query.key;

  final StreamController<KacheSnapshot<T>> _updates =
      StreamController<KacheSnapshot<T>>.broadcast(sync: true);
  late final StreamSubscription<KacheSnapshot<T>> _entrySubscription;
  late final Stream<KacheSnapshot<T>> _stream;
  bool _didStartAutomaticLoad = false;
  bool _isDisposed = false;
  DateTime? _pollAnchor;
  KacheScheduledTask? _pollTask;

  /// The current shared snapshot, available synchronously.
  KacheSnapshot<T> get snapshot => _entry.snapshot;

  /// A broadcast stream that replays [snapshot] to every new listener.
  ///
  /// The first listener starts [load] once. Listener cancellation does not
  /// dispose this handle.
  Stream<KacheSnapshot<T>> get stream => _stream;

  /// Whether [dispose] has released this handle.
  bool get isDisposed => _isDisposed;

  /// Loads cache data and applies this handle's load policy.
  Future<KacheSnapshot<T>> load() {
    _ensureActive();
    _didStartAutomaticLoad = true;
    return _loadWith(KacheEventTrigger.load);
  }

  /// Forces a fetch with this handle's fetcher, ignoring freshness.
  Future<KacheSnapshot<T>> refresh() {
    _ensureActive();
    return _refreshWith(KacheEventTrigger.refresh);
  }

  Future<KacheSnapshot<T>> _loadWith(
    KacheEventTrigger trigger, {
    _KacheTrace? trace,
  }) =>
      _trackPolling(
        _entry.load(
          query,
          trace: trace ?? _client._trace(trigger, query: query),
        ),
      );

  Future<KacheSnapshot<T>> _refreshWith(
    KacheEventTrigger trigger, {
    _KacheTrace? trace,
  }) =>
      _trackPolling(
        _entry.refresh(
          query,
          trace: trace ?? _client._trace(trigger, query: query),
        ),
      );

  /// Replaces this handle's same-key fetcher and policy without loading.
  void updateQuery(KacheQuery<T> query) {
    _ensureActive();
    _client._rebind(_entry, query);
    _query = query;
    _schedulePolling();
  }

  /// Replaces current data immediately and persists it when configured.
  Future<KacheSnapshot<T>> setData(T data) {
    _ensureActive();
    return _entry.setData(
      data,
      query: query,
      trace: _client._trace(KacheEventTrigger.set, query: query),
    );
  }

  /// Atomically computes and stores data from the latest shared snapshot.
  Future<KacheSnapshot<T>> updateData(
    T Function(KacheSnapshot<T> snapshot) update,
  ) {
    _ensureActive();
    return _entry.updateData(
      update,
      query: query,
      trace: _client._trace(KacheEventTrigger.update, query: query),
    );
  }

  /// Marks current data stale and optionally starts a fresh fetch.
  Future<KacheSnapshot<T>> invalidate({bool refetch = true}) {
    _ensureActive();
    return _entry.invalidate(
      query,
      refetch: refetch,
      trace: _client._trace(KacheEventTrigger.invalidate, query: query),
    );
  }

  /// Removes current memory and persisted data without fetching.
  Future<KacheSnapshot<T>> remove() {
    _ensureActive();
    return _entry.remove(
      trace: _client._trace(KacheEventTrigger.remove, query: query),
    );
  }

  /// Cancels the shared in-flight fetch for this key.
  ///
  /// Returns `false` when no cancellable fetch is active.
  @override
  bool cancel() {
    _ensureActive();
    return _entry.cancelFetch(KacheCancelReason.manual);
  }

  /// Idempotently releases this handle and closes its stream.
  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _cancelPolling();
    unawaited(_entrySubscription.cancel());
    _closeUpdates();
    _client._release(this, _entry);
  }

  @override
  Future<void> _revalidateAfterClear(_KacheTrace trace) async {
    if (!_isDisposed && !_entry.hasPendingClears) {
      await _refreshWith(KacheEventTrigger.clearRefetch, trace: trace);
    }
  }

  @override
  Future<void> revalidateOnResume() async {
    if (!_isDisposed) {
      await _entry.revalidate(
        query,
        query.policy.refreshOnResume,
        trace: _client._trace(KacheEventTrigger.resume, query: query),
      );
    }
  }

  @override
  Future<void> _revalidateOnReconnect(_KacheTrace trace) async {
    if (!_isDisposed) {
      await _entry.revalidate(
        query,
        query.policy.refreshOnReconnect,
        trace: trace,
      );
    }
  }

  @override
  Future<void> refreshActive() async {
    if (!_isDisposed) {
      await _refreshWith(KacheEventTrigger.refresh);
    }
  }

  @override
  void pausePolling() => _cancelPolling();

  @override
  void resumePolling() {
    if (_isDisposed || !_didStartAutomaticLoad) {
      return;
    }
    _pollAnchor = _client._now();
    _schedulePolling();
  }

  void _startAutomaticLoad() {
    if (_didStartAutomaticLoad || _isDisposed) {
      return;
    }
    _didStartAutomaticLoad = true;
    unawaited(load());
  }

  void _ensureActive() {
    if (_isDisposed) {
      throw const KacheLifecycleException(
        'resource_disposed',
        'The Kache resource is disposed.',
      );
    }
    _client._ensureOpen();
  }

  Future<KacheSnapshot<T>> _trackPolling(
    Future<KacheSnapshot<T>> operation,
  ) async {
    try {
      return await operation;
    } finally {
      if (!_isDisposed && !_client.isClosed) {
        _pollAnchor = _client._now();
        _schedulePolling();
      }
    }
  }

  void _schedulePolling() {
    _cancelPolling();
    final interval = query.policy.refreshInterval;
    if (_isDisposed ||
        _client.isClosed ||
        _client._isPollingPaused ||
        !_didStartAutomaticLoad ||
        interval == null) {
      return;
    }
    _pollTask = _client._scheduler(_remaining(interval), _poll);
  }

  Duration _remaining(Duration interval) {
    final now = _client._now();
    final local = _pollAnchor;
    final shared = _entry.lastFetchFinishedAt;
    final anchor = switch ((local, shared)) {
      (null, null) => null,
      (final DateTime value, null) => value,
      (null, final DateTime value) => value,
      (final DateTime left, final DateTime right) =>
        left.isAfter(right) ? left : right,
    };
    if (anchor == null) {
      return interval;
    }
    final elapsed = now.difference(anchor);
    if (elapsed.isNegative) {
      return interval;
    }
    return elapsed >= interval ? Duration.zero : interval - elapsed;
  }

  void _poll() {
    _pollTask = null;
    if (_isDisposed || _client.isClosed || _client._isPollingPaused) {
      return;
    }
    final interval = query.policy.refreshInterval;
    if (interval == null) {
      return;
    }
    final remaining = _remaining(interval);
    if (remaining > Duration.zero) {
      _pollTask = _client._scheduler(remaining, _poll);
      return;
    }
    unawaited(_runPoll());
  }

  Future<void> _runPoll() async {
    try {
      await _refreshWith(KacheEventTrigger.poll);
    } on KacheLifecycleException {
      if (!_isDisposed && !_client.isClosed) {
        _pollAnchor = _client._now();
        _schedulePolling();
      }
    }
  }

  void _cancelPolling() {
    _pollTask?.cancel();
    _pollTask = null;
  }

  void _closeUpdates() {
    if (!_updates.isClosed) {
      unawaited(_updates.close());
    }
  }
}
