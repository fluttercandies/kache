# kache_hive_ce

[简体中文](README.zh-CN.md)

The official restart-safe Hive CE persistence backend for Kache. It stores
versioned byte envelopes and does not require Hive `TypeAdapter` classes for
application models.

## Installation

```bash
dart pub add kache_hive_ce
```

Flutter applications that call `Hive.initFlutter` should also declare and
import `hive_ce_flutter` directly.

## Quick start

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:kache/kache.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

final class User {
  const User(this.id, this.name);

  factory User.fromJson(Map<String, Object?> json) =>
      User(json['id']! as String, json['name']! as String);

  final String id;
  final String name;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'name': name};
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
  final store = await HiveCeKacheStore.open(boxName: 'app-cache');
  final binding = store.bind<User>(
    codecId: 'user-json',
    schema: 1,
    codec: HiveCeCodec<User>(
      encode: (user) =>
          Uint8List.fromList(utf8.encode(jsonEncode(user.toJson()))),
      decode: (bytes) =>
          User.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, Object?>),
    ),
  );
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

## Codec and schema

`codecId` identifies the model format and must remain stable. `schema` is a
positive unsigned 32-bit version. Increasing the schema changes the binding
fingerprint, so provide `migrate(payload, fromSchema)` to read older envelopes.

Migration returns typed data immediately. Kache then schedules lazy
maintenance to rewrite the record with the current schema. A maintenance write
failure remains visible in persistence state and events without hiding data.

## Corruption and errors

Unknown envelopes, invalid metadata, codec mismatch, decode failures, and
missing migrations are reported as `KachePersistenceException` with an exact
operation and stage. Core recovery deletes the damaged record and continues as
a cache miss according to policy.

## Encryption

Pass an application-owned `HiveCipher` to `HiveCeKacheStore.open`, or wrap an
already-open encrypted `Box<Object?>` with `HiveCeKacheStore.fromBox`. Kache
never stores or logs encryption keys.

## Ownership

`open` uses reference-counted box leases. A box opened by Kache closes after
the final lease; a box already opened elsewhere is borrowed. `fromBox` defaults
to `HiveCeBoxOwnership.borrowed`; select `owned` only when the store must close
that injected box.

Configure the store as an owned `KacheClient` backend when the client is the
single lifecycle owner. Closing both layers is idempotent.

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
