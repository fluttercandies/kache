import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kache/kache.dart';

typedef AdapterHarnessFactoryCallback =
    Future<AdapterContractHarness> Function(
      WidgetTester tester,
      KacheClient client,
      KacheQuery<int> query,
    );

final class AdapterHarnessFactory {
  const AdapterHarnessFactory({required this.name, required this.create});

  final String name;
  final AdapterHarnessFactoryCallback create;
}

abstract interface class AdapterContractHarness {
  KacheSnapshot<int> get snapshot;

  Future<void> settle();

  Future<KacheSnapshot<int>> refresh();

  Future<KacheSnapshot<int>> invalidate({required bool refetch});

  Future<void> replaceQuery(KacheQuery<int> query);

  Future<void> resume();

  Future<void> dispose();
}

void runAdapterContract(List<AdapterHarnessFactory> factories) {
  for (final factory in factories) {
    group(factory.name, () {
      testWidgets('shows persisted data before background refresh', (
        tester,
      ) async {
        final backend = MemoryKachePersistence();
        final binding = backend.bind<int>(fingerprint: 'adapter-int-v1');
        final key = KacheKey('adapter-contract', <Object?>['cached-first']);
        await backend.write<int>(
          key: key,
          binding: binding,
          entry: KachePersistedEntry<int>(
            data: 1,
            metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2025)),
          ),
        );
        final network = Completer<int>();
        final client = KacheClient(persistence: backend);
        final harness = await factory.create(
          tester,
          client,
          KacheQuery.persisted(
            key: key,
            binding: binding,
            fetch: (context) => network.future,
          ),
        );

        try {
          await harness.settle();
          expect(harness.snapshot.phase, KachePhase.ready);
          expect(harness.snapshot.requireData, 1);
          expect(harness.snapshot.source, KacheDataSource.persistence);
          expect(harness.snapshot.isRefreshing, isTrue);

          network.complete(2);
          await network.future;
          await harness.settle();

          expect(harness.snapshot.phase, KachePhase.ready);
          expect(harness.snapshot.requireData, 2);
          expect(harness.snapshot.source, KacheDataSource.fetch);
          expect(harness.snapshot.isRefreshing, isFalse);
        } finally {
          if (!network.isCompleted) {
            network.complete(2);
            await network.future;
            await harness.settle();
          }
          await harness.dispose();
          await client.close();
          await backend.close();
        }
      });

      testWidgets('retains old data when refresh fails', (tester) async {
        var fetchCount = 0;
        final client = KacheClient();
        final harness = await factory.create(
          tester,
          client,
          KacheQuery.memory(
            key: KacheKey('adapter-contract', <Object?>['old-data-error']),
            fetch: (context) async {
              fetchCount += 1;
              if (fetchCount == 1) {
                return 1;
              }
              throw StateError('offline');
            },
          ),
        );

        try {
          await harness.settle();
          expect(harness.snapshot.requireData, 1);

          final refreshed = await harness.refresh();
          await harness.settle();

          expect(refreshed.phase, KachePhase.ready);
          expect(refreshed.requireData, 1);
          expect(refreshed.failure?.kind, KacheFailureKind.fetch);
          expect(harness.snapshot.requireData, 1);
          expect(harness.snapshot.failure?.kind, KacheFailureKind.fetch);
        } finally {
          await harness.dispose();
          await client.close();
        }
      });

      testWidgets('reports a fetch failure when no cache exists', (
        tester,
      ) async {
        final client = KacheClient();
        final harness = await factory.create(
          tester,
          client,
          KacheQuery.memory(
            key: KacheKey('adapter-contract', <Object?>['empty-error']),
            fetch: (context) async => throw StateError('offline'),
          ),
        );

        try {
          await harness.settle();

          expect(harness.snapshot.phase, KachePhase.failure);
          expect(harness.snapshot.hasData, isFalse);
          expect(harness.snapshot.failure?.kind, KacheFailureKind.fetch);
        } finally {
          await harness.dispose();
          await client.close();
        }
      });

      testWidgets('forces a refresh through the adapter command', (
        tester,
      ) async {
        var fetchCount = 0;
        final client = KacheClient();
        final harness = await factory.create(
          tester,
          client,
          KacheQuery.memory(
            key: KacheKey('adapter-contract', <Object?>['force-refresh']),
            fetch: (context) async => ++fetchCount,
          ),
        );

        try {
          await harness.settle();
          expect(harness.snapshot.requireData, 1);

          final refreshed = await harness.refresh();
          await harness.settle();

          expect(refreshed.requireData, 2);
          expect(harness.snapshot.requireData, 2);
          expect(fetchCount, 2);
        } finally {
          await harness.dispose();
          await client.close();
        }
      });

      testWidgets('invalidates data without discarding it', (tester) async {
        final client = KacheClient();
        final harness = await factory.create(
          tester,
          client,
          KacheQuery.memory(
            key: KacheKey('adapter-contract', <Object?>['invalidate']),
            fetch: (context) async => 1,
          ),
        );

        try {
          await harness.settle();

          final invalidated = await harness.invalidate(refetch: false);
          await harness.settle();

          expect(invalidated.requireData, 1);
          expect(invalidated.freshness, KacheFreshness.stale);
          expect(harness.snapshot.requireData, 1);
          expect(harness.snapshot.freshness, KacheFreshness.stale);
        } finally {
          await harness.dispose();
          await client.close();
        }
      });

      testWidgets('switches query parameters without retaining old state', (
        tester,
      ) async {
        final client = KacheClient();
        final harness = await factory.create(
          tester,
          client,
          KacheQuery.memory(
            key: KacheKey('adapter-contract', <Object?>['parameter', 1]),
            fetch: (context) async => 1,
          ),
        );

        try {
          await harness.settle();
          expect(harness.snapshot.requireData, 1);

          await harness.replaceQuery(
            KacheQuery.memory(
              key: KacheKey('adapter-contract', <Object?>['parameter', 2]),
              fetch: (context) async => 2,
            ),
          );
          await harness.settle();

          expect(harness.snapshot.phase, KachePhase.ready);
          expect(harness.snapshot.requireData, 2);
          expect(harness.snapshot.failure, isNull);
        } finally {
          await harness.dispose();
          await client.close();
        }
      });

      testWidgets('ignores pending fetch completion after disposal', (
        tester,
      ) async {
        final scheduler = _ManualScheduler();
        final client = KacheClient(scheduler: scheduler.call);
        final fetch = Completer<int>();
        final key = KacheKey('adapter-contract', <Object?>['disposed-pending']);
        final harness = await factory.create(
          tester,
          client,
          KacheQuery.memory(
            key: key,
            fetch: (context) => fetch.future,
            policy: KachePolicy.staleWhileRevalidate(gcAfter: Duration.zero),
          ),
        );
        await harness.settle();

        await harness.dispose();
        scheduler.runAll();
        fetch.complete(1);
        await fetch.future;
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(client.peek<int>(key), isNull);
        await client.close();
      });

      testWidgets('revalidates active data when the host resumes', (
        tester,
      ) async {
        var fetchCount = 0;
        final client = KacheClient();
        final harness = await factory.create(
          tester,
          client,
          KacheQuery.memory(
            key: KacheKey('adapter-contract', <Object?>['resume']),
            fetch: (context) async => ++fetchCount,
            policy: KachePolicy.cacheFirst(
              freshFor: const Duration(hours: 1),
              refreshOnResume: KacheRevalidation.always,
            ),
          ),
        );

        try {
          await harness.settle();
          expect(harness.snapshot.requireData, 1);

          await harness.resume();
          await harness.settle();

          expect(fetchCount, 2);
          expect(harness.snapshot.requireData, 2);
        } finally {
          await harness.dispose();
          await client.close();
        }
      });
    });
  }
}

final class _ManualScheduler {
  final List<_ManualTask> _tasks = <_ManualTask>[];

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
