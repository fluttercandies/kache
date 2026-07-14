import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  test('polling starts after load and refreshes at the interval', () async {
    final time = _ManualTime();
    var fetches = 0;
    final client = _client(time);
    final resource = client.watch(
      _query(
        key: KacheKey('polling-basic'),
        interval: const Duration(minutes: 5),
        fetch: (_) async => ++fetches,
      ),
    );

    expect(time.activeTasks, isEmpty);
    await resource.load();
    expect(fetches, 1);

    await time.elapse(const Duration(minutes: 4, seconds: 59));
    expect(fetches, 1);
    await time.elapse(const Duration(seconds: 1));
    expect(fetches, 2);
    expect(resource.snapshot.requireData, 2);

    resource.dispose();
    await client.close();
  });

  test('network-only queries can poll without cache lookups', () async {
    final time = _ManualTime();
    final events = <KacheEvent>[];
    var fetches = 0;
    final client = KacheClient(
      clock: () => time.now,
      scheduler: time.schedule,
      observer: events.add,
    );
    final resource = client.watch(
      KacheQuery<int>.networkOnly(
        key: KacheKey('polling-network-only'),
        refreshInterval: const Duration(minutes: 1),
        fetch: (_) async => ++fetches,
      ),
    );

    await resource.load();
    await time.elapse(const Duration(minutes: 1));

    expect(fetches, 2);
    expect(events.where((event) => event.layer != null), isEmpty);
    resource.dispose();
    await client.close();
  });

  test('polling never overlaps a slow fetch', () async {
    final time = _ManualTime();
    final secondFetch = Completer<int>();
    var fetches = 0;
    final client = _client(time);
    final resource = client.watch(
      _query(
        key: KacheKey('polling-overlap'),
        interval: const Duration(minutes: 1),
        fetch: (_) {
          fetches += 1;
          return fetches == 2 ? secondFetch.future : Future.value(fetches);
        },
      ),
    );
    await resource.load();

    await time.elapse(const Duration(minutes: 1));
    expect(fetches, 2);
    expect(time.activeTasks, isEmpty);
    await time.elapse(const Duration(minutes: 5));
    expect(fetches, 2);

    secondFetch.complete(2);
    await _flush();
    await time.elapse(const Duration(minutes: 1));
    expect(fetches, 3);

    resource.dispose();
    await client.close();
  });

  test('shared handles use the latest fetch to prevent over-polling', () async {
    final time = _ManualTime();
    var fetches = 0;
    final client = _client(time);
    final key = KacheKey('polling-shared');
    final fast = client.watch(
      _query(
        key: key,
        interval: const Duration(minutes: 1),
        fetch: (_) async => ++fetches,
      ),
    );
    final slow = client.watch(
      _query(
        key: key,
        interval: const Duration(minutes: 5),
        fetch: (_) async => ++fetches,
      ),
    );
    await fast.load();
    await slow.load();

    await time.elapse(const Duration(minutes: 5));

    expect(fetches, 6);
    fast.dispose();
    slow.dispose();
    await client.close();
  });

  test('failed polls retry only after the next interval', () async {
    final time = _ManualTime();
    var fetches = 0;
    final client = _client(time);
    final resource = client.watch(
      _query(
        key: KacheKey('polling-failure'),
        interval: const Duration(minutes: 2),
        fetch: (_) async {
          fetches += 1;
          if (fetches == 2) {
            throw StateError('offline');
          }
          return fetches;
        },
      ),
    );
    await resource.load();

    await time.elapse(const Duration(minutes: 2));
    expect(fetches, 2);
    expect(resource.snapshot.hasData, isTrue);
    expect(resource.snapshot.hasFailure, isTrue);
    await time.elapse(const Duration(minutes: 1, seconds: 59));
    expect(fetches, 2);
    await time.elapse(const Duration(seconds: 1));
    expect(fetches, 3);
    expect(resource.snapshot.hasFailure, isFalse);

    resource.dispose();
    await client.close();
  });

  test('manual refresh resets the polling interval', () async {
    final time = _ManualTime();
    var fetches = 0;
    final client = _client(time);
    final resource = client.watch(
      _query(
        key: KacheKey('polling-manual'),
        interval: const Duration(minutes: 5),
        fetch: (_) async => ++fetches,
      ),
    );
    await resource.load();

    await time.elapse(const Duration(minutes: 2));
    await resource.refresh();
    await time.elapse(const Duration(minutes: 4, seconds: 59));
    expect(fetches, 2);
    await time.elapse(const Duration(seconds: 1));
    expect(fetches, 3);

    resource.dispose();
    await client.close();
  });

  test('updateQuery replaces and reschedules the interval', () async {
    final time = _ManualTime();
    var fetches = 0;
    final client = _client(time);
    final key = KacheKey('polling-update');
    final resource = client.watch(
      _query(
        key: key,
        interval: const Duration(minutes: 5),
        fetch: (_) async => ++fetches,
      ),
    );
    await resource.load();
    await time.elapse(const Duration(minutes: 1));

    resource.updateQuery(
      _query(
        key: key,
        interval: const Duration(minutes: 10),
        fetch: (_) async => ++fetches,
      ),
    );
    await time.elapse(const Duration(minutes: 8, seconds: 59));
    expect(fetches, 1);
    await time.elapse(const Duration(seconds: 1));
    expect(fetches, 2);

    resource.dispose();
    await client.close();
  });

  test('pause and resume restart a full polling interval', () async {
    final time = _ManualTime();
    var fetches = 0;
    final client = _client(time);
    final resource = client.watch(
      _query(
        key: KacheKey('polling-pause'),
        interval: const Duration(minutes: 5),
        fetch: (_) async => ++fetches,
      ),
    );
    await resource.load();

    client.pausePolling();
    expect(time.activeTasks, isEmpty);
    await time.elapse(const Duration(hours: 1));
    expect(fetches, 1);
    client.resumePolling();
    await time.elapse(const Duration(minutes: 4, seconds: 59));
    expect(fetches, 1);
    await time.elapse(const Duration(seconds: 1));
    expect(fetches, 2);

    resource.dispose();
    await client.close();
  });

  test('dispose and close cancel scheduled polling', () async {
    final time = _ManualTime();
    final client = _client(time);
    final first = client.watch(
      _query(
        key: KacheKey('polling-dispose'),
        interval: const Duration(minutes: 5),
        fetch: (_) async => 1,
      ),
    );
    await first.load();
    final disposedTask = time.activeTasks.single;

    first.dispose();
    expect(disposedTask.isCancelled, isTrue);

    final second = client.watch(
      _query(
        key: KacheKey('polling-close'),
        interval: const Duration(minutes: 5),
        fetch: (_) async => 1,
      ),
    );
    await second.load();
    final closedTask = time.activeTasks.last;

    await client.close();
    expect(closedTask.isCancelled, isTrue);
  });
}

