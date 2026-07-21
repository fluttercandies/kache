import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:kache_flutter_hooks/kache_flutter_hooks.dart';

typedef Profile = ({String name});

final class ProfilePage extends HookWidget {
  const ProfilePage({required this.query, super.key});

  final KacheQuery<Profile> query;

  @override
  Widget build(BuildContext context) {
    final cache = useKache(query);
    return cache.snapshot.when(
      idle: () => const SizedBox.shrink(),
      loading: () => const Center(child: CircularProgressIndicator()),
      failed: (_) =>
          FilledButton(onPressed: cache.load, child: const Text('Try again')),
      ready: (profile) => ListTile(
        title: Text(profile.name),
        trailing: cache.snapshot.isRefreshing
            ? const CircularProgressIndicator()
            : IconButton(
                onPressed: cache.refresh,
                icon: const Icon(Icons.refresh),
              ),
      ),
      refreshError: (profile, _) => ListTile(
        title: Text(profile.name),
        subtitle: const Text('Refresh failed - showing cached data'),
        trailing: IconButton(
          onPressed: cache.refresh,
          icon: const Icon(Icons.refresh),
        ),
      ),
    );
  }
}

Widget createProfileApp({required Future<Profile> Function() fetchProfile}) {
  final client = KacheClient();
  return KacheScope(
    client: client,
    ownership: KacheScopeOwnership.owned,
    child: MaterialApp(
      home: ProfilePage(
        query: KacheQuery<Profile>.memory(
          key: KacheKey('profile'),
          fetch: (_) => fetchProfile(),
        ),
      ),
    ),
  );
}
