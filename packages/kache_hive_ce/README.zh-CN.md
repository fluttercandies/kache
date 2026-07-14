# kache_hive_ce

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[English](README.md)

Kache 官方的 Hive CE 跨重启持久层。它写入版本化 byte envelope，业务模型无需 Hive
`TypeAdapter`。

## 安装

```bash
dart pub add kache_hive_ce
```

Flutter 应用直接调用 `Hive.initFlutter` 时，还应显式声明并 import
`hive_ce_flutter`。

## 快速开始

```dart
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
```

## Codec 与 schema

`codecId` 标识模型格式，发布后应保持稳定。`schema` 是正的 unsigned 32-bit 版本号。
提升 schema 会改变 binding fingerprint，因此需要提供 `migrate(payload, fromSchema)`
读取旧 envelope。

迁移会先返回类型化数据，随后由 Kache 惰性重写当前 schema。maintenance 写入失败会
进入 persistence state 和 event，但不会隐藏已读取数据。

## 损坏与错误

未知 envelope、非法 metadata、codec 不匹配、decode 失败和缺少迁移都会以
`KachePersistenceException` 上报，并带准确 operation/stage。核心恢复流程会删除损坏
记录，然后按 policy 当作 cache miss 继续。

核心 lookup 事件会报告 persistence `cacheHit`、`cacheMiss` 和 `cacheExpired`，
不会暴露编码值或 key。

## 加密

可以把应用拥有的 `HiveCipher` 传给 `HiveCeKacheStore.open`，也可以用
`HiveCeKacheStore.fromBox` 包装已打开的加密 `Box<Object?>`。Kache 不保存也不记录
加密密钥。

## 所有权

`open` 使用引用计数 box lease。由 Kache 打开的 box 在最后一个 lease 结束后关闭；外部
已打开的 box 会被借用。`fromBox` 默认 `HiveCeBoxOwnership.borrowed`，只有 store
负责关闭注入 box 时才选择 `owned`。

如果 client 是唯一生命周期所有者，把 store 配置为 owned backend。两层 close 都是
幂等的。

## 兼容性

| 组件 | 支持范围 |
| --- | --- |
| Dart | Dart >=3.5.0 <4.0.0 |
| Flutter | 不需要 |
| Hive CE | `>=2.19.3 <3.0.0` |

## 许可证

MIT
