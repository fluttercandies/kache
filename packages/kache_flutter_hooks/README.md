# kache_flutter_hooks

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[简体中文](README.zh-CN.md)

Flutter Hooks lifecycle binding for Kache. It returns the regular
`KacheController<T>`, so hooks and non-hooks widgets share one cache state
machine and the same command semantics.

## Installation

```bash
flutter pub add kache_flutter_hooks flutter_hooks
```

## Quick start

```dart
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
```

`useKache` resolves the nearest `KacheScope` client. Pass `client:` when a
widget deliberately uses a client outside that scope. The hook automatically
loads, rebuilds from `KacheSnapshot`, updates same-key fetchers and policies,
and disposes its controller.

A client or key change creates a new controller and isolates late results from
the previous binding. A same-key query update preserves the controller and
cached data. The hook never owns or closes the client.

## API

- `useKache<T>(query, client:)` returns `KacheController<T>`.
- `cache.snapshot` is a readable alias for `cache.value`.
- `load`, `refresh`, `setData`, `updateData`, `invalidate`, and `remove` are the
  existing controller commands.

The package re-exports `kache_flutter`, but does not re-export
`flutter_hooks`. Application source using `HookWidget` must declare and import
`flutter_hooks` directly.

## Compatibility

| Component | Supported range |
| --- | --- |
| Dart | Dart >=3.8.0 <4.0.0 |
| Flutter | Flutter >=3.32.0 |
| flutter_hooks | `>=0.21.3+1 <0.22.0` |

## License

MIT
