part of 'client.dart';

abstract interface class _KacheResourceBase {
  KacheKey get key;

  Future<void> revalidateAfterClear();

  void dispose();
}

/// A disposable handle that observes and controls one [KacheQuery].
final class KacheResource<T> implements _KacheResourceBase {
  KacheResource._({
    required KacheClient client,
    required _KacheEntry<T> entry,
    required this.query,
  }) : _client = client,
       _entry = entry {
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

  /// The immutable declaration owned by this handle.
  final KacheQuery<T> query;

  @override
  KacheKey get key => query.key;

  final StreamController<KacheSnapshot<T>> _updates =
      StreamController<KacheSnapshot<T>>.broadcast(sync: true);
  late final StreamSubscription<KacheSnapshot<T>> _entrySubscription;
  late final Stream<KacheSnapshot<T>> _stream;
  bool _didStartAutomaticLoad = false;
  bool _isDisposed = false;

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
    return _entry.load(query);
  }

  /// Forces a fetch with this handle's fetcher, ignoring freshness.
  Future<KacheSnapshot<T>> refresh() {
    _ensureActive();
    return _entry.refresh(query);
  }

  /// Replaces current data immediately and persists it when configured.
  Future<KacheSnapshot<T>> setData(T data) {
    _ensureActive();
    return _entry.setData(data, query: query);
  }

  /// Atomically computes and stores data from the latest shared snapshot.
  Future<KacheSnapshot<T>> updateData(
    T Function(KacheSnapshot<T> snapshot) update,
  ) {
    _ensureActive();
    return _entry.updateData(update, query: query);
  }

  /// Marks current data stale and optionally starts a fresh fetch.
  Future<KacheSnapshot<T>> invalidate({bool refetch = true}) {
    _ensureActive();
    return _entry.invalidate(query, refetch: refetch);
  }

  /// Removes current memory and persisted data without fetching.
  Future<KacheSnapshot<T>> remove() {
    _ensureActive();
    return _entry.remove();
  }

  /// Idempotently releases this handle and closes its stream.
  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    unawaited(_entrySubscription.cancel());
    _closeUpdates();
    _client._release(this, _entry);
  }

  @override
  Future<void> revalidateAfterClear() async {
    if (!_isDisposed) {
      await refresh();
    }
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

  void _closeUpdates() {
    if (!_updates.isClosed) {
      unawaited(_updates.close());
    }
  }
}
