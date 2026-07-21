# kache_flutter

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

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

typedef Profile = ({String name});

Widget createProfileApp({required Future<Profile> Function() fetchProfile}) =>
    KacheScope(
      client: KacheClient(),
      ownership: KacheScopeOwnership.owned,
      child: MaterialApp(
        home: Scaffold(
          body: KacheBuilder<Profile>(
            query: KacheQuery<Profile>.memory(
              key: KacheKey('profile'),
              fetch: (_) => fetchProfile(),
            ),
            builder: (context, snapshot, controller) => snapshot.when(
              idle: () => const SizedBox.shrink(),
              loading: () => const Center(child: CircularProgressIndicator()),
              failed: (_) => Center(
                child: FilledButton(
                  onPressed: controller.load,
                  child: const Text('Try again'),
                ),
              ),
              ready: (profile) => _profileList(
                profile,
                controller,
                refreshing: snapshot.isRefreshing,
              ),
              refreshError: (profile, _) =>
                  _profileList(profile, controller, refreshFailed: true),
            ),
          ),
        ),
      ),
    );

Widget _profileList(
  Profile profile,
  KacheController<Profile> controller, {
  bool refreshing = false,
  bool refreshFailed = false,
}) => RefreshIndicator(
  onRefresh: () async => controller.refresh(),
  child: ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: <Widget>[
      ListTile(
        title: Text(profile.name),
        subtitle: refreshFailed
            ? const Text('Refresh failed - showing cached data')
            : null,
        trailing: refreshing
            ? const CircularProgressIndicator()
            : const Icon(Icons.cloud_done),
      ),
    ],
  ),
);
```

Builder 会自动加载。`snapshot.when` 会显式处理 idle、首次 loading、无数据失败、ready
数据和保留旧数据的刷新失败。后台刷新时缓存数据仍然可见；只有需要用 loading 替换
数据界面时才设置 `skipLoadingOnRefresh: false`。下拉刷新会显式调用同一个自动去重的
query。

## 组件

- `KacheScope` 提供 client，在离开前台时暂停轮询，并把
  `AppLifecycleState.resumed` 桥接到策略驱动重验；reconnect 工作也会延后到应用
  返回前台。
- `KacheBuilder<T>` 拥有一个 `KacheController<T>`，根据完整快照重建。
- `KacheListener<T>` 执行副作用，不重建 child。
- `KacheController<T>` 实现 `ValueListenable<KacheSnapshot<T>>`，并暴露所有资源命令。

`HookWidget` 使用独立的 `kache_flutter_hooks` 包。它的 `useKache(query)` 返回同一个
controller 类型，不增加第二套状态模型。

Widget 收到相同 key 的新 query 时，controller 只更新 handle 的 fetcher 和 policy，不会
丢失共享数据；key 改变时会释放旧 handle 并绑定新资源。

## 所有权

`KacheScopeOwnership.borrowed` 是默认值。只有 scope 本身是负责关闭 client 的应用
边界时才使用 `owned`。Builder、Listener 和 Controller 拥有 resource handle，但不
拥有 client。

生命周期失败可以通过 `KacheScope.onError` 处理；未提供 handler 时会交给
`FlutterError.reportError`。

在 query policy 设置 `refreshInterval` 即可轮询活动资源。scope 会在 inactive、
hidden、paused 和 detached 状态暂停计时器，恢复时重新计算完整周期，再执行
`refreshOnResume`。

配置 `KacheNetwork` 后，scope 在后台仍观察可用性，但暂停 reconnect 重验；恢复时
最多消费一次待处理恢复。官方插件适配包是 `kache_connectivity_plus`。

## 持久化

应用直接 import Hive CE 接口时，应显式依赖 `kache_hive_ce`。创建 scope 前打开 store，
把 owned backend 配置给 client，并使用 persisted query binding。codec 与迁移逻辑
仍留在存储包中。

## 兼容性

| 组件 | 支持范围 |
| --- | --- |
| Dart | Dart >=3.5.0 <4.0.0 |
| Flutter | Flutter >=3.24.0 |

## 许可证

MIT
