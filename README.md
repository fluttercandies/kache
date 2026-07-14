# Kache

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[简体中文](README.zh-CN.md)

Kache is a type-safe stale-while-revalidate cache for Dart and Flutter. It can
show the last usable value immediately, refresh in the background, preserve
data when refresh fails, and expose the complete operation state to any UI or
state-management layer.

The core package has no third-party runtime dependency. Persistence, Flutter,
and state-management integrations are separate packages.

## Packages

| Package | Purpose | Runtime boundary |
| --- | --- | --- |
| `kache` | Cache state machine, concurrency, policies, memory backend | Dart SDK only |
| `kache_flutter` | Scope, controller, builder, listener, app lifecycle | Flutter + `kache` |
| `kache_hive_ce` | Versioned Hive CE persistence, codecs, migrations | Hive CE + `kache` |
| `kache_connectivity_plus` | Automatic reconnect revalidation | connectivity_plus + `kache` |
| `kache_riverpod` | Provider/family/auto-dispose notifier integration | Riverpod + `kache` |
| `kache_bloc` | `KacheCubit` and composable binding | Bloc + `kache` |
| `kache_provider` | Provider widgets and context helpers | Provider + `kache_flutter` |

Choose one top-level integration package in application code. Add a lower
level package only when your source imports it directly, such as
`kache_hive_ce` for persistence or `flutter_bloc` for Bloc widgets.

## Quick start

```dart
import 'dart:async';

import 'package:kache/kache.dart';

final class User {
  const User(this.id, this.name);

  final String id;
  final String name;
}

abstract interface class UserApi {
  Future<User> fetchUser(String id);
}

Future<void> showUser({
  required UserApi api,
  required String userId,
  required void Function(KacheSnapshot<User>) render,
}) async {
  final client = KacheClient();
  final query = KacheQuery<User>.memory(
    key: KacheKey('users', <Object?>[userId]),
    fetch: (context) async {
      context.throwIfCancelled();
      return api.fetchUser(userId);
    },
    policy: KachePolicy.staleWhileRevalidate(),
  );
  final resource = client.watch(query);
  final subscription = resource.stream.listen(render);

  try {
    await resource.load();
  } finally {
    await subscription.cancel();
    resource.dispose();
    await client.close();
  }
}
```

Listening to `resource.stream` replays the current snapshot and starts the
first load once. Cached data stays visible while `isRefreshing` is true. A
refresh failure is available in `snapshot.failure` without removing data when
`retainDataOnError` is enabled.

Use `isLoading`, `isReady`, `isFailed`, `isStale`, and `hasFailure` for common
UI checks without flattening the complete snapshot state.

## Policy guide

| Requirement | Policy |
| --- | --- |
| Show cached data and refresh on load/resume | `KachePolicy.staleWhileRevalidate()` |
| Avoid requests during a fresh window | `KachePolicy.cacheFirst(freshFor: ...)` |
| Never fetch automatically | `KachePolicy.cacheOnly()` |
| Always fetch and do not cache | `KacheQuery.networkOnly(...)` |

`staleAfter` controls freshness. `expireAfter` is a hard boundary after which
data is removed instead of emitted. `gcAfter` controls how long an unreferenced
in-memory entry remains available.

Set `refreshInterval` to poll only while a resource handle is loaded and
active. Same-key polling remains single-flight. `pausePolling()` and
`resumePolling()` control timers without disabling manual cache commands.
`KacheQuery.networkOnly` accepts the same interval without enabling a cache.

## Network recovery

The core accepts any `KacheNetwork` implementation and remains Dart SDK-only.
When a configured source changes from `unavailable` to `available`, active
handles apply their own `refreshOnReconnect` policy. Reconnect requests are
single-flight and coalesce to at most one trailing pass.

Flutter apps can use `kache_connectivity_plus` as the official adapter. Network
interface availability is only a retry signal, not proof that the Internet or
an endpoint is reachable. Source errors are reported as connectivity events
without discarding cached data.

## Persistence

`KacheClient()` is memory-only. To survive restarts, configure a
`KachePersistenceBackend` and create persisted queries with a binding owned by
that backend. The official implementation is `kache_hive_ce`.

Serialization is intentionally not part of the core package. A storage
adapter owns codecs, physical records, schema versions, migrations, encryption
configuration, and corruption handling. The core only receives typed values
and cache metadata.

## Custom persistence

Implement `KachePersistenceBackend` for SQLite, Isar, files, secure storage, or
another system. Your backend must:

- return typed `KachePersistenceRead<T>` values;
- validate that a binding belongs to the backend;
- preserve `KachePersistedMetadata`;
- implement exact namespace-prefix clearing;
- wrap I/O and codec errors in `KachePersistenceException`;
- define idempotent ownership and `close()` behavior.

Use `MemoryKachePersistence` and the contract tests as a reference. Do not add
codec methods to `KacheQuery` or the core persistence protocol.

## Error handling

Snapshots carry failures as data. Streams do not use `addError` for expected
fetch or persistence failures. `KacheFailure` retains the original cause and
stack trace while its `toString()` stays sanitized. Command-oriented code can
call `snapshot.throwIfFailed()` or `clearResult.throwIfFailed()`.

Subscribe to `KacheClient.events` or provide an observer for logging and
telemetry. Events never include payloads or raw key values by default.
`cacheHit`, `cacheMiss`, and `cacheExpired` identify their `memory` or
`persistence` layer without changing resource state.

## Lifecycle

Every `client.watch(query)` returns an independently disposable
`KacheResource`. Canceling a stream listener does not dispose the resource.
Release the handle with `resource.dispose()`, then close clients and owned
backends at the application boundary.

Flutter applications should use `KacheScope`, which can own the client and
pause polling outside the foreground before revalidating active resources when
the app resumes. It also defers reconnect work outside the foreground and
consumes one pending recovery on resume. State adapters own their resource
handles but never own the supplied client.

## Compatibility

| Component | Supported range |
| --- | --- |
| Dart | Dart >=3.9.0 <4.0.0 |
| Flutter | Flutter >=3.35.0 |
| Hive CE | `>=2.19.3 <3.0.0` |
| connectivity_plus | `>=6.1.5 <7.0.0` |
| Riverpod | `>=3.3.2 <4.0.0` |
| Bloc | `>=9.2.1 <10.0.0` |
| Provider | `>=6.1.5+1 <7.0.0` |

## Examples

The `examples/` directory contains runnable Flutter, Riverpod, Bloc/Cubit, and
Provider applications. Each uses the GitHub repository API and Hive CE to
demonstrate cold loading, disk-cache-first restart, refresh, reconnect
revalidation, retained data on failure, and explicit cache clearing.

## License

Kache is available under the MIT License.
