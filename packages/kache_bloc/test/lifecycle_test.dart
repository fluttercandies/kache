import 'dart:async';

import 'package:kache/kache.dart';
import 'package:kache_bloc/kache_bloc.dart';
import 'package:test/test.dart';

void main() {
  test(
    'close is idempotent and pending fetch cannot emit late state',
    () async {
      final scheduler = _ManualScheduler();
      final client = KacheClient(scheduler: scheduler.call);
      final fetch = Completer<int>();
      final cubit = KacheCubit<int>(
        client: client,
        query: KacheQuery.memory(
          key: KacheKey('bloc-lifecycle', <Object?>['pending']),
          fetch: (context) => fetch.future,
          policy: KachePolicy.staleWhileRevalidate(gcAfter: Duration.zero),
        ),
      );
      await pumpEventQueue();
      expect(cubit.state.phase, KachePhase.loading);

      final closing = cubit.close();
      expect(cubit.close(), same(closing));
      await closing;

      expect(cubit.isClosed, isTrue);
      expect(scheduler.activeTasks, hasLength(1));
      expect(
        cubit.refresh,
        throwsA(
          isA<KacheLifecycleException>().having(
            (error) => error.code,
            'code',
            'cubit_closed',
          ),
        ),
      );

      fetch.complete(42);
      await fetch.future;
      await pumpEventQueue();
      await client.close();
    },
  );

  test('binding close releases an unattached resource', () async {
    final scheduler = _ManualScheduler();
    final client = KacheClient(scheduler: scheduler.call);
    final binding = KacheBlocBinding<int>(
      client: client,
      query: KacheQuery.memory(
        key: KacheKey('bloc-lifecycle', <Object?>['unattached']),
        policy: KachePolicy.cacheOnly(gcAfter: Duration.zero),
      ),
    );

    await binding.close();

    expect(binding.isClosed, isTrue);
    expect(scheduler.activeTasks, hasLength(1));
    await client.close();
  });
}

final class _ManualScheduler {
  final List<_ManualTask> _tasks = <_ManualTask>[];

  Iterable<_ManualTask> get activeTasks =>
      _tasks.where((task) => !task.isCancelled);

  KacheScheduledTask call(Duration delay, void Function() callback) {
    final task = _ManualTask();
    _tasks.add(task);
    return task;
  }
}

final class _ManualTask implements KacheScheduledTask {
  bool _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  void cancel() => _isCancelled = true;
}
