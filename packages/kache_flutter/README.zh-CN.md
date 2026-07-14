# kache_flutter

[English](README.md)

Kache 的 Flutter 组件与生命周期接入，不依赖第三方状态管理库。此包会 re-export
完整 `kache` API。

## 安装

```bash
flutter pub add kache_flutter
```

## 快速开始

```dart
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
              if (snapshot.phase == KachePhase.failure) {
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
```

## 组件

- `KacheScope` 提供 client，并把 `AppLifecycleState.resumed` 桥接到策略驱动重验。
- `KacheBuilder<T>` 拥有一个 `KacheController<T>`，根据完整快照重建。
- `KacheListener<T>` 执行副作用，不重建 child。
- `KacheController<T>` 实现 `ValueListenable<KacheSnapshot<T>>`，并暴露所有资源命令。

Widget 收到相同 key 的新 query 时，controller 只更新 handle 的 fetcher 和 policy，不会
丢失共享数据；key 改变时会释放旧 handle 并绑定新资源。

## 所有权

`KacheScopeOwnership.borrowed` 是默认值。只有 scope 本身是负责关闭 client 的应用
边界时才使用 `owned`。Builder、Listener 和 Controller 拥有 resource handle，但不
拥有 client。

生命周期失败可以通过 `KacheScope.onError` 处理；未提供 handler 时会交给
`FlutterError.reportError`。

## 持久化

应用直接 import Hive CE 接口时，应显式依赖 `kache_hive_ce`。创建 scope 前打开 store，
把 owned backend 配置给 client，并使用 persisted query binding。codec 与迁移逻辑
仍留在存储包中。

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
