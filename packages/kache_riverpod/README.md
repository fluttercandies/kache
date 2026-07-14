# kache_riverpod

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[简体中文](README.zh-CN.md)

Riverpod providers and notifiers backed by the Kache core state machine. The
complete state is always `KacheSnapshot<T>`, preserving cached data, refresh
progress, freshness, persistence state, and failures together.

## Installation

```bash
dart pub add kache_riverpod riverpod
```

Flutter UI that imports Riverpod widgets should declare `flutter_riverpod`
directly instead of relying on a transitive dependency.

## Quick start

```dart
import 'dart:async';

import 'package:kache_riverpod/kache_riverpod.dart';
import 'package:riverpod/riverpod.dart';

final class User {
  const User(this.id, this.name);

  final String id;
  final String name;
}

abstract interface class UserApi {
  Future<User> fetchUser(String id);
}

final class UserProviders {
  UserProviders({required this.client, required this.api});

  final KacheClient client;
  final UserApi api;

  late final user = kacheProvider.autoDispose.family<User, String>(
    client: (_) => client,
    query: (_, userId) => KacheQuery<User>.memory(
      key: KacheKey('users', <Object?>[userId]),
      fetch: (_) => api.fetchUser(userId),
    ),
  );
}

Future<void> observeUser(UserApi api, String userId) async {
  final client = KacheClient();
  final providers = UserProviders(client: client, api: api);
  final container = ProviderContainer();
  final subscription = container.listen(
    providers.user(userId),
    (previous, next) {},
    fireImmediately: true,
  );

  try {
    await container.read(providers.user(userId).notifier).refresh();
  } finally {
    subscription.close();
    container.dispose();
    await client.close();
  }
}
```

## Provider builders

- `kacheProvider<T>` creates a regular notifier provider.
- `kacheProvider.family<T, Arg>` puts a Riverpod family argument into query
  construction. Put the same argument in `KacheKey`.
- `kacheProvider.autoDispose<T>` releases its resource after Riverpod disposes
  the provider.
- `kacheProvider.autoDispose.family<T, Arg>` combines both behaviors.

Client and query callbacks receive `Ref`, so they can watch normal Riverpod
dependencies. A provider owns one resource handle and never closes its client.

## Commands and lifecycle

Read the notifier to call `load`, `refresh`, `setData`, `updateData`,
`invalidate`, or `remove`. `keepAlive()` and `releaseKeepAlive()` control an
auto-dispose provider's Riverpod keep-alive link without changing core cache
GC semantics.

Provider disposal cancels the snapshot subscription and releases the resource.
Late fetch completion cannot emit through a disposed notifier.

`refreshInterval` works while the provider keeps its resource active. In pure
Dart hosts, the client owner controls background timers with `pausePolling()`
and `resumePolling()`.

## Flutter

Wrap the app in `ProviderScope`. A `Consumer` can watch the Kache provider and
read its notifier for commands. Use `KacheScope` from `kache_flutter` when the
application also needs lifecycle-aware polling and resume revalidation.

## Compatibility

| Component | Supported range |
| --- | --- |
| Dart | Dart >=3.9.0 <4.0.0 |
| Flutter | Flutter >=3.35.0 |
| Hive CE | `>=2.19.3 <3.0.0` |
| Riverpod | `>=3.3.2 <4.0.0` |
| Bloc | `>=9.2.1 <10.0.0` |
| Provider | `>=6.1.5+1 <7.0.0` |

## License

MIT
