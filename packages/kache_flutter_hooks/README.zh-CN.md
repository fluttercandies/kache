# kache_flutter_hooks

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[English](README.md)

Kache 的 Flutter Hooks 生命周期接入。它直接返回普通 `KacheController<T>`，因此
Hooks 和非 Hooks Widget 共用同一缓存状态机及命令语义。

## 安装

```bash
flutter pub add kache_flutter_hooks flutter_hooks
```

## 快速开始

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:kache_flutter_hooks/kache_flutter_hooks.dart';

typedef Profile = ({String name});

final class ProfilePage extends HookWidget {
  const ProfilePage({required this.query, super.key});

  final KacheQuery<Profile> query;

  @override
  Widget build(BuildContext context) {
    final cache = useKache(query);
    return cache.snapshot.when(
      idle: () => const SizedBox.shrink(),
      loading: () => const Center(child: CircularProgressIndicator()),
      failed: (_) =>
          FilledButton(onPressed: cache.load, child: const Text('Try again')),
      ready: (profile) => ListTile(
        title: Text(profile.name),
        trailing: cache.snapshot.isRefreshing
            ? const CircularProgressIndicator()
            : IconButton(
                onPressed: cache.refresh,
                icon: const Icon(Icons.refresh),
              ),
      ),
      refreshError: (profile, _) => ListTile(
        title: Text(profile.name),
        subtitle: const Text('Refresh failed - showing cached data'),
        trailing: IconButton(
          onPressed: cache.refresh,
          icon: const Icon(Icons.refresh),
        ),
      ),
    );
  }
}

Widget createProfileApp({required Future<Profile> Function() fetchProfile}) {
  final client = KacheClient();
  return KacheScope(
    client: client,
    ownership: KacheScopeOwnership.owned,
    child: MaterialApp(
      home: ProfilePage(
        query: KacheQuery<Profile>.memory(
          key: KacheKey('profile'),
          fetch: (_) => fetchProfile(),
        ),
      ),
    ),
  );
}
```

`useKache` 默认解析最近的 `KacheScope` client。Widget 明确需要使用 scope 外的 client
时传入 `client:`。Hook 会自动 load、根据 `KacheSnapshot` 重建、更新同 key 的 fetcher
与 policy，并释放 controller。

client 或 key 改变会创建新 controller，并隔离旧 binding 的延迟结果；同 key query
更新会保留 controller 和缓存数据。Hook 不拥有也不会关闭 client。

## API

- `useKache<T>(query, client:)` 返回 `KacheController<T>`。
- `cache.snapshot` 是 `cache.value` 的可读别名。
- `load`、`refresh`、`setData`、`updateData`、`invalidate` 和 `remove` 都是既有
  controller 命令。

本包 re-export `kache_flutter`，但不 re-export `flutter_hooks`。源码使用
`HookWidget` 时，应用必须直接声明并 import `flutter_hooks`。

## 兼容性

| 组件 | 支持范围 |
| --- | --- |
| Dart | Dart >=3.8.0 <4.0.0 |
| Flutter | Flutter >=3.32.0 |
| flutter_hooks | `>=0.21.3+1 <0.22.0` |

## 许可证

MIT
