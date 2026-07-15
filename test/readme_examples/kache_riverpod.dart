import 'dart:async';

import 'package:kache_riverpod/kache_riverpod.dart';
import 'package:riverpod/riverpod.dart';

final class User {
  const User(this.id, this.name);

  final String id;
  final String name;
}

abstract interface class UserApi {
  Future<User> searchUser(String text, int page);
}

final class UserProviders {
  UserProviders({required this.client, required this.api});

  final KacheClient client;
  final UserApi api;

  late final search = kacheProvider.autoDispose
      .family<User, ({String text, int page})>(
        client: (_) => client,
        query: (_, args) => KacheQuery<User>.memory(
          key: KacheKey('search', <Object?>[args.text, args.page]),
          fetch: (_) => api.searchUser(args.text, args.page),
        ),
      );
}

Future<void> observeUser(UserApi api, String text, int page) async {
  final client = KacheClient();
  final providers = UserProviders(client: client, api: api);
  final container = ProviderContainer();
  final provider = providers.search((text: text, page: page));
  final subscription = container.listen(
    provider,
    (previous, next) {},
    fireImmediately: true,
  );

  try {
    await container.read(provider.notifier).refresh();
  } finally {
    subscription.close();
    container.dispose();
    await client.close();
  }
}
