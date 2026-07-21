# kache_hooks_riverpod

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[简体中文](README.zh-CN.md)

Hooks Riverpod binding for an existing Kache provider. It watches the
provider-owned snapshot and exposes its notifier commands without creating a
second cache resource.

## Installation

```bash
flutter pub add kache_hooks_riverpod hooks_riverpod
```

## Quick start

```dart
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
```

`useKacheProvider` accepts an existing `KacheProvider<T>`. Riverpod remains the
only owner of the underlying `KacheResource`, so family arguments, scopes,
overrides, auto-dispose, keep-alive, observers, and provider subscriptions keep
their native behavior.

The returned `KacheProviderBinding<T>` contains the snapshot and notifier
watched in the current build, plus `load`, `refresh`, `setData`,
`updateData`, `invalidate`, `remove`, `keepAlive`, and `releaseKeepAlive`
delegates.

The quick start marks `clientProvider` as scoped because the application
overrides it in a nested `ProviderScope`, then lists it in `profileProvider`'s
`dependencies`. Keep this Riverpod declaration pattern for any scoped client,
query input, or tenant/session provider.

This package does not create providers and does not map snapshots to
`AsyncValue`. Define providers with `kacheProvider`, then consume them here.
Application code using `HookConsumerWidget` must declare and import
`hooks_riverpod` directly.

## Compatibility

| Component | Supported range |
| --- | --- |
| Dart | Dart >=3.8.0 <4.0.0 |
| Flutter | Flutter >=3.32.0 |
| hooks_riverpod | `>=3.3.2 <4.0.0` |

## License

MIT
