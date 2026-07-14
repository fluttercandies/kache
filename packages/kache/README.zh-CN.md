# kache

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[English](README.md)

Kache 的无第三方依赖 Dart 核心包。它提供类型安全 key、查询策略、SWR 快照、确定性
并发、协作取消、缓存命令、事件和持久化协议。

## 安装

```bash
dart pub add kache
```

## 快速开始

```dart
import 'dart:async';

import 'package:kache/kache.dart';

final class User {
  const User(this.id, this.name);

  final String id;
  final String name;
}

abstract interface class UserApi {
  Future<User> fetchUser(String id);
}

Future<void> showUser({
  required UserApi api,
  required String userId,
  required void Function(KacheSnapshot<User>) render,
}) async {
  final client = KacheClient();
  final query = KacheQuery<User>.memory(
    key: KacheKey('users', <Object?>[userId]),
    fetch: (context) async {
      context.throwIfCancelled();
      return api.fetchUser(userId);
    },
    policy: KachePolicy.staleWhileRevalidate(),
  );
  final resource = client.watch(query);
  final subscription = resource.stream.listen(render);

  try {
    await resource.load();
  } finally {
    await subscription.cancel();
    resource.dispose();
    await client.close();
  }
}
```

第一个 listener 会立即收到当前快照。有缓存时，`isRefreshing` 和 `failure` 可以与
数据同时存在，因此后台操作进行中或失败后都不需要丢弃可用数据。
常见判断可直接使用 `isLoading`、`isReady`、`isFailed`、`isStale` 和
`hasFailure`。

## 查询与 key

所有请求参数都必须进入 `KacheKey`。key part 支持 `null`、bool、安全整数、合法
Unicode string 和 `Uint8List`；任意对象和隐式 `toString()` 会被拒绝。

使用 `KacheQuery.memory`、`KacheQuery.persisted` 或
`KacheQuery.networkOnly`。persisted query 必须使用当前 client backend 创建的
binding。

## 策略选择

- `staleWhileRevalidate`：先展示缓存，默认随后重验。
- `cacheFirst`：新鲜期内跳过请求。
- `cacheOnly`：不自动请求；如果提供 fetcher，显式 `refresh()` 仍可使用。
- `networkOnly`：状态只存在于活动 handle 中，并且始终请求。

硬过期数据会被删除且不会发出。默认情况下，刷新失败保留可见数据。

设置 `refreshInterval` 后会在首次 load 完成且 handle 仍活动时轮询；同 key handle
仍只共享一次 fetch。client owner 可调用 `pausePolling()` 和 `resumePolling()`，且不会
影响手动命令。`KacheQuery.networkOnly` 接受同名周期，但不会启用存储。

## 命令

`KacheResource` 提供 `load`、`refresh`、`setData`、`updateData`、
`invalidate` 和 `remove`。`KacheClient` 额外提供 `prefetch`、`peek`、namespace
清理、全量清理、活跃资源刷新和 resume 重验。

配置可选 `KacheNetwork` 后，来源从 `unavailable` 变为 `available` 时自动重验。
每个 handle 保留自己的 `refreshOnReconnect` 策略，同 key fetch 仍保持 single-flight。
`pauseReconnect()` 和 `resumeReconnect()` 会延后一次待处理恢复，但不会停止状态观察。
平台适配器应位于独立包中。

同 key 请求自动合并；同 key 写入串行；generation 与 namespace/global epoch 会阻止
旧任务在删除后恢复数据。

## 持久化协议

实现 `KachePersistenceBackend` 即可接入任意存储。核心只传递类型化 `T`、opaque
`KachePersistenceBinding<T>` 和 `KachePersistedMetadata`。序列化、codec、schema
迁移、加密和物理记录属于 backend 包，不属于核心。

`MemoryKachePersistence` 是进程内参考实现。需要跨重启持久化时使用
`kache_hive_ce` 或自定义 backend。

## 错误与事件

预期失败通过快照和命令结果中的 `KacheFailure` 表达。原始异常和堆栈会保留，字符串
输出会脱敏；配置和生命周期误用会立即抛出。

可订阅 `KacheClient.events` 做遥测。observer 自身失败不会中断缓存状态机。lookup
事件通过 `cacheHit`、`cacheMiss` 或 `cacheExpired` 标明 `memory` 或
`persistence` layer，且不携带 payload。

## 所有权

只有 `resource.dispose()` 会释放 handle，取消 stream 监听与它相互独立。
`KacheClient.close()` 会取消请求，按 `drainWrites` 处理写队列，关闭 stream，并且只
关闭 owned persistence backend。Owned network source 同样只关闭一次。Connectivity
失败以 `KacheFailureKind.connectivity` 事件保持可观测，且不会清除数据。

## 兼容性

| 组件 | 支持范围 |
| --- | --- |
| Dart | Dart >=3.5.0 <4.0.0 |
| Flutter | 不需要 |

## 许可证

MIT
