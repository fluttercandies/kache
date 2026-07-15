# kache_bloc

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[English](README.md)

Kache 的纯 Dart Bloc/Cubit 接入。它把完整 `KacheSnapshot<T>` 作为 state，并且不依赖
`flutter_bloc`。

## 安装

```bash
dart pub add kache_bloc
```

Flutter 应用使用 `BlocProvider` 或 `BlocBuilder` 时，还应执行
`flutter pub add flutter_bloc` 并直接 import。

## 快速开始

```dart
import 'dart:async';

import 'package:kache_bloc/kache_bloc.dart';

final class User {
  const User(this.id, this.name);

  final String id;
  final String name;
}

abstract interface class UserApi {
  Future<User> fetchUser(String id);
}

Future<void> observeUser(UserApi api, String userId) async {
  final client = KacheClient();
  final cubit = KacheCubit<User>(
    client: client,
    query: KacheQuery<User>.memory(
      key: KacheKey('users', <Object?>[userId]),
      fetch: (_) => api.fetchUser(userId),
    ),
  );
  final subscription = cubit.stream.listen(
    (snapshot) => snapshot.when<void>(
      idle: () {},
      loading: () => print('Loading user'),
      ready: (user) => print(user.name),
      refreshError: (user, _) => print('${user.name} (refresh failed)'),
      failed: (_) => print('Could not load user'),
    ),
  );

  try {
    await cubit.load();
  } finally {
    await subscription.cancel();
    await cubit.close();
    await client.close();
  }
}
```

## KacheCubit

`KacheCubit<T>` 拥有一个核心 resource，并发出它的快照。命令包括 `load`、
`refresh`、`setData`、`updateData`、`invalidate` 和 `remove`。关闭 Cubit 会取消
订阅并释放 resource，但不会关闭传入的 client。

`refresh` 返回 `Future<KacheSnapshot<T>>`，命令式调用方可以检查完成后的状态。使用
`snapshot.when` 渲染可以显式处理 idle 和保留数据的刷新失败；Bloc 适配器不会创建
第二套异步状态模型。

Cubit 活动时可在 query policy 设置 `refreshInterval`。纯 Dart client owner 可用
`pausePolling()` 和 `resumePolling()` 暂停与恢复这些计时器。

业务命令适合放在同一个 Cubit 时，可以继承 `KacheCubit<T>`。所有网络参数都必须进入
query key。

## 可组合 binding

已有 Bloc/Cubit 已经拥有业务 state 时，使用 `KacheBlocBinding<T>`。创建 binding，
调用一次 `attach` 接入 emit，按需代理缓存命令，并在宿主 close 中 await
`binding.close()`。

binding 只允许一个受管 listener，确保 resource 所有权明确；attach 前可以读取
`snapshot` 作为宿主初始状态。

## Flutter

在 `BlocProvider.create` 中创建 `KacheCubit`，通过
`BlocBuilder<KacheCubit<T>, KacheSnapshot<T>>` 渲染。页面需要在 descendant 首次
读取前开始缓存加载时，设置 `lazy: false`。

需要生命周期感知的轮询与 resume 重验时，在应用外层使用 `kache_flutter` 的
`KacheScope`。

## 兼容性

| 组件 | 支持范围 |
| --- | --- |
| Dart | Dart >=3.5.0 <4.0.0 |
| Flutter | 不需要 |
| Bloc | `>=9.2.1 <10.0.0` |

## 许可证

MIT
