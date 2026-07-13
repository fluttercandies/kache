import 'package:kache/kache.dart';
import 'package:riverpod/misc.dart';
import 'package:riverpod/riverpod.dart';

import 'notifier.dart';

/// Riverpod-style builder for Kache notifier providers.
const kacheProvider = KacheProviderBuilder();

/// Creates regular Kache [NotifierProvider] instances.
final class KacheProviderBuilder {
  /// Creates the provider builder.
  const KacheProviderBuilder();

  /// Creates a provider that owns one resource handle, not the client.
  NotifierProvider<KacheNotifier<T>, KacheSnapshot<T>> call<T>({
    required KacheClientBuilder client,
    required KacheQueryBuilder<T> query,
    String? name,
    Iterable<ProviderOrFamily>? dependencies,
    Duration? Function(int retryCount, Object error)? retry,
  }) => NotifierProvider<KacheNotifier<T>, KacheSnapshot<T>>(
    () => KacheNotifier<T>(client: client, query: query),
    name: name,
    dependencies: dependencies,
    retry: retry,
  );

  /// Creates providers parameterized by a Riverpod family argument.
  KacheProviderFamilyBuilder get family => const KacheProviderFamilyBuilder();

  /// Creates auto-dispose Kache notifier providers.
  KacheAutoDisposeProviderBuilder get autoDispose =>
      const KacheAutoDisposeProviderBuilder();
}

/// Creates auto-dispose Kache notifier providers.
final class KacheAutoDisposeProviderBuilder {
  /// Creates the auto-dispose builder.
  const KacheAutoDisposeProviderBuilder();

  /// Creates an auto-dispose provider with optional initial keep-alive.
  NotifierProvider<KacheNotifier<T>, KacheSnapshot<T>> call<T>({
    required KacheClientBuilder client,
    required KacheQueryBuilder<T> query,
    bool keepAlive = false,
    String? name,
    Iterable<ProviderOrFamily>? dependencies,
    Duration? Function(int retryCount, Object error)? retry,
  }) => NotifierProvider.autoDispose<KacheNotifier<T>, KacheSnapshot<T>>(
    () => KacheNotifier<T>(client: client, query: query, keepAlive: keepAlive),
    name: name,
    dependencies: dependencies,
    retry: retry,
  );

  /// Creates auto-dispose providers parameterized by a family argument.
  KacheAutoDisposeProviderFamilyBuilder get family =>
      const KacheAutoDisposeProviderFamilyBuilder();
}

/// Creates auto-dispose Kache notifier provider families.
final class KacheAutoDisposeProviderFamilyBuilder {
  /// Creates the auto-dispose family builder.
  const KacheAutoDisposeProviderFamilyBuilder();

  /// Creates an auto-dispose family whose argument is passed to [query].
  NotifierProviderFamily<KacheNotifier<T>, KacheSnapshot<T>, Arg> call<T, Arg>({
    required KacheClientBuilder client,
    required KacheFamilyQueryBuilder<T, Arg> query,
    bool keepAlive = false,
    String? name,
    Iterable<ProviderOrFamily>? dependencies,
    Duration? Function(int retryCount, Object error)? retry,
  }) => NotifierProvider.autoDispose
      .family<KacheNotifier<T>, KacheSnapshot<T>, Arg>(
        (argument) => KacheNotifier<T>(
          client: client,
          query: (ref) => query(ref, argument),
          keepAlive: keepAlive,
        ),
        name: name,
        dependencies: dependencies,
        retry: retry,
      );
}

/// Creates regular Kache notifier provider families.
final class KacheProviderFamilyBuilder {
  /// Creates the family builder.
  const KacheProviderFamilyBuilder();

  /// Creates a family whose argument is passed to [query].
  NotifierProviderFamily<KacheNotifier<T>, KacheSnapshot<T>, Arg> call<T, Arg>({
    required KacheClientBuilder client,
    required KacheFamilyQueryBuilder<T, Arg> query,
    String? name,
    Iterable<ProviderOrFamily>? dependencies,
    Duration? Function(int retryCount, Object error)? retry,
  }) => NotifierProvider.family<KacheNotifier<T>, KacheSnapshot<T>, Arg>(
    (argument) =>
        KacheNotifier<T>(client: client, query: (ref) => query(ref, argument)),
    name: name,
    dependencies: dependencies,
    retry: retry,
  );
}
