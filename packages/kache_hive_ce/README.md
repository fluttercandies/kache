# kache_hive_ce

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[简体中文](README.zh-CN.md)

The official restart-safe Hive CE persistence backend for Kache. It can reuse
registered Hive `TypeAdapter` classes through a native envelope or use explicit
byte codecs for storage formats that need independent codec evolution.

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

The native adapter envelope does not add a Kache format version or migration
hook. Keep adapter reads backward-compatible under Hive's rules, or use `bind`
when format evolution needs an explicit codec identity and migration.

Use `bind(codecId:, codec:, migrate:)` when the cache payload needs an
independent byte format. `codecId` is the sole identity of that format: keep it
stable while the bytes retain the same interpretation and change it whenever
the interpretation changes. An optional `migrate(payload, fromCodecId)` reads
supported older formats; it should reject every unknown codec identifier.

Migration returns typed data immediately. Kache then schedules race-safe lazy
maintenance to rewrite the record under the current `codecId`. A maintenance
failure remains visible in persistence state and events without hiding data.

## Large values and isolates

`isolateThreshold` controls where byte-codec work runs. Records smaller than
the threshold (64 KiB by default) are decoded synchronously, so cached data is
available in the first frame. Larger records are decoded, migrated, and encoded
on a background isolate; only `box.get` and `box.put` stay on the calling
isolate.

```dart
final store = await HiveCeKacheStore.open(
  boxName: 'kache',
  isolateThreshold: 64 * 1024, // `null` keeps all codec work inline.
);
```

- Build codecs from top-level or static functions. A codec whose callbacks
  capture state that cannot be sent to another isolate falls back to inline
  work automatically; the read never fails and the record is never deleted
  because of it. Codecs must be free of side effects because a fallback
  repeats them.
- The first write of a codec runs inline because its size is unknown; later
  writes use the stored record size.
- Writes to the same key keep their call order; `clear`, `clearNamespace`, and
  `close` wait for offloaded writes.
- On Web there are no background isolates, so codec work always runs inline.
- Flutter widget tests run under a fake clock that never completes isolate
  work. Use payloads below the threshold there or pass `isolateThreshold: null`.

Open the store during app startup: opening a box parses every record in it.
Prefer compact binary codecs over JSON for large lists, and cache very large
lists in pages under separate keys.

## Physical key strategy

Logical `KacheKey`s are mapped to fixed-length physical Hive box keys using a
domain-separated digest. The physical key does not directly encode reversible
canonical key material, and logical keys can exceed Hive CE's 255-byte string
key boundary.

The default strategy is `HiveCeKeyStrategy.sha256()`. It applies SHA-256 with a
fixed domain prefix and NUL separator to each key component.

**Limitations of SHA-256:**
- It is a deterministic digest: identical logical keys produce identical
  physical keys, so equality relationships are observable.
- Low-entropy key parts remain susceptible to dictionary attacks.
- **Never** pass secrets (API keys, tokens, passwords) as cache key parts.

For caches whose key material may be sensitive, use
`HiveCeKeyStrategy.hmacSha256(secret)` with a cryptographically random secret of
at least 32 bytes. The HMAC strategy makes dictionary attacks infeasible without
the secret. The secret is copied internally and never exposed; its stable
identity is derived from the secret without revealing it. Do not derive the
secret from the 32-bit Hive cipher key CRC.

```dart
final store = await HiveCeKacheStore.open(
  boxName: 'app-cache',
  keyStrategy: HiveCeKeyStrategy.hmacSha256(mySecret),
);
```

Every concurrent `open` sharing an active box lease must use the same strategy
identity; a mismatch throws `HiveCeOpenException`. Treat the strategy and HMAC
secret as persistent storage configuration. Reopening with a different strategy
or secret cannot find records written under the original strategy. Clear them
with the original configuration before intentionally rotating it.

Version 3 is a clean cut: canonical `k1:` keys, `kache:2:` hashed keys, and v1
byte envelopes are not read, rewritten, or removed. They remain host-owned box
data until the application explicitly purges or migrates them.

## Corruption and errors

Unknown envelopes, invalid metadata, adapter or codec mismatch, decode
failures, and missing migrations are reported as `KachePersistenceException`
with an exact operation and stage. Core recovery deletes the damaged record
and continues as a cache miss according to policy.

Core lookup events report `hit`, `miss`, and `expired` for the persistence
layer. A successful hit can expose its trusted in-process typed value; Kache's
sanitized event string never includes it.

## Encryption

Pass an application-owned `HiveCipher` to `HiveCeKacheStore.open`, or wrap an
already-open encrypted `Box<Object?>` with `HiveCeKacheStore.fromBox`. Kache
never stores or logs encryption keys.

For a Kache-managed box, the cipher is pinned on first open using the exact
cipher object (`identical`), its runtime type, and its key CRC. Subsequent
`open` calls must pass the same cipher object; a different object — even one
with the same key material — fails with `HiveCeOpenException`. The full lease
descriptor (path, bytes, crash recovery, cipher, key strategy) is also compared,
so any configuration mismatch fails safely before touching the box. Passing a
cipher for a box that was opened outside Kache also fails, because the cipher
cannot be verified.

## Shared boxes and clear boundaries

`clear()` deletes only keys that strictly match Kache's managed physical-key
grammar; it never calls Hive `Box.clear()`. `clearNamespace(namespace)` deletes
only managed records carrying that namespace's derived prefix. Both operations
preserve unrelated String and integer keys, including when `fromBox` uses
`HiveCeBoxOwnership.owned`—lifecycle ownership does not imply ownership of every
record in the box.

The strict managed grammar is
`kache:3:[sh]:<43-char token>:<43-char token>`. Older `kache:2:` and canonical
`k1:` keys are not owned by this version. Applications sharing a box must not
create host keys matching the v3 grammar. Selective clear enumerates box keys,
so a dedicated box remains preferable when the host stores many unrelated
records.

## Ownership and open errors

`open` uses reference-counted box leases. A box opened by Kache closes after
the final lease; a box already opened elsewhere is borrowed. `fromBox` defaults
to `HiveCeBoxOwnership.borrowed`; select `owned` only when the store must close
that injected box. If the box belongs to a non-global `HiveInterface`, pass it
with `fromBox(hive: ...)` so adapter registration and box identity use the right
registry.

All failures during box acquisition — cipher mismatches, strategy mismatches,
and asynchronous Hive I/O errors — are reported as `HiveCeOpenException`. Its
`toString` is intentionally sanitized and never includes the box name, path, or
cipher details. Inspect `cause` and `stackTrace` for programmatic diagnosis.
Invalid `boxName` arguments throw `ArgumentError` before any Hive interaction.

Configure the store as an owned `KacheClient` backend when the client is the
single lifecycle owner. Closing both layers is idempotent.

## Compatibility

| Component | Supported range |
| --- | --- |
| Dart | Dart >=3.5.0 <4.0.0 |
| Flutter | Not required |
| Hive CE | `>=2.19.3 <3.0.0` |
| Background codec work | Native platforms; Web runs codecs inline |

## License

MIT
