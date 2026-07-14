# kache_bloc

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[简体中文](README.zh-CN.md)

Pure Dart Bloc/Cubit integration for Kache. It exposes the complete
`KacheSnapshot<T>` as state and does not depend on `flutter_bloc`.

## Installation

```bash
dart pub add kache_bloc
```

Flutter applications that use `BlocProvider` or `BlocBuilder` should also run
`flutter pub add flutter_bloc` and import it directly.

## Quick start

```dart
import 'dart:async';

import 'package:kache_bloc/kache_bloc.dart';

final class User {
  const User(this.id, this.name);

  final String id;
  final String name;
}

abstract interface class UserApi {
  Future<User> fetchUser(String id);
}

Future<void> observeUser(UserApi api, String userId) async {
  final client = KacheClient();
  final cubit = KacheCubit<User>(
    client: client,
    query: KacheQuery<User>.memory(
      key: KacheKey('users', <Object?>[userId]),
      fetch: (_) => api.fetchUser(userId),
    ),
  );
  final subscription = cubit.stream.listen((snapshot) {
    if (snapshot.hasData) {
      print(snapshot.requireData.name);
    }
  });

  try {
    await cubit.load();
  } finally {
    await subscription.cancel();
    await cubit.close();
    await client.close();
  }
}
```

## KacheCubit

`KacheCubit<T>` owns one core resource and emits snapshots from it. Commands
include `load`, `refresh`, `setData`, `updateData`, `invalidate`, and `remove`.
Closing the Cubit cancels its subscription and releases the resource, but never
closes the supplied client.

Set `refreshInterval` on the query policy while the Cubit is active. Pure Dart
client owners can pause and resume those timers with `pausePolling()` and
`resumePolling()`.

Subclass `KacheCubit<T>` when domain commands belong in the same Cubit. Keep
network parameters in the query key.

## Composable binding

Use `KacheBlocBinding<T>` when an existing Bloc or Cubit already owns the
business state. Create a binding, call `attach` once with your emit adapter,
delegate cache commands as needed, and await `binding.close()` from the host's
close method.

The binding supports one managed listener so resource ownership remains
unambiguous. It can expose `snapshot` before attachment for the host's initial
state.

## Flutter

Construct `KacheCubit` in `BlocProvider.create` and render with
`BlocBuilder<KacheCubit<T>, KacheSnapshot<T>>`. Use `lazy: false` when the page
must begin cache loading before the first descendant reads the Cubit.

Wrap the application with `KacheScope` from `kache_flutter` when lifecycle-aware
polling and resume revalidation are required.

## Compatibility

| Component | Supported range |
| --- | --- |
| Dart | Dart >=3.5.0 <4.0.0 |
| Flutter | Not required |
| Bloc | `>=9.2.1 <10.0.0` |

## License

MIT
