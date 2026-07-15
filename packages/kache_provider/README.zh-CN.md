# kache_provider

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[English](README.md)

基于 `KacheController<T>` 实现的 Provider 接入。此包 re-export
`kache_flutter`，一个 import 即可获得适配器使用的核心与 Flutter API。

## 安装

```bash
flutter pub add kache_provider
```

只有应用源码直接 import 本包组件之外的 Provider API 时，才需要显式声明 `provider`。

## 快速开始

```dart
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
```

## Provider 组件

`KacheProvider<T>` 创建并销毁一个 `KacheController<T>`。可以显式传入 client，也可
省略并读取最近的 `KacheScope`。相同 key 的 query 更新保留共享数据，新 key 会重新
绑定 controller。

`KacheConsumer<T>` 根据当前快照重建，并提供 controller 执行命令。它支持普通
Provider consumer 的静态 `child` 语义。

使用 `snapshot.when` 完整处理 idle/loading/data/error。controller 的 `refresh` 返回
`Future<KacheSnapshot<T>>`；Provider 只负责核心 resource 生命周期适配，不复制状态机。

不订阅地执行命令使用 `context.readKache<T>()`；根据最近快照重建使用
`context.watchKache<T>()`。

## 所有权

provider 拥有 controller 和 resource handle，但始终借用 client。client 所有权应放在
应用边界，通过 `KacheScopeOwnership.owned` 管理，或由外部所有者自行关闭。

不要在频繁重建的 Widget 中创建 client，应把它放在应用状态、依赖注入或 owned
`KacheScope` 中。

## 持久化与生命周期

先打开 `kache_hive_ce` 等 backend，创建 client，再把 `KacheScope` 放在
`KacheProvider` 上方以获得生命周期感知的 `refreshInterval` 轮询和 resume 重验。
Provider 适配器不会复制持久化或生命周期状态。

## 兼容性

| 组件 | 支持范围 |
| --- | --- |
| Dart | Dart >=3.5.0 <4.0.0 |
| Flutter | Flutter >=3.24.0 |
| Provider | `>=6.1.5+1 <7.0.0` |

## 许可证

MIT
