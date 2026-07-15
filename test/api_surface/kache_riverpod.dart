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

Future<KacheSnapshot<int>> verifyNotifierRefresh(KacheNotifier<int> notifier) =>
    notifier.refresh();
