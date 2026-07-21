# kache_riverpod

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

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
  Future<User> searchUser(String text, int page);
}

final class UserProviders {
  UserProviders({required this.client, required this.api});

  final KacheClient client;
  final UserApi api;

  late final search = kacheProvider.autoDispose
      .family<User, ({String text, int page})>(
        client: (_) => client,
        query: (_, args) => KacheQuery<User>.memory(
          key: KacheKey('search', <Object?>[args.text, args.page]),
          fetch: (_) => api.searchUser(args.text, args.page),
        ),
      );
}

Future<void> observeUser(UserApi api, String text, int page) async {
  final client = KacheClient();
  final providers = UserProviders(client: client, api: api);
  final container = ProviderContainer();
  final provider = providers.search((text: text, page: page));
  final subscription = container.listen(
    provider,
    (previous, next) {},
    fireImmediately: true,
  );

  try {
    await container.read(provider.notifier).refresh();
  } finally {
    subscription.close();
    container.dispose();
    await client.close();
  }
}
```

## Provider builder

- `kacheProvider<T>` 创建普通 notifier provider。
- `kacheProvider.family<T, Arg>` 把 Riverpod family 参数传给 query 构造；多参数使用
  named record，并把每个字段都放入 `KacheKey`。
- `kacheProvider.autoDispose<T>` 在 Riverpod dispose 后释放 resource。
- `kacheProvider.autoDispose.family<T, Arg>` 组合两者。

builder 通过短别名 `KacheProvider<T>` 和 `KacheProviderFamily<T, Arg>` 返回原生
`NotifierProvider`，不会引入平行的 provider 抽象。

client 与 query callback 都接收 `Ref`，可以 watch 普通 Riverpod 依赖。provider 拥有
当某个依赖会在嵌套 `ProviderScope` 中被 override 时，应按 Riverpod 原生作用域
契约将该依赖声明为 scoped，并在 Kache provider 的 `dependencies` 中列出。
provider 拥有一个 resource handle，但不会关闭 client。

Provider 直接暴露 `KacheSnapshot<T>`。使用 `snapshot.when` 渲染，确保 idle 和保留旧
数据的刷新失败都有显式分支。Kache 不转换为 `AsyncValue`，因为转换会丢失 freshness、
source、persistence，以及“缓存正在刷新”和“缓存伴随错误”的差异。

## 命令与生命周期

通过 notifier 可以调用 `load`、`refresh`、`setData`、`updateData`、
`invalidate` 和 `remove`。如果 notifier 或它的属性会影响 widget `build` 输出，
应 watch `provider.notifier`；如果只在事件中执行命令，应在事件回调内部 read
notifier。这遵循 Riverpod 不在 build 中捕获 `ref.read` 值的建议。`keepAlive()` 与
`releaseKeepAlive()` 只管理 Riverpod keep-alive link，不改变核心 cache GC 语义。

provider dispose 会取消快照订阅并释放 resource；延迟完成的 fetch 不会向已销毁
notifier emit。

`ref.refresh(provider)` 与 `ref.invalidate(provider)` 会重建 Riverpod provider 并
绑定新 resource。`ref.read(provider.notifier).refresh()` 保持 provider 和 resource
身份，只强制执行一次 Kache fetch。

provider 持有活动 resource 时，`refreshInterval` 会按周期刷新。纯 Dart 宿主由 client
owner 调用 `pausePolling()` 和 `resumePolling()` 管理后台计时器。

## Riverpod 互操作

| Riverpod 能力 | Kache 契约 |
| --- | --- |
| `watch`、`read`、`listen`、`select` | 保持原生行为 |
| ProviderScope/Container 与 observer | 保持原生行为 |
| `name` 与 scoped `dependencies` | 所有 builder 原样传递 |
| family、record 参数与 auto-dispose family | 保持原生 family 身份 |
| `keepAlive` | notifier 显式 link，依赖重建时保留意图 |
| provider refresh/invalidate | 重建并重新绑定 provider resource |
| ProviderSubscription pause/resume | 恢复时重放 Riverpod 保留的最后快照 |
| `overrideWith` / family `overrideWith2` | 使用替换 `KacheNotifier`，完整支持 |
| `overrideWithBuild` | 不支持，因为会绕过 Kache resource binding |

Riverpod 3.3.2 的同步 `NotifierProvider` 虽暴露 `retry` 参数，但同步 element 遇到
build 错误时不会调用该 callback，因此 Kache 不暴露误导性的 retry 选项。client/query
build 错误进入 Riverpod 同步 provider 错误通道；fetch 失败是
`KacheSnapshot.failure` 数据，请在 fetcher 内组合请求重试。

Kache 不增加 `AsyncValue` 转换、Riverpod offline persistence、实验 Mutation wrapper
或 code generation。这些能力会丢失缓存状态、制造重复持久化所有权、绑定不稳定 API，
或在没有运行时收益时引入构建系统。应用层 Riverpod mutation 可以直接调用 notifier
命令。

## Flutter

应用根节点使用 `ProviderScope`。`Consumer` watch Kache provider；notifier 要么作为
build 依赖被 watch，要么在命令事件回调中被 read。应用还需要生命周期感知的轮询与
resume 重验时，配合 `kache_flutter` 的 `KacheScope`。

`HookConsumerWidget` 添加 `kache_hooks_riverpod` 并调用
`useKacheProvider(ref, provider)`。它消费现有 provider，不会创建另一份 resource。

## 兼容性

| 组件 | 支持范围 |
| --- | --- |
| Dart | Dart >=3.7.0 <4.0.0 |
| Flutter | 不需要 |
| Riverpod | `>=3.3.2 <4.0.0` |

## 许可证

MIT
