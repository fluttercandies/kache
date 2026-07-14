# kache_riverpod

[English](README.md)

基于 Kache 核心状态机的 Riverpod provider 与 notifier。状态始终是完整
`KacheSnapshot<T>`，缓存数据、刷新进度、新鲜度、持久化状态和失败可以同时表达。

## 安装

```bash
dart pub add kache_riverpod riverpod
```

Flutter UI 直接 import Riverpod Widget 时，应显式声明 `flutter_riverpod`，不要依赖传递
依赖。

## 快速开始

```dart
import 'dart:async';

import 'package:kache_riverpod/kache_riverpod.dart';
import 'package:riverpod/riverpod.dart';

final class User {
  const User(this.id, this.name);

  final String id;
  final String name;
}

abstract interface class UserApi {
  Future<User> fetchUser(String id);
}

final class UserProviders {
  UserProviders({required this.client, required this.api});

  final KacheClient client;
  final UserApi api;

  late final user = kacheProvider.autoDispose.family<User, String>(
    client: (_) => client,
    query: (_, userId) => KacheQuery<User>.memory(
      key: KacheKey('users', <Object?>[userId]),
      fetch: (_) => api.fetchUser(userId),
    ),
  );
}

Future<void> observeUser(UserApi api, String userId) async {
  final client = KacheClient();
  final providers = UserProviders(client: client, api: api);
  final container = ProviderContainer();
  final subscription = container.listen(
    providers.user(userId),
    (previous, next) {},
    fireImmediately: true,
  );

  try {
    await container.read(providers.user(userId).notifier).refresh();
  } finally {
    subscription.close();
    container.dispose();
    await client.close();
  }
}
```

## Provider builder

- `kacheProvider<T>` 创建普通 notifier provider。
- `kacheProvider.family<T, Arg>` 把 Riverpod family 参数传给 query 构造；同一参数也必须
  放入 `KacheKey`。
- `kacheProvider.autoDispose<T>` 在 Riverpod dispose 后释放 resource。
- `kacheProvider.autoDispose.family<T, Arg>` 组合两者。

client 与 query callback 都接收 `Ref`，可以 watch 普通 Riverpod 依赖。provider 拥有
一个 resource handle，但不会关闭 client。

## 命令与生命周期

读取 notifier 后可以调用 `load`、`refresh`、`setData`、`updateData`、
`invalidate` 和 `remove`。`keepAlive()` 与 `releaseKeepAlive()` 只管理 Riverpod
keep-alive link，不改变核心 cache GC 语义。

provider dispose 会取消快照订阅并释放 resource；延迟完成的 fetch 不会向已销毁
notifier emit。

## Flutter

应用根节点使用 `ProviderScope`。`Consumer` watch Kache provider，并读取 notifier
执行命令。应用还需要自动 resume 重验时，配合 `kache_flutter` 的 `KacheScope`。

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
