# kache_hive_ce

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[简体中文](README.zh-CN.md)

The official restart-safe Hive CE persistence backend for Kache. It can reuse
registered Hive `TypeAdapter` classes through a native envelope or use explicit
byte codecs for storage formats that need independent schemas and migrations.

## Installation

```bash
dart pub add kache_hive_ce hive_ce
```

Flutter applications that call `Hive.initFlutter` should also declare and
import `hive_ce_flutter` directly.

## Quick start

```dart
import 'package:hive_ce/hive_ce.dart';
import 'package:kache/kache.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

final class User {
  const User(this.id, this.name);

  final String id;
  final String name;
}

final class UserAdapter extends TypeAdapter<User> {
  const UserAdapter();

  static const typeIdValue = 1;

  @override
  int get typeId => typeIdValue;

  @override
  User read(BinaryReader reader) =>
      User(reader.readString(), reader.readString());

  @override
  void write(BinaryWriter writer, User obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.name);
  }
}

abstract interface class UserApi {
  Future<User> fetchUser(String id);
}

final class UserCache {
  const UserCache(this.client, this.query);

  final KacheClient client;
  final KacheQuery<User> query;
}

Future<UserCache> openUserCache(UserApi api, String userId) async {
  if (!Hive.isAdapterRegistered(UserAdapter.typeIdValue)) {
    Hive.registerAdapter<User>(const UserAdapter());
  }
  final store = await HiveCeKacheStore.open(boxName: 'app-cache');
  final binding = store.bindAdapter<User>(const UserAdapter());
  final client = KacheClient(
    persistence: store,
    persistenceOwnership: KachePersistenceOwnership.owned,
  );
  final query = KacheQuery<User>.persisted(
    key: KacheKey('users', <Object?>[userId]),
    binding: binding,
    fetch: (_) => api.fetchUser(userId),
  );
  return UserCache(client, query);
}
```

## Adapter and codec bindings

`bindAdapter<T>(adapter)` requires that the adapter type id is already
registered on the same `HiveInterface` used to open the box. Kache does not
register or own adapters. Projects using Hive CE code generation can pass the
generated adapter after their normal `Hive.registerAdapters()` call. The full
Hive CE external type id range `0..65439`, including extended ids above 223,
is supported. Native records support nullable cached values and are isolated
from byte-codec records, so one mode can never reinterpret the other.

Use `bind(codecId:, schema:, codec:, migrate:)` when the cache payload needs an
independent byte format. `codecId` identifies that model format and must remain
stable. `schema` is a positive unsigned 32-bit version. Increasing the schema
changes the binding fingerprint, so provide `migrate(payload, fromSchema)` to
read older envelopes.

Migration returns typed data immediately. Kache then schedules lazy
maintenance to rewrite the record with the current schema. A maintenance write
failure remains visible in persistence state and events without hiding data.

## Corruption and errors

Unknown envelopes, invalid metadata, adapter or codec mismatch, decode
failures, and missing migrations are reported as `KachePersistenceException`
with an exact operation and stage. Core recovery deletes the damaged record
and continues as a cache miss according to policy.

Core lookup events report persistence `cacheHit`, `cacheMiss`, and
`cacheExpired` outcomes without exposing encoded values or keys.

## Encryption

Pass an application-owned `HiveCipher` to `HiveCeKacheStore.open`, or wrap an
already-open encrypted `Box<Object?>` with `HiveCeKacheStore.fromBox`. Kache
never stores or logs encryption keys.

## Ownership

`open` uses reference-counted box leases. A box opened by Kache closes after
the final lease; a box already opened elsewhere is borrowed. `fromBox` defaults
to `HiveCeBoxOwnership.borrowed`; select `owned` only when the store must close
that injected box. If the box belongs to a non-global `HiveInterface`, pass it
with `fromBox(hive: ...)` so adapter registration and box identity use the right
registry.

Configure the store as an owned `KacheClient` backend when the client is the
single lifecycle owner. Closing both layers is idempotent.

## Compatibility

| Component | Supported range |
| --- | --- |
| Dart | Dart >=3.5.0 <4.0.0 |
| Flutter | Not required |
| Hive CE | `>=2.19.3 <3.0.0` |

## License

MIT
