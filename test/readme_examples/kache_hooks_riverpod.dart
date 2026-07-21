import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kache_hooks_riverpod/kache_hooks_riverpod.dart';

typedef Profile = ({String name});

final clientProvider = Provider<KacheClient>((ref) {
  throw StateError('Override clientProvider at the application boundary.');
}, dependencies: const []);

final profileProvider = kacheProvider<Profile>(
  client: (ref) => ref.watch(clientProvider),
  query: (ref) => KacheQuery<Profile>.memory(
    key: KacheKey('profile'),
    fetch: (_) async => (name: 'Ada'),
  ),
  dependencies: [clientProvider],
);

final class ProfilePage extends HookConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = useKacheProvider(ref, profileProvider);
    return cache.snapshot.when(
      idle: () => const SizedBox.shrink(),
      loading: () => const Center(child: CircularProgressIndicator()),
      failed: (_) =>
          FilledButton(onPressed: cache.load, child: const Text('Try again')),
      ready: (profile) => ListTile(
        title: Text(profile.name),
        trailing: IconButton(
          onPressed: cache.refresh,
          icon: const Icon(Icons.refresh),
        ),
      ),
      refreshError: (profile, _) => ListTile(
        title: Text(profile.name),
        subtitle: const Text('Refresh failed - showing cached data'),
      ),
    );
  }
}

Widget createProfileApp() {
  final client = KacheClient();
  return ProviderScope(
    overrides: [clientProvider.overrideWithValue(client)],
    child: const MaterialApp(home: ProfilePage()),
  );
}
