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
  required void Function(String) render,
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
  final subscription = resource.stream.listen(
    (snapshot) => render(
      snapshot.when(
        idle: () => 'Idle',
        loading: () => 'Loading',
        ready: (user) => user.name,
        refreshError: (user, _) => '${user.name} (refresh failed)',
        failed: (_) => 'Could not load user',
      ),
    ),
  );

  try {
    await resource.load();
  } finally {
    await subscription.cancel();
    resource.dispose();
    await client.close();
  }
}
```

第一个 listener 会立即收到当前快照。`when` 要求显式处理 idle、loading、ready、
保留数据的刷新失败和无数据失败；刷新时默认继续进入 `ready`，且不会静默隐藏刷新
错误。局部处理使用 `maybeWhen`，转换可见数据使用 `mapData`，两者都不会创建第二套
状态语义。

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
`invalidate`、`remove` 和 `cancel`。`KacheClient` 额外提供 `prefetch`、`peek`、
`cancel(key)`、`cancelAll`、namespace 清理、全量清理、活跃资源刷新和 resume 重验。

配置可选 `KacheNetwork` 后，来源从 `unavailable` 变为 `available` 时自动重验。
每个 handle 保留自己的 `refreshOnReconnect` 策略，同 key fetch 仍保持 single-flight。
`pauseReconnect()` 和 `resumeReconnect()` 会延后一次待处理恢复，但不会停止状态观察。
平台适配器应位于独立包中。

同 key 请求自动合并；同 key 写入串行；generation 与 namespace/global epoch 会阻止
旧任务在删除后恢复数据。

## 持久化协议

实现 `KachePersistenceBackend` 即可接入任意存储。核心只传递类型化 `T`、opaque
`KachePersistenceBinding<T>` 和 `KachePersistedMetadata`。序列化、codec、格式迁移、
加密和物理记录属于 backend 包，不属于核心。

核心可能在监听者的同步调用栈内调用 `read` 和 `write`，例如订阅资源的 widget build。
返回的 future 首次让出之前执行的工作不得随 payload 大小增长；大值的解码、编码或拷贝
应放到异步间隔之后，例如另一个 isolate。具体在哪里执行由 backend 决定。

`MemoryKachePersistence` 是进程内参考实现。需要跨重启持久化时使用
`kache_hive_ce` 或自定义 backend。

## 错误与事件

预期失败通过快照和命令结果中的 `KacheFailure` 表达。原始异常和堆栈会保留，字符串
输出会脱敏；配置和生命周期误用会立即抛出。

可订阅 `KacheClient.events` 做遥测，observer 自身失败不会中断缓存状态机。事件通过
`kind + phase + trigger`、成对 span/trace id、scope、耗时、revision 和 query context
描述完整操作。成功的缓存命中、读取、请求、写入和 set 事件可以通过
`requireData<T>()` 访问原始类型对象；`hasData` 能区分缺失与 nullable `null`。

这是受信任的进程内通道。Kache 不会自动记录或上传，脱敏的 `toString()` 不包含 data、
key、metadata、异常 cause 与堆栈。筛选、映射、脱敏、打印和上传由订阅者控制。

## 取消

同 key fetch 会共享，因此 `resource.cancel()` 与 `client.cancel(key)` 会逻辑取消该 key
的所有等待者，`client.cancelAll()` 按 key 计数。命令会恢复请求前快照，不删除数据，
也不停止后续轮询。无法协作取消的 Future 可能继续在后台执行，但迟到 value/error
不能更新状态，也不会制造 fetch failure。

Fetcher 可以把 `context.cancellation.whenCancelled` 桥接到 HTTP cancel token 或 abort
controller，并用 `context.throwIfCancelled()` 获取精确原因。set、invalidate、remove、
clear 与 close 也会用各自原因取消冲突任务。释放单个 handle 不会取消其他 handle
共享的请求。

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
