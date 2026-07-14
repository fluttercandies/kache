# kache_connectivity_plus

<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>

[English](README.md)

Kache 官方 connectivity_plus 网络恢复适配包。它把平台网络接口状态转换为
`KacheNetworkState`，同时让纯 Dart 的 `kache` 核心继续保持无插件依赖。

网络接口可用不等于 Internet 一定可达。Fetcher 仍必须处理超时、DNS、HTTP 失败和
取消。

## 安装

```bash
flutter pub add kache_connectivity_plus
```

## 快速开始

```dart
import 'package:kache_connectivity_plus/kache_connectivity_plus.dart';

KacheClient createClient() {
  final network = ConnectivityPlusNetwork();
  return KacheClient(
    network: network,
    networkOwnership: KacheNetworkOwnership.owned,
  );
}
```

`KachePolicy.staleWhileRevalidate()` 默认会在 `unavailable -> available`
转换后重验活动 handle。每个 query 可把 `refreshOnReconnect` 设为 `always`、
`ifStale` 或 `never`；`cacheOnly` 不会因为网络恢复而请求。

## 状态语义

适配器先订阅变化，再执行首次检查，因此较新的平台事件不会被迟到的检查结果覆盖。
每个订阅者先收到当前规范化状态，之后只收到不同状态。`ConnectivityResult.none`
映射为 `unavailable`，其他非空结果集合映射为 `available`。

首次检查失败、stream 失败、非法空结果和 stream 意外结束都保持可观测。
`KacheClient` 会把来源失败报告为 `KacheFailureKind.connectivity` 事件，但不会清除
缓存快照。

## 所有权

Client 是生命周期边界时使用 `KacheNetworkOwnership.owned`；`close()` 会通过
适配器准确取消一次插件订阅。由外部对象管理适配器时使用 `borrowed`，并在所有
client 停止后显式关闭适配器。

`ConnectivityPlusNetwork(connectivity: ...)` 可注入显式 `Connectivity` 实现，
便于确定性测试。接入其他插件或可达性服务时，在独立包中实现仅依赖 SDK 的
`KacheNetwork` 接口，再用相同方式交给 `KacheClient`。
自定义 stream 必须为每个订阅者先重放当前状态：

```dart
final class AppNetwork implements KacheNetwork {
  AppNetwork({required this.states, required Future<void> Function() close})
    : _close = close;

  @override
  final Stream<KacheNetworkState> states;

  final Future<void> Function() _close;

  @override
  Future<void> close() => _close();
}
```

宿主管理 `_close` 时把 `AppNetwork` 作为 borrowed 传入；由 `KacheClient` 负责关闭
时使用 owned。

## Flutter 生命周期

把 client 放入 `KacheScope`。应用处于 inactive、hidden、paused 或 detached 时，
scope 会暂停 reconnect 重验；恢复前台后只消费一次待处理恢复。网络状态观察不会
暂停，因此后台期间的恢复信号不会丢失。

## 兼容性

| 组件 | 支持范围 |
| --- | --- |
| Dart | Dart >=3.5.0 <4.0.0 |
| Flutter | Flutter >=3.24.0 |
| connectivity_plus | `>=7.2.0 <8.0.0` |
| Android | minSdk 21、Java 17、AGP >=8.12.1、Gradle >=8.13、Kotlin 2.2.0 |
| Apple | iOS >=12.0、macOS >=10.14、Xcode >=26.1.1 |

通过 connectivity_plus 7.2.0 支持 Android、iOS、macOS、Linux、Windows 和 Web。
connectivity 只表示存在可用网络接口，不代表已经验证 Internet 可达。即使 Flutter SDK
约束能够解析，已有 Android 工程仍必须满足上表中的原生构建工具要求。

## 许可证

MIT
