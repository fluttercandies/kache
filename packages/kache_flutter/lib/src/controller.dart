import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kache/kache.dart';

/// Adapts a core [KacheResource] to Flutter's [ValueListenable] contract.
final class KacheController<T> extends ChangeNotifier
    implements ValueListenable<KacheSnapshot<T>> {
  /// Creates a controller and starts loading when its resource stream is bound.
  KacheController({required this.client, required KacheQuery<T> query})
    : _query = query {
    _bind(query);
  }

  /// The client that owns this controller's resource handles.
  final KacheClient client;

  KacheQuery<T> _query;
  late KacheResource<T> _resource;
  late KacheSnapshot<T> _value;
  StreamSubscription<KacheSnapshot<T>>? _subscription;
  int _bindingGeneration = 0;
  bool _isDisposed = false;

  /// The query currently used by this controller.
  KacheQuery<T> get query => _query;

  /// The underlying core resource.
  KacheResource<T> get resource => _resource;

  @override
  KacheSnapshot<T> get value => _value;

  /// Whether [dispose] has released the resource.
  bool get isDisposed => _isDisposed;

  /// Updates the query without reloading when its key remains unchanged.
  void updateQuery(KacheQuery<T> query) {
    _ensureActive();
    if (query.key == _query.key) {
      _resource.updateQuery(query);
      _query = query;
      return;
    }
    _unbind();
    _query = query;
    _bind(query);
    notifyListeners();
  }

  /// Loads cache data and applies [query]'s load policy.
  Future<KacheSnapshot<T>> load() {
    _ensureActive();
    return _run(_resource.load());
  }

  /// Forces a refresh with [query]'s fetcher.
  Future<KacheSnapshot<T>> refresh() {
    _ensureActive();
    return _run(_resource.refresh());
  }

  /// Replaces the current value.
  Future<KacheSnapshot<T>> setData(T data) {
    _ensureActive();
    return _run(_resource.setData(data));
  }

  /// Atomically updates data from the latest shared snapshot.
  Future<KacheSnapshot<T>> updateData(
    T Function(KacheSnapshot<T> snapshot) update,
  ) {
    _ensureActive();
    return _run(_resource.updateData(update));
  }

  /// Marks current data stale and optionally refreshes it.
  Future<KacheSnapshot<T>> invalidate({bool refetch = true}) {
    _ensureActive();
    return _run(_resource.invalidate(refetch: refetch));
  }

  /// Removes current memory and persisted data.
  Future<KacheSnapshot<T>> remove() {
    _ensureActive();
    return _run(_resource.remove());
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _unbind();
    super.dispose();
  }

  void _bind(KacheQuery<T> query) {
    final generation = ++_bindingGeneration;
    _resource = client.watch(query);
    _value = _resource.snapshot;
    _subscription = _resource.stream.listen((snapshot) {
      if (_isDisposed || generation != _bindingGeneration) {
        return;
      }
      _accept(snapshot);
    });
  }

  void _unbind() {
    _bindingGeneration += 1;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    _resource.dispose();
  }

  void _ensureActive() {
    if (_isDisposed) {
      throw const KacheLifecycleException(
        'controller_disposed',
        'The Kache controller is disposed.',
      );
    }
  }

  Future<KacheSnapshot<T>> _run(Future<KacheSnapshot<T>> operation) async {
    final snapshot = await operation;
    if (!_isDisposed) {
      _accept(snapshot);
    }
    return snapshot;
  }

  void _accept(KacheSnapshot<T> snapshot) {
    if (identical(_value, snapshot)) {
      return;
    }
    _value = snapshot;
    notifyListeners();
  }
}
