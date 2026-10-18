# kache_connectivity_plus

<p align="center">
  <img src="https://raw.githubusercontent.com/fluttercandies/kache/main/packages/kache_connectivity_plus/assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[![pub package](https://img.shields.io/pub/v/kache_connectivity_plus.svg)](https://pub.dev/packages/kache_connectivity_plus)
[![CI](https://github.com/fluttercandies/kache/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/fluttercandies/kache/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/fluttercandies/kache/blob/main/packages/kache_connectivity_plus/LICENSE)

[简体中文](README.zh-CN.md)

The official connectivity_plus adapter for Kache reconnect revalidation. It
turns platform interface availability into `KacheNetworkState` without adding
plugin dependencies to the Dart-only `kache` core.

An available network interface does not guarantee Internet access. Fetchers
must still handle timeouts, DNS failures, HTTP failures, and cancellation.

## Installation

```bash
flutter pub add kache_connectivity_plus
```

## Quick start

```dart
import 'package:kache_connectivity_plus/kache_connectivity_plus.dart';

KacheClient createClient() {
  final network = ConnectivityPlusNetwork();
  return KacheClient(
    network: network,
    networkOwnership: KacheNetworkOwnership.owned,
  );
}
```

`KachePolicy.staleWhileRevalidate()` revalidates active handles after an
`unavailable -> available` transition by default. Override
`refreshOnReconnect` with `always`, `ifStale`, or `never` per query. A
`cacheOnly` query never fetches because of reconnect.

## State semantics

The adapter subscribes to connectivity changes before running the initial
check, so a newer platform event cannot be overwritten by a late check. Each
subscriber receives the latest normalized state first, followed by distinct
changes; a paused subscriber resumes with only the newest state. A result made
only of `ConnectivityResult.none` maps to `unavailable`; any other non-empty
result set maps to `available`.

Check failures, stream failures, malformed empty results, and unexpected
stream completion remain observable. When a check failed and no state is known
yet, the next subscriber triggers a fresh check instead of waiting silently.
`KacheClient` reports source failures as `KacheFailureKind.connectivity` events
without clearing cached snapshots.

## Ownership

Use `KacheNetworkOwnership.owned` when the client is the lifecycle boundary.
The client then cancels the plugin subscription through the adapter exactly
once during `close()`. Use `borrowed` when another object owns the adapter and
close it explicitly after all clients have stopped.

`ConnectivityPlusNetwork(connectivity: ...)` accepts an explicit
`Connectivity` implementation for deterministic tests. To integrate another
plugin or reachability service, implement the SDK-only `KacheNetwork`
interface in a separate package and pass it to `KacheClient` in the same way.
The custom stream must replay its current state to every subscriber:

```dart
final class AppNetwork implements KacheNetwork {
  AppNetwork({required this.states, required Future<void> Function() close})
    : _close = close;

  @override
  final Stream<KacheNetworkState> states;

  final Future<void> Function() _close;

  @override
  Future<void> close() => _close();
}
```

Pass an `AppNetwork` as borrowed when its host owns `_close`, or owned when the
`KacheClient` is responsible for closing it.

## Flutter lifecycle

Place the client in `KacheScope`. The scope pauses reconnect revalidation while
the app is inactive, hidden, paused, or detached, then consumes one pending
reconnect after resume. Network observation stays active in the background.

Platforms can drop connectivity events in the background (connectivity_plus
skips them on iOS), so the adapter checks connectivity again every time the
app resumes. A change event that arrives while that check is pending wins over
the check result, and an unchanged result emits nothing. The default adapter
observes `WidgetsBinding.instance`; pass `binding:` together with an injected
`connectivity:` to enable resume checks in tests.

## Compatibility

| Component | Supported range |
| --- | --- |
| Dart | Dart >=3.5.0 <4.0.0 |
| Flutter | Flutter >=3.24.0 |
| connectivity_plus | `>=7.3.0 <8.0.0` |
| Android | minSdk 21, Java 17, AGP >=8.12.1, Gradle >=8.13, Kotlin 2.2.0 |
| Apple | iOS >=12.0, macOS >=10.14, Xcode >=26.1.1 |

Android, iOS, macOS, Linux, Windows, and Web are supported through
connectivity_plus 7.3.1 (with a compatible floor of 7.3.0). Connectivity reports an available network interface,
not verified Internet reachability. Existing Android projects must satisfy the
native build-tool requirements above even when their Flutter SDK constraint
resolves successfully.

## License

MIT
