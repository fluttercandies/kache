import 'dart:async';

import 'package:kache_riverpod/kache_riverpod.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

void main() {
  test(
    'autoDispose releases its core resource after the last listener',
    () async {
      final scheduler = _ManualScheduler();
      final client = KacheClient(scheduler: scheduler.call);
      final provider = kacheProvider.autoDispose<int>(
        client: (ref) => client,
        query: (ref) => _query('auto'),
      );
      final container = ProviderContainer();
      final subscription = container.listen(
        provider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        container.dispose();
        await client.close();
      });

      await pumpEventQueue();
      subscription.close();
      await container.pump();

      expect(scheduler.activeTasks, hasLength(1));
      scheduler.runAll();
      expect(client.peek<int>(_query('auto').key), isNull);
    },
  );

  test('keepAlive link delays autoDispose until explicitly released', () async {
    final scheduler = _ManualScheduler();
    final client = KacheClient(scheduler: scheduler.call);
    final provider = kacheProvider.autoDispose<int>(
      client: (ref) => client,
      query: (ref) => _query('kept'),
    );
    final container = ProviderContainer();
    final subscription = container.listen(
      provider,
      (previous, next) {},
      fireImmediately: true,
    );
    final notifier = container.read(provider.notifier);
    addTearDown(() async {
      container.dispose();
      await client.close();
    });

    notifier.keepAlive();
    subscription.close();
    await container.pump();

    expect(notifier.isKeptAlive, isTrue);
    expect(scheduler.activeTasks, isEmpty);

    notifier.releaseKeepAlive();
    await container.pump();

    expect(scheduler.activeTasks, hasLength(1));
  });

  test('manual keepAlive survives a dependency-driven rebuild', () async {
    final scheduler = _ManualScheduler();
    final client = KacheClient(scheduler: scheduler.call);
    final dependency = NotifierProvider<_Counter, int>(_Counter.new);
    final provider = kacheProvider.autoDispose<int>(
      client: (ref) => client,
      query: (ref) => _query('rebuild-${ref.watch(dependency)}'),
    );
    final container = ProviderContainer();
    final subscription = container.listen(
      provider,
      (previous, next) {},
      fireImmediately: true,
    );
    final notifier = container.read(provider.notifier);
    addTearDown(() async {
      container.dispose();
      await client.close();
    });

    notifier.keepAlive();
    container.read(dependency.notifier).increment();
    await container.pump();

    expect(container.read(provider.notifier), same(notifier));
    expect(notifier.isKeptAlive, isTrue);
    final tasksAfterRebuild = scheduler.activeTasks.length;
    subscription.close();
    await container.pump();
    expect(scheduler.activeTasks, hasLength(tasksAfterRebuild));

    notifier.releaseKeepAlive();
    await container.pump();
    expect(scheduler.activeTasks, hasLength(tasksAfterRebuild + 1));
  });

  test('autoDispose can acquire keepAlive during provider creation', () async {
    final scheduler = _ManualScheduler();
    final client = KacheClient(scheduler: scheduler.call);
    final provider = kacheProvider.autoDispose<int>(
      client: (ref) => client,
      query: (ref) => _query('initially-kept'),
      keepAlive: true,
    );
    final container = ProviderContainer();
    final subscription = container.listen(
      provider,
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      container.dispose();
      await client.close();
    });

    await pumpEventQueue();
    subscription.close();
    await container.pump();

    expect(container.read(provider.notifier).isKeptAlive, isTrue);
    expect(scheduler.activeTasks, isEmpty);
  });

  test(
    'container disposal releases resources from regular providers',
    () async {
      final scheduler = _ManualScheduler();
      final client = KacheClient(scheduler: scheduler.call);
      final provider = kacheProvider<int>(
        client: (ref) => client,
        query: (ref) => _query('container'),
      );
      final container = ProviderContainer();
      container.listen(provider, (previous, next) {}, fireImmediately: true);
      await pumpEventQueue();

      container.dispose();

      expect(scheduler.activeTasks, hasLength(1));
      await client.close();
    },
  );

  test('autoDispose family releases only the unused argument', () async {
    final scheduler = _ManualScheduler();
    final client = KacheClient(scheduler: scheduler.call);
    final family = kacheProvider.autoDispose.family<int, String>(
      client: (ref) => client,
      query: (ref, id) => _query(id),
    );
    final container = ProviderContainer();
    final first = container.listen(
      family('first'),
      (previous, next) {},
      fireImmediately: true,
    );
    final second = container.listen(
      family('second'),
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      second.close();
      container.dispose();
      await client.close();
    });
    await pumpEventQueue();

    first.close();
    await container.pump();
    scheduler.runAll();

    expect(client.peek<int>(_query('first').key), isNull);
    expect(client.peek<int>(_query('second').key), isNotNull);
  });

  test('autoDispose family supports initial keepAlive per argument', () async {
    final scheduler = _ManualScheduler();
    final client = KacheClient(scheduler: scheduler.call);
    final family = kacheProvider.autoDispose.family<int, String>(
      client: (ref) => client,
      query: (ref, id) => _query(id),
      keepAlive: true,
    );
    final container = ProviderContainer();
    final subscription = container.listen(
      family('kept-family'),
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      container.dispose();
      await client.close();
    });
    await pumpEventQueue();

    subscription.close();
    await container.pump();

    expect(scheduler.activeTasks, isEmpty);
    expect(container.read(family('kept-family').notifier).isKeptAlive, isTrue);
  });

  test(
    'pending fetch completion cannot emit after provider disposal',
    () async {
      final client = KacheClient();
      final fetch = Completer<int>();
      final provider = kacheProvider.autoDispose<int>(
        client: (ref) => client,
        query: (ref) => KacheQuery.memory(
          key: KacheKey('riverpod-lifecycle', <Object?>['pending']),
          fetch: (context) => fetch.future,
          policy: KachePolicy.staleWhileRevalidate(gcAfter: Duration.zero),
        ),
      );
      final container = ProviderContainer();
      final subscription = container.listen(
        provider,
        (previous, next) {},
        fireImmediately: true,
      );
      await pumpEventQueue();

      subscription.close();
      await container.pump();
      fetch.complete(42);
      await fetch.future;
      await pumpEventQueue();

      container.dispose();
      await client.close();
    },
  );
}

KacheQuery<int> _query(String id) => KacheQuery.memory(
  key: KacheKey('riverpod-lifecycle', <Object?>[id]),
  policy: KachePolicy.cacheOnly(gcAfter: Duration.zero),
);

final class _ManualScheduler {
  final List<_ManualTask> _tasks = <_ManualTask>[];

  Iterable<_ManualTask> get activeTasks =>
      _tasks.where((task) => !task.isCancelled);

  KacheScheduledTask call(Duration delay, void Function() callback) {
    final task = _ManualTask(callback);
    _tasks.add(task);
    return task;
  }

  void runAll() {
    for (final task in _tasks.toList(growable: false)) {
      task.run();
    }
  }
}

final class _Counter extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state += 1;
}

final class _ManualTask implements KacheScheduledTask {
  _ManualTask(this._callback);

  final void Function() _callback;
  bool _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  void cancel() => _isCancelled = true;

  void run() {
    if (!_isCancelled) {
      _isCancelled = true;
      _callback();
    }
  }
}
