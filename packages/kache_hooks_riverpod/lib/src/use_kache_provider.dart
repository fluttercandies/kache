import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kache_riverpod/kache_riverpod.dart';

/// A snapshot and its provider-owned Kache commands.
final class KacheProviderBinding<T> {
  const KacheProviderBinding._({
    required this.snapshot,
    required this.notifier,
  });

  /// The snapshot watched during the current widget build.
  final KacheSnapshot<T> snapshot;

  /// The notifier that owns the provider's single resource handle.
  final KacheNotifier<T> notifier;

  /// The query currently bound by the provider.
  KacheQuery<T> get query => notifier.query;

  /// The provider-owned core resource.
  KacheResource<T> get resource => notifier.resource;

  /// Whether the provider currently requests Riverpod keep-alive.
  bool get isKeptAlive => notifier.isKeptAlive;

  /// Loads persistence and applies the query policy.
  Future<KacheSnapshot<T>> load() => notifier.load();

  /// Forces a Kache fetch without rebuilding the provider.
  Future<KacheSnapshot<T>> refresh() => notifier.refresh();

  /// Replaces the current value.
  Future<KacheSnapshot<T>> setData(T data) => notifier.setData(data);

  /// Atomically updates data from the latest shared snapshot.
  Future<KacheSnapshot<T>> updateData(
    T Function(KacheSnapshot<T> snapshot) update,
  ) => notifier.updateData(update);

  /// Marks data stale and optionally starts a fetch.
  Future<KacheSnapshot<T>> invalidate({bool refetch = true}) =>
      notifier.invalidate(refetch: refetch);

  /// Removes current memory and persisted data.
  Future<KacheSnapshot<T>> remove() => notifier.remove();

  /// Keeps an auto-dispose provider alive without changing Kache GC policy.
  void keepAlive() => notifier.keepAlive();

  /// Releases a manually requested Riverpod keep-alive link.
  void releaseKeepAlive() => notifier.releaseKeepAlive();
}

/// Watches an existing Kache provider from a [HookConsumerWidget].
///
/// This hook never creates a resource. The provider remains the single owner,
/// preserving Riverpod overrides, families, auto-dispose, and scoping. Both
/// the snapshot and notifier are tracked as build dependencies.
KacheProviderBinding<T> useKacheProvider<T>(
  WidgetRef ref,
  KacheProvider<T> provider,
) {
  final snapshot = ref.watch(provider);
  final notifier = ref.watch(provider.notifier);
  return useMemoized(
    () => KacheProviderBinding<T>._(snapshot: snapshot, notifier: notifier),
    <Object?>[snapshot, notifier],
  );
}
