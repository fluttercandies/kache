import 'dart:async';

import 'package:kache/kache.dart';

/// Receives snapshots from a [KacheBlocBinding].
typedef KacheBlocSnapshotListener<T> = void Function(KacheSnapshot<T> snapshot);

/// Composes one core resource into an existing Bloc or Cubit.
///
/// A binding owns its resource handle and one managed listener. It never owns
/// or closes the client supplied to its constructor.
final class KacheBlocBinding<T> {
  /// Creates a detached binding. Call [attach] to start automatic loading.
  KacheBlocBinding({required KacheClient client, required KacheQuery<T> query})
      : _resource = client.watch(query);

  final KacheResource<T> _resource;
  StreamSubscription<KacheSnapshot<T>>? _subscription;
  KacheBlocSnapshotListener<T>? _listener;
  bool _isClosing = false;
  Future<void>? _closeFuture;

  /// The core resource owned by this binding.
  KacheResource<T> get resource => _resource;

  /// The query currently bound to [resource].
  KacheQuery<T> get query => _resource.query;

  /// The current resource snapshot, available before [attach].
  KacheSnapshot<T> get snapshot => _resource.snapshot;

  /// Whether [close] has started.
  bool get isClosed => _isClosing;

  /// Attaches the single managed snapshot listener and starts loading.
  void attach(KacheBlocSnapshotListener<T> listener) {
    _ensureActive();
    if (_subscription != null) {
      throw const KacheConfigurationException(
        'bloc_binding_already_attached',
        'A Kache Bloc binding supports one managed listener.',
      );
    }
    _listener = listener;
    _subscription = _resource.stream.listen((snapshot) {
      if (!_isClosing) {
        _listener?.call(snapshot);
      }
    });
  }

  /// Loads persistence and applies the query's load policy.
  Future<KacheSnapshot<T>> load() => _run(_resource.load);

  /// Forces a fetch while retaining cached data according to policy.
  Future<KacheSnapshot<T>> refresh() => _run(_resource.refresh);

  /// Replaces the current value immediately.
  Future<KacheSnapshot<T>> setData(T data) =>
      _run(() => _resource.setData(data));

  /// Atomically updates data from the latest shared snapshot.
  Future<KacheSnapshot<T>> updateData(
    T Function(KacheSnapshot<T> snapshot) update,
  ) =>
      _run(() => _resource.updateData(update));

  /// Marks current data stale and optionally starts a fetch.
  Future<KacheSnapshot<T>> invalidate({bool refetch = true}) =>
      _run(() => _resource.invalidate(refetch: refetch));

  /// Removes current memory and persisted data without fetching.
  Future<KacheSnapshot<T>> remove() => _run(_resource.remove);

  /// Cancels the managed listener and releases the resource handle.
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    _isClosing = true;
    final future = _performClose();
    _closeFuture = future;
    return future;
  }

  Future<KacheSnapshot<T>> _run(Future<KacheSnapshot<T>> Function() command) {
    _ensureActive();
    return command();
  }

  void _ensureActive() {
    if (_isClosing) {
      throw const KacheLifecycleException(
        'bloc_binding_closed',
        'The Kache Bloc binding is closed.',
      );
    }
  }

  Future<void> _performClose() async {
    final subscription = _subscription;
    _subscription = null;
    _listener = null;
    if (subscription != null) {
      await subscription.cancel();
    }
    _resource.dispose();
  }
}
