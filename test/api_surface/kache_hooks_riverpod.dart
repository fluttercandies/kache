import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kache_hooks_riverpod/kache_hooks_riverpod.dart';

KacheProviderBinding<int> verifyUseKacheProvider(
  WidgetRef ref,
  KacheProvider<int> provider,
) => useKacheProvider(ref, provider);

Future<KacheSnapshot<int>> verifyBindingRefresh(
  KacheProviderBinding<int> binding,
) => binding.refresh();
