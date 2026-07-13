import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  test(
    'repeated watch and dispose keeps one compatible shared entry',
    () async {
      final scheduler = _StressScheduler();
      final client = KacheClient(scheduler: scheduler.schedule);
      final query = KacheQuery<int>.memory(
        key: KacheKey('watch-stress'),
        policy: KachePolicy.cacheFirst(
          freshFor: const Duration(minutes: 1),
          gcAfter: Duration.zero,
        ),
        fetch: (_) async => 1,
      );

      for (var index = 0; index < 1000; index++) {
        client.watch(query).dispose();
      }

      expect(scheduler.activeTasks, hasLength(1));
      scheduler.activeTasks.single.run();
      final replacement = client.watch(
        KacheQuery<String>.memory(
          key: query.key,
          fetch: (_) async => 'replacement',
        ),
      );
      replacement.dispose();
      await client.close();
    },
  );

  test('many handles share one fetch and close without late events', () async {
    final fetch = Completer<int>();
    var fetchCount = 0;
    final client = KacheClient();
    final query = KacheQuery<int>.memory(
      key: KacheKey('handle-stress'),
      fetch: (_) {
        fetchCount += 1;
        return fetch.future;
      },
    );
    final resources = List<KacheResource<int>>.generate(
      500,
      (_) => client.watch(query),
    );
    final refreshes = resources.map((resource) => resource.refresh()).toList();

    expect(fetchCount, 1);
    for (final resource in resources) {
      resource.dispose();
    }
    fetch.complete(7);
    await Future.wait(refreshes);
    await client.close();

    expect(client.isClosed, isTrue);
  });

  test('close is stable under repeated concurrent calls', () async {
    final client = KacheClient();

    final closes = List<Future<void>>.generate(
      1000,
      (index) => client.close(drainWrites: index.isEven),
    );

    expect(closes.every((future) => identical(future, closes.first)), isTrue);
    await Future.wait(closes);
  });
}

final class _StressScheduler {
  final List<_StressTask> _tasks = <_StressTask>[];

  List<_StressTask> get activeTasks =>
      _tasks.where((task) => !task.isCancelled).toList(growable: false);

  KacheScheduledTask schedule(Duration delay, void Function() callback) {
    final task = _StressTask(callback);
    _tasks.add(task);
    return task;
  }
}

final class _StressTask implements KacheScheduledTask {
  _StressTask(this._callback);

  final void Function() _callback;

  @override
  bool isCancelled = false;

  @override
  void cancel() => isCancelled = true;

  void run() {
    if (!isCancelled) {
      _callback();
    }
  }
}
