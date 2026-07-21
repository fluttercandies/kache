# kache_hive_ce

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[English](README.md)

Kache 官方的 Hive CE 跨重启持久层。它既可以通过 native envelope 复用已注册的 Hive
`TypeAdapter`，也可以为需要独立 schema 和迁移的存储格式使用显式 byte codec。

## 安装

```bash
dart pub add kache_hive_ce hive_ce
```

Flutter 应用直接调用 `Hive.initFlutter` 时，还应显式声明并 import
`hive_ce_flutter`。

## 快速开始

```dart
import 'package:hive_ce/hive_ce.dart';
import 'package:kache/kache.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

final class User {
  const User(this.id, this.name);

  final String id;
  final String name;
}

final class UserAdapter extends TypeAdapter<User> {
  const UserAdapter();

  static const typeIdValue = 1;

  @override
  int get typeId => typeIdValue;

  @override
  User read(BinaryReader reader) =>
      User(reader.readString(), reader.readString());

  @override
  void write(BinaryWriter writer, User obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.name);
  }
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
  if (!Hive.isAdapterRegistered(UserAdapter.typeIdValue)) {
    Hive.registerAdapter<User>(const UserAdapter());
  }
  final store = await HiveCeKacheStore.open(boxName: 'app-cache');
  final binding = store.bindAdapter<User>(const UserAdapter());
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

## Adapter 与 codec binding

`bindAdapter<T>(adapter)` 要求 adapter type id 已注册到打开该 box 的同一个
`HiveInterface`。Kache 不会注册或持有 adapter。使用 Hive CE codegen 的项目在正常
调用 `Hive.registerAdapters()` 后传入生成的 adapter 即可。完整支持 Hive CE 外部
type id 范围 `0..65439`，包括 223 以上的扩展 id。native record 支持缓存 nullable
值，并且与 byte-codec record 严格隔离，两种模式不会互相误读。

缓存 payload 需要独立 byte 格式时，使用
`bind(codecId:, schema:, codec:, migrate:)`。`codecId` 标识模型格式，发布后应保持
稳定。`schema` 是正的 unsigned 32-bit 版本号。提升 schema 会改变 binding
fingerprint，因此需要提供 `migrate(payload, fromSchema)` 读取旧 envelope。

迁移会先返回类型化数据，随后由 Kache 惰性重写当前 schema。maintenance 写入失败会
进入 persistence state 和 event，但不会隐藏已读取数据。

## 损坏与错误

未知 envelope、非法 metadata、adapter 或 codec 不匹配、decode 失败和缺少迁移都会
以 `KachePersistenceException` 上报，并带准确 operation/stage。核心恢复流程会删除
损坏记录，然后按 policy 当作 cache miss 继续。

核心 lookup 事件会报告 persistence `cacheHit`、`cacheMiss` 和 `cacheExpired`，
不会暴露编码值或 key。

## 加密

可以把应用拥有的 `HiveCipher` 传给 `HiveCeKacheStore.open`，也可以用
`HiveCeKacheStore.fromBox` 包装已打开的加密 `Box<Object?>`。Kache 不保存也不记录
加密密钥。

## 所有权

`open` 使用引用计数 box lease。由 Kache 打开的 box 在最后一个 lease 结束后关闭；外部
已打开的 box 会被借用。`fromBox` 默认 `HiveCeBoxOwnership.borrowed`，只有 store
负责关闭注入 box 时才选择 `owned`。如果 box 属于非全局 `HiveInterface`，应传入
`fromBox(hive: ...)`，以便在正确 registry 上检查 adapter 注册和 box 身份。

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
