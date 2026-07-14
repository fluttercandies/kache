# kache_flutter

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[简体中文](README.zh-CN.md)

Flutter widgets and lifecycle integration for Kache, with no third-party state
management dependency. This package re-exports the complete `kache` API.

## Installation

```bash
flutter pub add kache_flutter
```

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:kache_flutter/kache_flutter.dart';

typedef Profile = ({String name});

Widget createProfileApp({required Future<Profile> Function() fetchProfile}) =>
    KacheScope(
      client: KacheClient(),
      ownership: KacheScopeOwnership.owned,
      child: MaterialApp(
        home: Scaffold(
          body: KacheBuilder<Profile>(
            query: KacheQuery<Profile>.memory(
              key: KacheKey('profile'),
              fetch: (_) => fetchProfile(),
            ),
            builder: (context, snapshot, controller) {
              if (!snapshot.hasData) {
                return Center(
                  child: snapshot.isFailed
                      ? FilledButton(
                          onPressed: controller.load,
                          child: const Text('Try again'),
                        )
                      : const CircularProgressIndicator(),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => controller.refresh(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: <Widget>[
                    ListTile(
                      title: Text(snapshot.requireData.name),
                      subtitle: snapshot.hasFailure
                          ? const Text('Refresh failed - showing cached data')
                          : null,
                      trailing: snapshot.isRefreshing
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.cloud_done),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
```

The builder loads automatically. Cached data remains visible during
background refresh and after refresh failures. Pull to refresh calls the same
deduplicated query explicitly.

## Widgets

- `KacheScope` exposes a client, pauses polling outside the foreground, and
  bridges `AppLifecycleState.resumed` to policy-driven revalidation. It also
  defers reconnect work until the app returns to the foreground.
- `KacheBuilder<T>` owns one `KacheController<T>` and rebuilds from complete
  snapshots.
- `KacheListener<T>` performs side effects without rebuilding its child.
- `KacheController<T>` is a `ValueListenable<KacheSnapshot<T>>` and exposes all
  resource commands.

When a widget receives a new query with the same key, the controller updates
the handle's fetcher and policy without losing shared data. A different key
releases the previous handle and binds a new one.

## Ownership

`KacheScopeOwnership.borrowed` is the default. Use `owned` only when the scope
is the application boundary responsible for closing the client. Builders,
listeners, and controllers own resource handles, never the client.

Lifecycle errors can be routed through `KacheScope.onError`. Without a custom
handler, they are reported through `FlutterError.reportError`.

Set `refreshInterval` on a query policy for active polling. The scope pauses
those timers for inactive, hidden, paused, and detached app states, then starts
a fresh interval on resume before applying `refreshOnResume`.

With a configured `KacheNetwork`, the scope keeps observing availability while
backgrounded but pauses reconnect revalidation. Resume consumes at most one
pending recovery. The official plugin adapter is `kache_connectivity_plus`.

## Persistence

Add `kache_hive_ce` as a direct dependency when the application imports it.
Open the store before creating the scope, configure an owned backend on the
client, and use a persisted query binding. Codec and migration logic stay in
the storage package.

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

## License

MIT
