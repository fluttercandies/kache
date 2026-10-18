# kache

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[简体中文](README.zh-CN.md)

The dependency-free Dart core of Kache. It provides typed cache keys, query
policies, stale-while-revalidate snapshots, deterministic concurrency,
cooperative cancellation, cache commands, events, and persistence contracts.

## Installation

```bash
dart pub add kache
```

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
  required void Function(String) render,
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
  final subscription = resource.stream.listen(
    (snapshot) => render(
      snapshot.when(
        idle: () => 'Idle',
        loading: () => 'Loading',
        ready: (user) => user.name,
        refreshError: (user, _) => '${user.name} (refresh failed)',
        failed: (_) => 'Could not load user',
      ),
    ),
  );

  try {
    await resource.load();
  } finally {
    await subscription.cancel();
    resource.dispose();
    await client.close();
  }
}
```

The first listener receives the current snapshot immediately. `when` requires
idle, loading, ready, retained-data refresh error, and no-data failure branches.
It keeps cached data in `ready` while refreshing by default and never silently
hides a refresh failure. Use `maybeWhen` for partial handling and `mapData` to
transform visible data without losing cache metadata or operation state.

## Queries and keys

Put every fetch parameter in `KacheKey`. Supported key parts are `null`, bool,
safe integer-valued numbers, valid Unicode strings, and `Uint8List`. Arbitrary
objects and implicit `toString()` conversion are rejected.

Use `KacheQuery.memory`, `KacheQuery.persisted`, or
`KacheQuery.networkOnly`. Persisted queries require a binding from the same
backend configured on the client.

## Policy guide

- `staleWhileRevalidate`: show cache, then revalidate by default.
- `cacheFirst`: skip requests while data is fresh.
- `cacheOnly`: never fetch automatically; a provided fetcher may still be used
  by explicit `refresh()`.
- `networkOnly`: keep state only for the active handle and always fetch.

Hard-expired data is deleted and never emitted. By default, a refresh error
retains visible data.

Set `refreshInterval` to poll after the first load while the handle remains
active. Same-key handles still share one fetch. Client owners can call
`pausePolling()` and `resumePolling()` without affecting manual commands.
`KacheQuery.networkOnly` accepts the same interval without enabling storage.

## Commands

`KacheResource` exposes `load`, `refresh`, `setData`, `updateData`,
`invalidate`, `remove`, and `cancel`. `KacheClient` adds `prefetch`, `peek`,
`cancel(key)`, `cancelAll`, namespace clear, global clear, active-resource
refresh, and resume revalidation.

Configure an optional `KacheNetwork` to revalidate after an
`unavailable -> available` transition. Each handle keeps its own
`refreshOnReconnect` policy, while same-key fetches remain single-flight.
`pauseReconnect()` and `resumeReconnect()` defer one pending recovery without
stopping state observation. Platform adapters belong in separate packages.

Same-key fetches are single-flight. Writes are serialized per key. Generation
and namespace/global epochs prevent stale work from restoring removed data.

## Persistence contract

Implement `KachePersistenceBackend` to connect any storage system. The core
passes typed `T` values, an opaque `KachePersistenceBinding<T>`, and
`KachePersistedMetadata`. Serialization, codecs, format migration, encryption,
and physical records belong to the backend package, not this package.

The core may call `read` and `write` inside a listener's synchronous stack,
such as a widget build that subscribes to a resource. Work that runs before
the returned future first yields must not grow with payload size; decode,
encode, or copy large values after an asynchronous gap, for example on another
isolate. Where that work runs is up to the backend.

`MemoryKachePersistence` is a process-local reference implementation. For
restart-safe storage, use `kache_hive_ce` or a custom backend.

## Errors and events

Expected failures are represented by `KacheFailure` in snapshots and command
results. The original cause and stack trace are retained, while string output
is sanitized. Configuration and lifecycle misuse throw immediately.

Observe `KacheClient.events` for telemetry. Observer failures cannot interrupt
the cache state machine. Events use `kind + phase + trigger`, paired span and
trace ids, scope, timing, revision, and query context. Successful cache hits,
reads, fetches, writes, and sets may expose the original typed object through
`requireData<T>()`, including a nullable `null` distinguished by `hasData`.

This is a trusted in-process channel. Kache never logs or uploads it, and the
sanitized `toString()` omits data, key, metadata, causes, and stack traces.
Subscribers own filtering, mapping, redaction, printing, and export.

## Cancellation

Same-key fetches are shared, so `resource.cancel()` and `client.cancel(key)`
logically cancel every waiter for that key; `client.cancelAll()` counts keys.
The command restores the pre-fetch snapshot without deleting data or stopping
future polling. A non-cooperative Future may continue in the background, but
its late value or error cannot update state or emit a fetch failure.

Fetchers can bridge `context.cancellation.whenCancelled` to an HTTP cancel
token or abort controller. `context.throwIfCancelled()` exposes the precise
reason. Setting data, invalidating, removing, clearing, and closing also cancel
conflicting work with their own reasons. Disposing one handle does not cancel a
request shared by other handles.

## Ownership

A resource handle is released only by `resource.dispose()`. Stream
subscription cancellation is independent. `KacheClient.close()` cancels
fetches, drains or discards queued writes according to `drainWrites`, closes
streams, and closes only an owned persistence backend. An owned network source
is also closed exactly once. Connectivity failures are observable as
`KacheFailureKind.connectivity` events and never clear data.

## Compatibility

| Component | Supported range |
| --- | --- |
| Dart | Dart >=3.5.0 <4.0.0 |
| Flutter | Not required |

## License

MIT
