import 'package:kache_riverpod/kache_riverpod.dart';

void verifyRiverpodTypes({
  required KacheNotifier<int> notifier,
  required KacheProviderBuilder providerBuilder,
  required KacheProviderFamilyBuilder familyBuilder,
  required KacheAutoDisposeProviderBuilder autoDisposeBuilder,
  required KacheAutoDisposeProviderFamilyBuilder autoDisposeFamilyBuilder,
}) {}

KacheClientBuilder verifyClientBuilder(KacheClientBuilder builder) => builder;

KacheQueryBuilder<int> verifyQueryBuilder(KacheQueryBuilder<int> builder) =>
    builder;

KacheFamilyQueryBuilder<int, String> verifyFamilyQueryBuilder(
  KacheFamilyQueryBuilder<int, String> builder,
) => builder;

KacheProviderBuilder verifyTopLevelBuilder() => kacheProvider;

KacheProvider<int> verifyProvider(KacheProvider<int> provider) => provider;

KacheProviderFamily<int, String> verifyProviderFamily(
  KacheProviderFamily<int, String> family,
) => family;

Future<KacheSnapshot<int>> verifyNotifierRefresh(KacheNotifier<int> notifier) =>
    notifier.refresh();
