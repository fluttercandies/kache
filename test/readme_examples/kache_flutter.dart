import 'package:flutter/material.dart';
import 'package:kache_flutter/kache_flutter.dart';

final class User {
  const User(this.id, this.name);

  final String id;
  final String name;
}

abstract interface class UserApi {
  Future<User> fetchUser(String id);
}

Widget createUserApp({required UserApi api, required String userId}) {
  final client = KacheClient();
  final query = KacheQuery<User>.memory(
    key: KacheKey('users', <Object?>[userId]),
    fetch: (_) => api.fetchUser(userId),
  );

  return KacheScope(
    client: client,
    ownership: KacheScopeOwnership.owned,
    child: MaterialApp(
      home: Scaffold(
        body: KacheBuilder<User>(
          query: query,
          builder: (context, snapshot, controller) {
            if (!snapshot.hasData) {
              if (snapshot.isFailed) {
                return const Center(child: Text('Could not load user'));
              }
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
                icon: snapshot.isRefreshing
                    ? const CircularProgressIndicator()
                    : const Icon(Icons.refresh),
              ),
            );
          },
        ),
      ),
    ),
  );
}
