# kache

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

The first listener receives the current snapshot immediately. A cached value
can coexist with `isRefreshing` and `failure`, so UIs never need to discard
usable data while a background operation is running or has failed.

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

## Commands

`KacheResource` exposes `load`, `refresh`, `setData`, `updateData`,
`invalidate`, and `remove`. `KacheClient` adds `prefetch`, `peek`, namespace
clear, global clear, active-resource refresh, and resume revalidation.

Same-key fetches are single-flight. Writes are serialized per key. Generation
and namespace/global epochs prevent stale work from restoring removed data.

## Persistence contract

Implement `KachePersistenceBackend` to connect any storage system. The core
passes typed `T` values, an opaque `KachePersistenceBinding<T>`, and
`KachePersistedMetadata`. Serialization, codecs, schema migration, encryption,
and physical records belong to the backend package, not this package.

`MemoryKachePersistence` is a process-local reference implementation. For
restart-safe storage, use `kache_hive_ce` or a custom backend.

## Errors and events

Expected failures are represented by `KacheFailure` in snapshots and command
results. The original cause and stack trace are retained, while string output
is sanitized. Configuration and lifecycle misuse throw immediately.

Observe `KacheClient.events` for telemetry. Observer failures cannot interrupt
the cache state machine.

## Ownership

A resource handle is released only by `resource.dispose()`. Stream
subscription cancellation is independent. `KacheClient.close()` cancels
fetches, drains or discards queued writes according to `drainWrites`, closes
streams, and closes only an owned persistence backend.

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
