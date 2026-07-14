# Kache

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[English](README.md)

Kache 是面向 Dart 和 Flutter 的类型安全 stale-while-revalidate 缓存库。它能先
展示上一次可用数据，在后台刷新；刷新失败时保留旧数据，并把完整操作状态交给 UI
或任意状态管理层处理。

核心包没有第三方运行时依赖。持久化、Flutter 和状态管理接入分别位于独立包中。

## 包结构

| 包 | 用途 | 运行时边界 |
| --- | --- | --- |
| `kache` | 缓存状态机、并发、策略、内存后端 | 仅 Dart SDK |
| `kache_flutter` | Scope、Controller、Builder、Listener、应用生命周期 | Flutter + `kache` |
| `kache_hive_ce` | 版本化 Hive CE 持久化、codec、迁移 | Hive CE + `kache` |
| `kache_riverpod` | provider/family/auto-dispose notifier 接入 | Riverpod + `kache` |
| `kache_bloc` | `KacheCubit` 与可组合 binding | Bloc + `kache` |
| `kache_provider` | Provider 组件与 context helper | Provider + `kache_flutter` |

应用通常只声明一个最上层 Kache 接入包。只有源码直接 import 更底层能力时才额外
声明，例如持久化使用 `kache_hive_ce`，Bloc UI 使用 `flutter_bloc`。

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

监听 `resource.stream` 会立即重放当前快照，并且只自动触发一次首次加载。有缓存时，
`isRefreshing` 为 true 但旧数据仍然可见。启用 `retainDataOnError` 时，刷新失败记录在
`snapshot.failure`，不会清空数据。

常见 UI 判断可直接使用 `isLoading`、`isReady`、`isFailed`、`isStale` 和
`hasFailure`，完整快照状态仍然保留。

## 策略选择

| 需求 | 策略 |
| --- | --- |
| 先显示缓存，并在加载/恢复时刷新 | `KachePolicy.staleWhileRevalidate()` |
| 新鲜期内避免重复请求 | `KachePolicy.cacheFirst(freshFor: ...)` |
| 永不自动请求 | `KachePolicy.cacheOnly()` |
| 每次请求且完全不缓存 | `KacheQuery.networkOnly(...)` |

`staleAfter` 决定数据何时变旧；`expireAfter` 是硬过期边界，超过后数据会被删除而不是
发出；`gcAfter` 控制无人引用的内存条目保留时长。

设置 `refreshInterval` 后，只在 resource handle 已 load 且仍活动时轮询；同 key 请求仍会
自动合并。`pausePolling()` 和 `resumePolling()` 只控制计时器，不会禁用手动缓存命令。
`KacheQuery.networkOnly` 接受同名周期，但不会因此启用缓存。

## 持久化

`KacheClient()` 默认只使用内存。需要跨重启恢复时，为客户端配置
`KachePersistenceBackend`，并通过后端创建的 binding 声明 persisted query。官方
实现是 `kache_hive_ce`。

序列化不属于核心包。存储适配器负责 codec、物理记录、schema 版本、迁移、加密配置
和损坏恢复；核心只处理类型化数据和缓存元数据。

## 自定义持久层

可以为 SQLite、Isar、文件、安全存储或其他系统实现 `KachePersistenceBackend`。
实现必须：

- 返回类型化 `KachePersistenceRead<T>`；
- 校验 binding 属于当前 backend；
- 完整保存 `KachePersistedMetadata`；
- 按规范 namespace prefix 精确清理；
- 用 `KachePersistenceException` 包装 I/O 和 codec 失败；
- 明确定义幂等所有权与 `close()` 语义。

可参考 `MemoryKachePersistence` 和持久层契约测试。不要把 codec 方法加入
`KacheQuery` 或核心持久化协议。

## 错误处理

快照把失败作为状态数据携带，stream 不会用 `addError` 表达预期的请求或持久化
失败。`KacheFailure` 保留原始异常和堆栈，但 `toString()` 会脱敏。命令式代码可调用
`snapshot.throwIfFailed()` 或 `clearResult.throwIfFailed()`。

日志和遥测可以订阅 `KacheClient.events` 或注入 observer。事件默认不包含 payload
或原始 key 值。`cacheHit`、`cacheMiss` 和 `cacheExpired` 会标明 `memory` 或
`persistence` layer，且不会改变资源状态。

## 生命周期

每次 `client.watch(query)` 都返回独立的 `KacheResource` handle。取消 stream 监听不
等于释放资源，必须调用 `resource.dispose()`；应用边界再关闭 client 和 owned backend。

Flutter 应用应使用 `KacheScope`，由它选择是否拥有 client，在离开前台时暂停轮询，
并在恢复前台时自动重验活跃资源。状态管理适配器拥有自己的 resource handle，但不会
拥有传入的 client。

## 兼容性

| 组件 | 支持范围 |
| --- | --- |
| Dart | Dart >=3.9.0 <4.0.0 |
| Flutter | Flutter >=3.35.0 |
| Hive CE | `>=2.19.3 <3.0.0` |
| Riverpod | `>=3.3.2 <4.0.0` |
| Bloc | `>=9.2.1 <10.0.0` |
| Provider | `>=6.1.5+1 <7.0.0` |

## 示例

`examples/` 提供普通 Flutter、Riverpod、Bloc/Cubit 和 Provider 四个可运行应用。
它们使用真实 GitHub repository API 与 Hive CE，覆盖冷启动、重启缓存首显、刷新、
失败保留旧数据和清缓存。

## 许可证

Kache 使用 MIT License。
