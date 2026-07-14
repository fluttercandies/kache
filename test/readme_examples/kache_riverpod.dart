import 'dart:async';

import 'package:kache_riverpod/kache_riverpod.dart';
import 'package:riverpod/riverpod.dart';

final class User {
  const User(this.id, this.name);

  final String id;
  final String name;
}

abstract interface class UserApi {
  Future<User> fetchUser(String id);
}

final class UserProviders {
  UserProviders({required this.client, required this.api});

  final KacheClient client;
  final UserApi api;

  late final user = kacheProvider.autoDispose.family<User, String>(
    client: (_) => client,
    query: (_, userId) => KacheQuery<User>.memory(
      key: KacheKey('users', <Object?>[userId]),
      fetch: (_) => api.fetchUser(userId),
    ),
  );
}

Future<void> observeUser(UserApi api, String userId) async {
  final client = KacheClient();
  final providers = UserProviders(client: client, api: api);
  final container = ProviderContainer();
  final subscription = container.listen(
    providers.user(userId),
    (previous, next) {},
    fireImmediately: true,
  );

  try {
    await container.read(providers.user(userId).notifier).refresh();
  } finally {
    subscription.close();
    container.dispose();
    await client.close();
  }
}
