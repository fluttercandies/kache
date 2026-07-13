import 'dart:async';

import 'package:kache/kache.dart';
import 'package:riverpod/misc.dart';
import 'package:riverpod/riverpod.dart';

/// Resolves the cache client from a Riverpod [Ref].
typedef KacheClientBuilder = KacheClient Function(Ref ref);

/// Builds a cache query from a Riverpod [Ref].
typedef KacheQueryBuilder<T> = KacheQuery<T> Function(Ref ref);

/// Builds a cache query from a Riverpod family argument.
typedef KacheFamilyQueryBuilder<T, Arg> =
    KacheQuery<T> Function(Ref ref, Arg argument);

/// A Riverpod notifier backed by exactly one core [KacheResource].
///
/// Use the top-level `kacheProvider` builder to construct providers. The
/// notifier exposes the full [KacheSnapshot] so cached data, refresh progress,
/// and failures can coexist.
final class KacheNotifier<T> extends Notifier<KacheSnapshot<T>> {
  /// Creates a notifier for the supplied client and query builders.
  KacheNotifier({
    required KacheClientBuilder client,
    required KacheQueryBuilder<T> query,
    bool keepAlive = false,
  }) : _clientBuilder = client,
       _queryBuilder = query,
       _keepAliveInitially = keepAlive;

  final KacheClientBuilder _clientBuilder;
  final KacheQueryBuilder<T> _queryBuilder;
  final bool _keepAliveInitially;
  KacheResource<T>? _resource;
  KeepAliveLink? _keepAliveLink;

  /// The resource bound by the current provider build.
  KacheResource<T> get resource => _requireResource();

  /// The query bound by the current provider build.
  KacheQuery<T> get query => _requireResource().query;

  /// Whether this notifier currently holds a Riverpod keep-alive link.
  bool get isKeptAlive => _keepAliveLink != null;

  @override
  KacheSnapshot<T> build() {
    final resource = _clientBuilder(ref).watch(_queryBuilder(ref));
    _resource = resource;
    if (_keepAliveInitially) {
      keepAlive();
    }
    StreamSubscription<KacheSnapshot<T>>? subscription;
    scheduleMicrotask(() {
      if (!ref.mounted || !identical(_resource, resource)) {
        return;
      }
      subscription = resource.stream.listen((snapshot) {
        if (ref.mounted && identical(_resource, resource)) {
          state = snapshot;
        }
      });
    });
    ref.onDispose(() {
      _keepAliveLink?.close();
      _keepAliveLink = null;
      final activeSubscription = subscription;
      if (activeSubscription != null) {
        unawaited(activeSubscription.cancel());
      }
      resource.dispose();
      if (identical(_resource, resource)) {
        _resource = null;
      }
    });
    return resource.snapshot;
  }

  /// Forces a fetch while preserving cached data according to policy.
  Future<KacheSnapshot<T>> refresh() => _requireResource().refresh();

  /// Loads persistence and applies the query's load policy.
  Future<KacheSnapshot<T>> load() => _requireResource().load();

  /// Replaces the current value immediately.
  Future<KacheSnapshot<T>> setData(T data) => _requireResource().setData(data);

  /// Atomically updates data from the latest shared snapshot.
  Future<KacheSnapshot<T>> updateData(
    T Function(KacheSnapshot<T> snapshot) update,
  ) => _requireResource().updateData(update);

  /// Marks current data stale and optionally starts a fetch.
  Future<KacheSnapshot<T>> invalidate({bool refetch = true}) =>
      _requireResource().invalidate(refetch: refetch);

  /// Removes current memory and persisted data without fetching.
  Future<KacheSnapshot<T>> remove() => _requireResource().remove();

  /// Keeps an auto-dispose provider alive after its final listener is removed.
  void keepAlive() {
    _ensureMounted();
    _keepAliveLink ??= ref.keepAlive();
  }

  /// Releases the current keep-alive link, if any.
  void releaseKeepAlive() {
    _keepAliveLink?.close();
    _keepAliveLink = null;
  }

  KacheResource<T> _requireResource() {
    final resource = _resource;
    if (resource == null) {
      _throwDisposed();
    }
    _ensureMounted();
    return resource;
  }

  void _ensureMounted() {
    if (!ref.mounted) {
      _throwDisposed();
    }
  }

  Never _throwDisposed() {
    throw const KacheLifecycleException(
      'riverpod_notifier_disposed',
      'The Kache Riverpod notifier is disposed.',
    );
  }
}
