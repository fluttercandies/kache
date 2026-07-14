import 'dart:convert';
import 'dart:typed_data';

import 'package:kache/kache.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

final class User {
  const User(this.id, this.name);

  factory User.fromJson(Map<String, Object?> json) =>
      User(json['id']! as String, json['name']! as String);

  final String id;
  final String name;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'name': name};
}

abstract interface class UserApi {
  Future<User> fetchUser(String id);
}

final class UserCache {
  const UserCache(this.client, this.query);

  final KacheClient client;
  final KacheQuery<User> query;
}

Future<UserCache> openUserCache(UserApi api, String userId) async {
  final store = await HiveCeKacheStore.open(boxName: 'app-cache');
  final binding = store.bind<User>(
    codecId: 'user-json',
    schema: 1,
    codec: HiveCeCodec<User>(
      encode: (user) =>
          Uint8List.fromList(utf8.encode(jsonEncode(user.toJson()))),
      decode: (bytes) =>
          User.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, Object?>),
    ),
  );
  final client = KacheClient(
    persistence: store,
    persistenceOwnership: KachePersistenceOwnership.owned,
  );
  final query = KacheQuery<User>.persisted(
    key: KacheKey('users', <Object?>[userId]),
    binding: binding,
    fetch: (_) => api.fetchUser(userId),
  );
  return UserCache(client, query);
}
