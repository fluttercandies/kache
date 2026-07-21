# kache_hooks_riverpod

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[English](README.md)

已有 Kache provider 的 Hooks Riverpod 接入。它 watch provider 拥有的 snapshot 并
暴露 notifier 命令，不会创建第二份缓存 resource。

## 安装

```bash
flutter pub add kache_hooks_riverpod hooks_riverpod
```

## 快速开始

```dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kache_hooks_riverpod/kache_hooks_riverpod.dart';

typedef Profile = ({String name});

final clientProvider = Provider<KacheClient>((ref) {
  throw StateError('Override clientProvider at the application boundary.');
}, dependencies: const []);

final profileProvider = kacheProvider<Profile>(
  client: (ref) => ref.watch(clientProvider),
  query: (ref) => KacheQuery<Profile>.memory(
    key: KacheKey('profile'),
    fetch: (_) async => (name: 'Ada'),
  ),
  dependencies: [clientProvider],
);

final class ProfilePage extends HookConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = useKacheProvider(ref, profileProvider);
    return cache.snapshot.when(
      idle: () => const SizedBox.shrink(),
      loading: () => const Center(child: CircularProgressIndicator()),
      failed: (_) =>
          FilledButton(onPressed: cache.load, child: const Text('Try again')),
      ready: (profile) => ListTile(
        title: Text(profile.name),
        trailing: IconButton(
          onPressed: cache.refresh,
          icon: const Icon(Icons.refresh),
        ),
      ),
      refreshError: (profile, _) => ListTile(
        title: Text(profile.name),
        subtitle: const Text('Refresh failed - showing cached data'),
      ),
    );
  }
}

Widget createProfileApp() {
  final client = KacheClient();
  return ProviderScope(
    overrides: [clientProvider.overrideWithValue(client)],
    child: const MaterialApp(home: ProfilePage()),
  );
}
```

`useKacheProvider` 接收已有 `KacheProvider<T>`。Riverpod 仍是底层
`KacheResource` 的唯一所有者，因此 family 参数、scope、override、auto-dispose、
keep-alive、observer 和 provider subscription 都保持原生行为。

返回的 `KacheProviderBinding<T>` 包含当前 build watch 的 snapshot 与
notifier，以及 `load`、`refresh`、`setData`、`updateData`、`invalidate`、`remove`、
`keepAlive` 和 `releaseKeepAlive` 代理。

快速开始中的 `clientProvider` 会在嵌套 `ProviderScope` 中被 override，因此显式
声明为 scoped，并在 `profileProvider` 的 `dependencies` 中列出。client、query 输入、
租户或会话 provider 需要作用域化时都应保持这个 Riverpod 声明模式。

本包不创建 provider，也不把 snapshot 映射为 `AsyncValue`。先用 `kacheProvider`
定义 provider，再在这里消费。应用源码使用 `HookConsumerWidget` 时必须直接声明并
import `hooks_riverpod`。

## 兼容性

| 组件 | 支持范围 |
| --- | --- |
| Dart | Dart >=3.8.0 <4.0.0 |
| Flutter | Flutter >=3.32.0 |
| hooks_riverpod | `>=3.3.2 <4.0.0` |

## 许可证

MIT
