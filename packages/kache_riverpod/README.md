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
  Future<User> searchUser(String text, int page);
}

final class UserProviders {
  UserProviders({required this.client, required this.api});

  final KacheClient client;
  final UserApi api;

  late final search = kacheProvider.autoDispose
      .family<User, ({String text, int page})>(
        client: (_) => client,
        query: (_, args) => KacheQuery<User>.memory(
          key: KacheKey('search', <Object?>[args.text, args.page]),
          fetch: (_) => api.searchUser(args.text, args.page),
        ),
      );
}

Future<void> observeUser(UserApi api, String text, int page) async {
  final client = KacheClient();
  final providers = UserProviders(client: client, api: api);
  final container = ProviderContainer();
  final provider = providers.search((text: text, page: page));
  final subscription = container.listen(
    provider,
    (previous, next) {},
    fireImmediately: true,
  );

  try {
    await container.read(provider.notifier).refresh();
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
  construction. Use a named record for multiple parameters and put every field
  in `KacheKey`.
- `kacheProvider.autoDispose<T>` releases its resource after Riverpod disposes
  the provider.
- `kacheProvider.autoDispose.family<T, Arg>` combines both behaviors.

The builders return native `NotifierProvider` values through the short
`KacheProvider<T>` and `KacheProviderFamily<T, Arg>` aliases. They do not
introduce a parallel provider abstraction.

Client and query callbacks receive `Ref`, so they can watch normal Riverpod
dependencies. When a dependency is overridden in a nested `ProviderScope`,
declare that dependency as scoped and include it in the Kache provider's
`dependencies`, following Riverpod's native scoping contract. A provider owns
one resource handle and never closes its client.

Providers expose `KacheSnapshot<T>` directly. Render with `snapshot.when` so
idle and retained-data refresh failures stay explicit. Kache deliberately does
not convert to `AsyncValue`: that would lose freshness, source, persistence,
and the distinction between cached data refreshing and cached data with an
error.

## Commands and lifecycle

Use the notifier to call `load`, `refresh`, `setData`, `updateData`,
`invalidate`, or `remove`. Inside widget `build`, watch `provider.notifier`
when the notifier or one of its properties contributes to rendered output.
For a command used only by an event, read the notifier inside that event
handler. This follows Riverpod's guidance against capturing `ref.read` values
in `build`. `keepAlive()` and `releaseKeepAlive()` control an auto-dispose
provider's Riverpod keep-alive link without changing core cache GC semantics.

Provider disposal cancels the snapshot subscription and releases the resource.
Late fetch completion cannot emit through a disposed notifier.

`ref.refresh(provider)` and `ref.invalidate(provider)` rebuild the Riverpod
provider and bind a new resource. `ref.read(provider.notifier).refresh()` keeps
the provider and resource identity and only forces a Kache fetch.

`refreshInterval` works while the provider keeps its resource active. In pure
Dart hosts, the client owner controls background timers with `pausePolling()`
and `resumePolling()`.

## Riverpod interoperability

| Riverpod capability | Kache contract |
| --- | --- |
| `watch`, `read`, `listen`, `select` | Native behavior |
| ProviderScope/Container and observers | Native behavior |
| `name` and scoped `dependencies` | Forwarded by every builder |
| family, records, and auto-dispose family | Native family identity |
| `keepAlive` | Explicit notifier link, preserved across dependency rebuilds |
| provider refresh/invalidate | Rebuilds and rebinds the provider resource |
| ProviderSubscription pause/resume | Replays Riverpod's latest missed snapshot |
| `overrideWith` / family `overrideWith2` | Supported with a replacement `KacheNotifier` |
| `overrideWithBuild` | Unsupported because it bypasses Kache resource binding |

Riverpod 3.3.2 exposes a `retry` argument on synchronous `NotifierProvider`,
but its synchronous element does not invoke that callback for build errors.
Kache therefore does not expose a misleading retry option. Client/query build
errors use Riverpod's synchronous provider error channel. Fetch failures are
data in `KacheSnapshot.failure`; compose request retry in the fetcher.

Kache intentionally does not add `AsyncValue` conversion, Riverpod offline
persistence, experimental Mutation wrappers, or code generation. Those would
lose cache state, duplicate persistence ownership, bind unstable APIs, or add
a build system without improving the runtime contract. Application-level
Riverpod mutations can call notifier commands directly.

## Flutter

Wrap the app in `ProviderScope`. A `Consumer` watches the Kache provider; it
either watches the notifier as a build dependency or reads it inside a command
event handler. Use `KacheScope` from `kache_flutter` when the application also
needs lifecycle-aware polling and resume revalidation.

For `HookConsumerWidget`, add `kache_hooks_riverpod` and call
`useKacheProvider(ref, provider)`. It consumes this existing provider instead
of creating another resource.

## Compatibility

| Component | Supported range |
| --- | --- |
| Dart | Dart >=3.7.0 <4.0.0 |
| Flutter | Not required |
| Riverpod | `>=3.3.2 <4.0.0` |

## License

MIT