KacheClient _client(_ManualTime time) =>
    KacheClient(clock: () => time.now, scheduler: time.schedule);

KacheQuery<int> _query({
  required KacheKey key,
  required Duration interval,
  required KacheFetcher<int> fetch,
}) => KacheQuery<int>.memory(
  key: key,
  fetch: fetch,
  policy: KachePolicy.cacheFirst(
    freshFor: const Duration(hours: 1),
    refreshInterval: interval,
  ),
);

final class _ManualTime {
  DateTime now = DateTime.utc(2026, 10, 11);
  final List<_ManualTask> _tasks = <_ManualTask>[];

  List<_ManualTask> get activeTasks => _tasks
      .where((task) => !task.isCancelled && !task.didRun)
      .toList(growable: false);

  KacheScheduledTask schedule(Duration delay, void Function() callback) {
    final task = _ManualTask(now.add(delay), callback);
    _tasks.add(task);
    return task;
  }

  Future<void> elapse(Duration duration) async {
    final target = now.add(duration);
    while (true) {
      final due =
          activeTasks.where((task) => !task.dueAt.isAfter(target)).toList()
            ..sort((left, right) => left.dueAt.compareTo(right.dueAt));
      if (due.isEmpty) {
        break;
      }
      now = due.first.dueAt;
      due.first.run();
      await _flush();
    }
    now = target;
    await _flush();
  }
}

final class _ManualTask implements KacheScheduledTask {
  _ManualTask(this.dueAt, this._callback);

  final DateTime dueAt;
  final void Function() _callback;
  bool didRun = false;

  @override
  bool isCancelled = false;

  @override
  void cancel() => isCancelled = true;

  void run() {
    if (isCancelled || didRun) {
      return;
    }
    didRun = true;
    _callback();
  }
}

Future<void> _flush() async {
  for (var index = 0; index < 8; index++) {
    await Future<void>.value();
  }
}
