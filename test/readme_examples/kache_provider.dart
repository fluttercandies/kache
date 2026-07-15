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
      builder: (context, snapshot, controller, child) => snapshot.when(
        idle: () => const SizedBox.shrink(),
        loading: () => const Center(child: CircularProgressIndicator()),
        failed: (_) => const Center(child: Text('Could not load user')),
        ready: (user) => _userTile(user, controller),
        refreshError: (user, _) =>
            _userTile(user, controller, refreshFailed: true),
      ),
    ),
  );
}

Widget _userTile(
  User user,
  KacheController<User> controller, {
  bool refreshFailed = false,
}) => ListTile(
  title: Text(user.name),
  subtitle: refreshFailed ? const Text('Showing cached data') : null,
  trailing: IconButton(
    tooltip: 'Refresh user',
    onPressed: controller.refresh,
    icon: const Icon(Icons.refresh),
  ),
);
