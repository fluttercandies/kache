import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  test('uses the maximum gcAfter seen during an entry lifetime', () async {
    final scheduler = _ManualScheduler();
    final client = KacheClient(scheduler: scheduler.schedule);
    final key = KacheKey('gc-maximum');
    final short = client.watch(
      KacheQuery<String>.memory(
        key: key,
        policy: KachePolicy.cacheFirst(
          freshFor: const Duration(minutes: 1),
          gcAfter: const Duration(seconds: 10),
        ),
        fetch: (_) async => 'short',
      ),
    );
    final long = client.watch(
      KacheQuery<String>.memory(
        key: key,
        policy: KachePolicy.cacheFirst(
          freshFor: const Duration(minutes: 1),
          gcAfter: const Duration(minutes: 5),
        ),
        fetch: (_) async => 'long',
      ),
    );

    long.dispose();
    short.dispose();

    expect(scheduler.pending.single.delay, const Duration(minutes: 5));
    expect(
      () =>
          client.watch(KacheQuery<int>.memory(key: key, fetch: (_) async => 1)),
      throwsA(isA<KacheConfigurationException>()),
    );

    scheduler.pending.single.run();

    final replacement = client.watch(
      KacheQuery<int>.memory(key: key, fetch: (_) async => 1),
    );
    replacement.dispose();
    await client.close();
  });

  test('a new reference cancels pending garbage collection', () async {
    final scheduler = _ManualScheduler();
    final client = KacheClient(scheduler: scheduler.schedule);
    final key = KacheKey('gc-cancel');
    final query = KacheQuery<String>.memory(
      key: key,
      policy: KachePolicy.cacheFirst(
        freshFor: const Duration(minutes: 1),
        gcAfter: const Duration(minutes: 1),
      ),
      fetch: (_) async => 'value',
    );
    final first = client.watch(query)..dispose();
    expect(first.isDisposed, isTrue);
    final firstTask = scheduler.pending.single;

    final second = client.watch(query);

    expect(firstTask.isCancelled, isTrue);
    second.dispose();
    expect(scheduler.pending.where((task) => !task.isCancelled), hasLength(1));
    await client.close();
  });

  test('zero references do not cancel an in-flight fetch', () async {
    final scheduler = _ManualScheduler();
    final fetch = Completer<String>();
    final client = KacheClient(scheduler: scheduler.schedule);
    final key = KacheKey('gc-in-flight');
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: key,
        policy: KachePolicy.cacheFirst(
          freshFor: const Duration(minutes: 1),
          gcAfter: Duration.zero,
        ),
        fetch: (_) => fetch.future,
      ),
    );
    final refresh = resource.refresh();
    resource.dispose();
    scheduler.pending.single.run();

    expect(fetch.isCompleted, isFalse);
    fetch.complete('completed');
    await refresh;

    final replacement = client.watch(
      KacheQuery<int>.memory(key: key, fetch: (_) async => 1),
    );
    replacement.dispose();
    await client.close();
  });

  test('closed clients reject new handles and resource commands', () async {
    final client = KacheClient();
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('closed-client'),
        fetch: (_) async => 1,
      ),
    );

    await client.close();

    expect(resource.isDisposed, isTrue);
    expect(
      () => client.watch(
        KacheQuery<int>.memory(key: KacheKey('new'), fetch: (_) async => 1),
      ),
      throwsA(isA<KacheLifecycleException>()),
    );
    expect(() => resource.refresh(), throwsA(isA<KacheLifecycleException>()));
  });
}

final class _ManualScheduler {
  final List<_ManualTask> pending = <_ManualTask>[];

  KacheScheduledTask schedule(Duration delay, void Function() callback) {
    final task = _ManualTask(delay, callback);
    pending.add(task);
    return task;
  }
}

final class _ManualTask implements KacheScheduledTask {
  _ManualTask(this.delay, this._callback);

  final Duration delay;
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
