# kache_hive_ce

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[English](README.md)

Kache 官方的 Hive CE 跨重启持久层。它既可以通过 native envelope 复用已注册的 Hive
`TypeAdapter`，也可以为需要独立 codec 演进的存储格式使用显式 byte codec。

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

native adapter envelope 不会额外提供 Kache 格式版本或迁移钩子。应按 Hive 规则保持
adapter 的读取向后兼容；格式演进需要显式 codec 身份和迁移时，请改用 `bind`。

缓存 payload 需要独立 byte 格式时，使用 `bind(codecId:, codec:, migrate:)`。
`codecId` 是该格式的唯一身份：字节解释不变时保持稳定，解释规则改变时必须更换。
可选的 `migrate(payload, fromCodecId)` 用于读取明确支持的旧格式，并应拒绝未知 codec id。

迁移会立即返回类型化数据，随后由 Kache 以竞争安全的惰性 maintenance 重写当前
`codecId`。maintenance 失败会进入 persistence state 和 event，但不会隐藏已读取数据。

## 大数据与 isolate

`isolateThreshold` 决定 byte codec 工作在哪里执行。小于阈值（默认 64 KiB）的记录同步
解码，缓存数据在首帧即可使用；更大的记录在后台 isolate 中解码、迁移和编码，只有
`box.get` 与 `box.put` 留在调用方 isolate。

```dart
final store = await HiveCeKacheStore.open(
  boxName: 'kache',
  isolateThreshold: 64 * 1024, // `null` 表示所有 codec 工作都内联执行。
);
```

- 用顶层函数或静态函数构建 codec。若 codec 回调捕获了无法发送到其他 isolate 的状态，
  会自动回退为内联执行；读取不会因此失败，也不会删除记录。codec 必须无副作用，因为回退
  会重复执行它。
- 某个 codec 的首次写入因大小未知而内联执行，之后的写入按已存记录大小判断。
- 同一 key 的写入保持调用顺序；`clear`、`clearNamespace` 与 `close` 会等待后台写入完成。
- Web 没有后台 isolate，codec 工作始终内联执行。
- Flutter widget 测试运行在不会完成 isolate 任务的 fake clock 下。请让测试 payload 小于
  阈值，或传入 `isolateThreshold: null`。

在应用启动阶段打开 store：打开 box 会解析其中全部记录。大列表优先使用紧凑二进制 codec
而不是 JSON，超大列表按页拆分到不同 key 缓存。

## 物理键策略

逻辑 `KacheKey` 通过域分隔摘要映射为固定长度的物理 Hive box 键。物理键不直接编码
可逆的 canonical key 内容，逻辑键也可以超过 Hive CE 的 255 字节字符串键边界。

默认策略是 `HiveCeKeyStrategy.sha256()`。它对每个键组件应用带固定域前缀和 NUL 分隔
符的 SHA-256。

**SHA-256 的局限：**
- 它是确定性摘要：相同的逻辑键产生相同的物理键，因此相等关系仍可观察。
- 低熵键部分仍可能遭受字典攻击。
- **切勿**将密钥（API key、token、密码）作为缓存键的一部分。

当缓存键可能包含敏感信息时，使用 `HiveCeKeyStrategy.hmacSha256(secret)`，secret
为至少 32 字节的密码学随机值。HMAC 策略使没有 secret 的字典攻击不可行。secret 在
内部被拷贝且永不暴露；其稳定 identity 由 secret 派生但不泄露 secret。不要从 32-bit
Hive cipher key CRC 派生 secret。

```dart
final store = await HiveCeKacheStore.open(
  boxName: 'app-cache',
  keyStrategy: HiveCeKeyStrategy.hmacSha256(mySecret),
);
```

共享同一活动 box lease 的并发 `open` 必须使用 identity 相同的策略；不匹配会抛出
`HiveCeOpenException`。应将策略及 HMAC secret 视为持久化存储配置。使用不同策略或
secret 重新打开时，无法找到原策略写入的记录；有意轮换前应使用原配置清理它们。

版本 3 采用 clean cut：canonical `k1:` 键、`kache:2:` 哈希键和 v1 byte envelope 均
不会被读取、重写或删除。它们作为宿主 Box 数据保留，直到应用显式清理或迁移。

## 损坏与错误

未知 envelope、非法 metadata、adapter 或 codec 不匹配、decode 失败和缺少迁移都会
以 `KachePersistenceException` 上报，并带准确 operation/stage。核心恢复流程会删除
损坏记录，然后按 policy 当作 cache miss 继续。

核心 lookup 事件会报告 persistence layer 的 `hit`、`miss` 和 `expired`。成功命中可在
受信任的进程内事件中访问类型化值，但 Kache 的脱敏事件字符串永远不会包含它。

## 加密

可以把应用拥有的 `HiveCipher` 传给 `HiveCeKacheStore.open`，也可以用
`HiveCeKacheStore.fromBox` 包装已打开的加密 `Box<Object?>`。Kache 不保存也不记录
加密密钥。

对于 Kache 管理的 box，cipher 在首次打开时通过精确的 cipher 对象（`identical`）、
其 runtime type 及其 key CRC 固定。后续 `open` 调用必须传入同一个 cipher 对象；不同
对象——即使具有相同密钥材料——也会抛出 `HiveCeOpenException`。完整的 lease 描述符
（path、bytes、crash recovery、cipher、key strategy）也会被比较，因此任何配置不匹配
都会在操作 box 之前安全失败。对外部已打开的 box 传入 cipher 也会失败，因为 cipher
无法被验证。

## 共享 Box 与 clear 边界

`clear()` 只删除严格匹配 Kache 托管物理键语法的记录，绝不会调用 Hive
`Box.clear()`。`clearNamespace(namespace)` 只删除带有该 namespace 派生前缀的托管
记录。即使 `fromBox` 使用 `HiveCeBoxOwnership.owned`，两者也都会保留无关 String
和整数键——生命周期所有权不等于拥有 box 中的全部记录。

当前严格托管语法为 `kache:3:[sh]:<43 字符 token>:<43 字符 token>`。旧
`kache:2:` 和 canonical `k1:` 键不归本版本所有。共享 box 的应用不得创建匹配 v3
语法的宿主键。选择性 clear 需要枚举 box 键；宿主保存大量无关记录时仍应优先使用
专用 box。

## 所有权与 open 错误

`open` 使用引用计数 box lease。由 Kache 打开的 box 在最后一个 lease 结束后关闭；外部
已打开的 box 会被借用。`fromBox` 默认 `HiveCeBoxOwnership.borrowed`，只有 store
负责关闭注入 box 时才选择 `owned`。如果 box 属于非全局 `HiveInterface`，应传入
`fromBox(hive: ...)`，以便在正确 registry 上检查 adapter 注册和 box 身份。

box 获取期间的所有失败——cipher 不匹配、策略不匹配、以及异步 Hive I/O 错误——都以
`HiveCeOpenException` 上报。其 `toString` 固定脱敏，永不包含 box 名、路径或 cipher
细节。请检查 `cause` 和 `stackTrace` 进行诊断。非法 `boxName` 参数在任何 Hive 交互前
抛出 `ArgumentError`。

如果 client 是唯一生命周期所有者，把 store 配置为 owned backend。两层 close 都是
幂等的。

## 兼容性

| 组件 | 支持范围 |
| --- | --- |
| Dart | Dart >=3.5.0 <4.0.0 |
| Flutter | 不需要 |
| Hive CE | `>=2.19.3 <3.0.0` |
| 后台 codec 工作 | 原生平台；Web 内联执行 codec |

## 许可证

MIT
