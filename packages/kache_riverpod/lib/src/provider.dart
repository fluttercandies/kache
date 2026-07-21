import 'package:kache/kache.dart';
import 'package:riverpod/misc.dart';
import 'package:riverpod/riverpod.dart';

import 'notifier.dart';

/// Riverpod-style builder for Kache notifier providers.
const kacheProvider = KacheProviderBuilder();

/// A Riverpod provider exposing a Kache snapshot and notifier.
typedef KacheProvider<T> = NotifierProvider<KacheNotifier<T>, KacheSnapshot<T>>;

/// A parameterized family of Kache providers.
typedef KacheProviderFamily<T, Arg> =
    NotifierProviderFamily<KacheNotifier<T>, KacheSnapshot<T>, Arg>;

/// Creates regular Kache [NotifierProvider] instances.
final class KacheProviderBuilder {
  /// Creates the provider builder.
  const KacheProviderBuilder();

  /// Creates a provider that owns one resource handle, not the client.
  KacheProvider<T> call<T>({
    required KacheClientBuilder client,
    required KacheQueryBuilder<T> query,
    String? name,
    Iterable<ProviderOrFamily>? dependencies,
  }) => NotifierProvider<KacheNotifier<T>, KacheSnapshot<T>>(
    () => KacheNotifier<T>(client: client, query: query),
    name: name,
    dependencies: dependencies,
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
  KacheProvider<T> call<T>({
    required KacheClientBuilder client,
    required KacheQueryBuilder<T> query,
    bool keepAlive = false,
    String? name,
    Iterable<ProviderOrFamily>? dependencies,
  }) => NotifierProvider.autoDispose<KacheNotifier<T>, KacheSnapshot<T>>(
    () => KacheNotifier<T>(client: client, query: query, keepAlive: keepAlive),
    name: name,
    dependencies: dependencies,
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
  KacheProviderFamily<T, Arg> call<T, Arg>({
    required KacheClientBuilder client,
    required KacheFamilyQueryBuilder<T, Arg> query,
    bool keepAlive = false,
    String? name,
    Iterable<ProviderOrFamily>? dependencies,
  }) => NotifierProvider.autoDispose
      .family<KacheNotifier<T>, KacheSnapshot<T>, Arg>(
        (argument) => KacheNotifier<T>(
          client: client,
          query: (ref) => query(ref, argument),
          keepAlive: keepAlive,
        ),
        name: name,
        dependencies: dependencies,
      );
}

/// Creates regular Kache notifier provider families.
final class KacheProviderFamilyBuilder {
  /// Creates the family builder.
  const KacheProviderFamilyBuilder();

  /// Creates a family whose argument is passed to [query].
  KacheProviderFamily<T, Arg> call<T, Arg>({
    required KacheClientBuilder client,
    required KacheFamilyQueryBuilder<T, Arg> query,
    String? name,
    Iterable<ProviderOrFamily>? dependencies,
  }) => NotifierProvider.family<KacheNotifier<T>, KacheSnapshot<T>, Arg>(
    (argument) =>
        KacheNotifier<T>(client: client, query: (ref) => query(ref, argument)),
    name: name,
    dependencies: dependencies,
  );
}
