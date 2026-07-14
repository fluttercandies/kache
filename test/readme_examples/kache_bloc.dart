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
