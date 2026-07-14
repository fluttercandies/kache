# kache_provider

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[简体中文](README.zh-CN.md)

Provider widgets for Kache, implemented on top of `KacheController<T>`. This
package re-exports `kache_flutter`, so one import provides the core and Flutter
APIs used by the integration.

## Installation

```bash
flutter pub add kache_provider
```

Declare `provider` directly only when application source imports Provider APIs
outside this package's widgets.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:kache_provider/kache_provider.dart';

final class User {
  const User(this.id, this.name);

  final String id;
  final String name;
}

abstract interface class UserApi {
  Future<User> fetchUser(String id);
}

Widget createUserView({
  required KacheClient client,
  required UserApi api,
  required String userId,
}) {
  final query = KacheQuery<User>.memory(
    key: KacheKey('users', <Object?>[userId]),
    fetch: (_) => api.fetchUser(userId),
  );
  return KacheProvider<User>(
    client: client,
    query: query,
    child: KacheConsumer<User>(
      builder: (context, snapshot, controller, child) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListTile(
          title: Text(snapshot.requireData.name),
          subtitle: snapshot.failure == null
              ? null
              : const Text('Showing cached data'),
          trailing: IconButton(
            tooltip: 'Refresh user',
            onPressed: controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
        );
      },
    ),
  );
}
```

## Provider widgets

`KacheProvider<T>` creates and disposes one `KacheController<T>`. Supply an
explicit client or omit it to use the nearest `KacheScope`. A query update with
the same key keeps shared data; a new key rebinds the controller.

`KacheConsumer<T>` rebuilds from the current snapshot and provides the
controller for commands. It accepts a static `child` using normal Provider
consumer semantics.

Use `context.readKache<T>()` for commands without subscribing and
`context.watchKache<T>()` to rebuild from the nearest snapshot.

## Ownership

The provider owns its controller and resource handle, but always borrows the
client. Put client ownership at the app boundary with
`KacheScopeOwnership.owned`, or close an externally owned client yourself.

Do not create a client in a frequently rebuilt widget. Keep it in application
state, dependency injection, or an owned `KacheScope`.

## Persistence and lifecycle

Open a backend such as `kache_hive_ce`, create the client, and place
`KacheScope` above `KacheProvider` for lifecycle-aware `refreshInterval`
polling and resume revalidation. The Provider adapter does not duplicate
persistence or lifecycle state.

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
