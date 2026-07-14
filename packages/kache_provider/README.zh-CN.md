# kache_provider

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
```

## Provider 组件

`KacheProvider<T>` 创建并销毁一个 `KacheController<T>`。可以显式传入 client，也可
省略并读取最近的 `KacheScope`。相同 key 的 query 更新保留共享数据，新 key 会重新
绑定 controller。

`KacheConsumer<T>` 根据当前快照重建，并提供 controller 执行命令。它支持普通
Provider consumer 的静态 `child` 语义。

不订阅地执行命令使用 `context.readKache<T>()`；根据最近快照重建使用
`context.watchKache<T>()`。

## 所有权

provider 拥有 controller 和 resource handle，但始终借用 client。client 所有权应放在
应用边界，通过 `KacheScopeOwnership.owned` 管理，或由外部所有者自行关闭。

不要在频繁重建的 Widget 中创建 client，应把它放在应用状态、依赖注入或 owned
`KacheScope` 中。

## 持久化与生命周期

先打开 `kache_hive_ce` 等 backend，创建 client，再把 `KacheScope` 放在
`KacheProvider` 上方以获得自动 resume 重验。Provider 适配器不会复制持久化或
生命周期状态。

## 兼容性

| 组件 | 支持范围 |
| --- | --- |
| Dart | Dart >=3.9.0 <4.0.0 |
| Flutter | Flutter >=3.35.0 |
| Hive CE | `>=2.19.3 <3.0.0` |
| Riverpod | `>=3.3.2 <4.0.0` |
| Bloc | `>=9.2.1 <10.0.0` |
| Provider | `>=6.1.5+1 <7.0.0` |

## 许可证

MIT
