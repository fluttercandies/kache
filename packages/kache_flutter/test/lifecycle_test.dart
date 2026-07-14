import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache_flutter/kache_flutter.dart';

void main() {
  testWidgets('app resume revalidates active resources by policy', (
    tester,
  ) async {
    final client = KacheClient();
    var fetches = 0;
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('app-resume'),
        policy: KachePolicy.cacheFirst(
          freshFor: const Duration(hours: 1),
          refreshOnResume: KacheRevalidation.always,
        ),
        fetch: (_) async => ++fetches,
      ),
    );
    await resource.load();
    await tester.pumpWidget(
      KacheScope(client: client, child: const SizedBox()),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(fetches, 2);
    resource.dispose();
    await client.close();
  });

  testWidgets('host can explicitly refresh active resources', (tester) async {
    final client = KacheClient();
    var fetches = 0;
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('network-restored'),
        fetch: (_) async => ++fetches,
      ),
    );
    await resource.load();
    late BuildContext scopedContext;
    await tester.pumpWidget(
      KacheScope(
        client: client,
        child: Builder(
          builder: (context) {
            scopedContext = context;
            return const SizedBox();
          },
        ),
      ),
    );

    await KacheScope.refreshActive(scopedContext);

    expect(fetches, 2);
    resource.dispose();
    await client.close();
  });

  testWidgets('app lifecycle pauses and resumes polling', (tester) async {
    final scheduler = _ManualScheduler();
    final client = KacheClient(scheduler: scheduler.schedule);
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('lifecycle-polling'),
        policy: KachePolicy.cacheFirst(
          freshFor: const Duration(hours: 1),
          refreshOnResume: KacheRevalidation.never,
          refreshInterval: const Duration(minutes: 5),
        ),
        fetch: (_) async => 1,
      ),
    );
    await resource.load();
    await tester.pumpWidget(
      KacheScope(client: client, child: const SizedBox()),
    );

    for (final state in const <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      final task = scheduler.activeTasks.single;
      tester.binding.handleAppLifecycleStateChanged(state);
      expect(task.isCancelled, isTrue, reason: state.name);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(scheduler.activeTasks, hasLength(1), reason: state.name);
    }

    resource.dispose();
    await client.close();
  });

  testWidgets('app lifecycle defers reconnect refresh until resumed', (
    tester,
  ) async {
    final network = _FakeNetwork();
    final client = KacheClient(network: network);
    var fetches = 0;
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('lifecycle-reconnect'),
        policy: KachePolicy.staleWhileRevalidate(
          refreshOnLoad: KacheRevalidation.never,
          refreshOnResume: KacheRevalidation.never,
        ),
        fetch: (_) async => ++fetches,
      ),
    );
    addTearDown(() async {
      resource.dispose();
      await client.close();
      await network.close();
    });
    network.emit(KacheNetworkState.unavailable);
    await tester.pumpWidget(
      KacheScope(client: client, child: const SizedBox()),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    network.emit(KacheNetworkState.available);
    await tester.pump();
    expect(fetches, 0);

    final reconnectCompleted = client.events.firstWhere(
      (event) => event.kind == KacheEventKind.reconnectCompleted,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(fetches, 1);
    await reconnectCompleted;
  });

  testWidgets('replacement client inherits the current inactive state', (
    tester,
  ) async {
    final firstScheduler = _ManualScheduler();
    final secondScheduler = _ManualScheduler();
    final first = KacheClient(scheduler: firstScheduler.schedule);
    final second = KacheClient(scheduler: secondScheduler.schedule);
    final firstResource = first.watch(_pollingQuery('first-client'));
    final secondResource = second.watch(_pollingQuery('second-client'));
    await firstResource.load();
    await secondResource.load();
    await tester.pumpWidget(KacheScope(client: first, child: const SizedBox()));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(firstScheduler.activeTasks, isEmpty);
    expect(secondScheduler.activeTasks, hasLength(1));

    await tester.pumpWidget(
      KacheScope(client: second, child: const SizedBox()),
    );
    expect(secondScheduler.activeTasks, isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(secondScheduler.activeTasks, hasLength(1));

    firstResource.dispose();
    secondResource.dispose();
    await first.close();
    await second.close();
  });
}

KacheQuery<int> _pollingQuery(String key) => KacheQuery<int>.memory(
  key: KacheKey(key),
  policy: KachePolicy.cacheFirst(
    freshFor: const Duration(hours: 1),
    refreshOnResume: KacheRevalidation.never,
    refreshInterval: const Duration(minutes: 5),
  ),
  fetch: (_) async => 1,
);

final class _ManualScheduler {
  final List<_ManualTask> _tasks = <_ManualTask>[];

  List<_ManualTask> get activeTasks =>
      _tasks.where((task) => !task.isCancelled).toList(growable: false);

  KacheScheduledTask schedule(Duration delay, void Function() callback) {
    final task = _ManualTask();
    _tasks.add(task);
    return task;
  }
}

final class _ManualTask implements KacheScheduledTask {
  @override
  bool isCancelled = false;

  @override
  void cancel() => isCancelled = true;
}

final class _FakeNetwork implements KacheNetwork {
  final StreamController<KacheNetworkState> _states =
      StreamController<KacheNetworkState>.broadcast(sync: true);

  @override
  Stream<KacheNetworkState> get states => _states.stream;

  void emit(KacheNetworkState state) => _states.add(state);

  @override
  Future<void> close() => _states.close();
}
