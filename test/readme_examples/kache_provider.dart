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
