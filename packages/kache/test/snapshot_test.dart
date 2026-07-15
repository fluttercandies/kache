import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  final key = KacheKey('profiles', [7]);
  final fetchedAt = DateTime.utc(2026, 2, 3, 4, 5);

  group('KacheSnapshot empty states', () {
    test('idle has no data or data metadata', () {
      final snapshot = KacheSnapshot<String>.idle();

      expect(snapshot.phase, KachePhase.idle);
      expect(snapshot.hasData, isFalse);
      expect(snapshot.dataOrNull, isNull);
      expect(snapshot.freshness, isNull);
      expect(snapshot.source, isNull);
      expect(snapshot.fetchedAt, isNull);
      expect(snapshot.failure, isNull);
      expect(snapshot.isRefreshing, isFalse);
      expect(() => snapshot.requireData, throwsStateError);
    });

    test('loading has no data and retains persistence state', () {
      final snapshot = KacheSnapshot<String>.loading(
        revision: 2,
        persistence: const KachePersistenceState.reading(),
      );

      expect(snapshot.phase, KachePhase.loading);
      expect(snapshot.hasData, isFalse);
      expect(snapshot.revision, 2);
      expect(snapshot.persistence?.phase, KachePersistencePhase.reading);
    });

    test('failed requires failure and has no data', () {
      final failure = _fetchFailure(key);
      final snapshot = KacheSnapshot<String>.failed(
        failure: failure,
        revision: 3,
      );

      expect(snapshot.phase, KachePhase.failure);
      expect(snapshot.hasData, isFalse);
      expect(snapshot.failure, same(failure));
      expect(snapshot.isRefreshing, isFalse);
    });
  });

  group('KacheSnapshot data states', () {
    test('ready exposes data and normalized fetch metadata', () {
      final localFetchedAt = fetchedAt.toLocal();
      final snapshot = KacheSnapshot<String>.ready(
        data: 'Ada',
        freshness: KacheFreshness.fresh,
        source: KacheDataSource.persistence,
        fetchedAt: localFetchedAt,
        revision: 4,
        persistence: const KachePersistenceState.persisted(),
      );

      expect(snapshot.phase, KachePhase.ready);
      expect(snapshot.hasData, isTrue);
      expect(snapshot.dataOrNull, 'Ada');
      expect(snapshot.requireData, 'Ada');
      expect(snapshot.fetchedAt, fetchedAt);
      expect(snapshot.fetchedAt?.isUtc, isTrue);
      expect(snapshot.persistence?.phase, KachePersistencePhase.persisted);
    });

    test('distinguishes cached null from missing data', () {
      final snapshot = KacheSnapshot<String?>.ready(
        data: null,
        freshness: KacheFreshness.fresh,
        source: KacheDataSource.fetch,
        fetchedAt: fetchedAt,
      );

      expect(snapshot.hasData, isTrue);
      expect(snapshot.dataOrNull, isNull);
      expect(snapshot.requireData, isNull);
    });

    test('represents old data refreshing without returning to loading', () {
      final snapshot = KacheSnapshot<String>.ready(
        data: 'cached',
        freshness: KacheFreshness.stale,
        source: KacheDataSource.persistence,
        fetchedAt: fetchedAt,
        isRefreshing: true,
      );

      expect(snapshot.phase, KachePhase.ready);
      expect(snapshot.isRefreshing, isTrue);
      expect(snapshot.hasData, isTrue);
    });

    test('represents old data together with refresh failure', () {
      final failure = _fetchFailure(key);
      final snapshot = KacheSnapshot<String>.ready(
        data: 'cached',
        freshness: KacheFreshness.stale,
        source: KacheDataSource.persistence,
        fetchedAt: fetchedAt,
        failure: failure,
      );

      expect(snapshot.phase, KachePhase.ready);
      expect(snapshot.hasData, isTrue);
      expect(snapshot.failure, same(failure));
      expect(snapshot.isRefreshing, isFalse);
    });
  });

  group('KacheSnapshot convenience state', () {
    test('derives phase and freshness flags', () {
      final idle = KacheSnapshot<String>.idle();
      final loading = KacheSnapshot<String>.loading();
      final ready = KacheSnapshot<String>.ready(
        data: 'cached',
        freshness: KacheFreshness.stale,
        source: KacheDataSource.persistence,
        fetchedAt: fetchedAt,
      );
      final failed = KacheSnapshot<String>.failed(failure: _fetchFailure(key));

      expect(idle.isLoading, isFalse);
      expect(loading.isLoading, isTrue);
      expect(ready.isReady, isTrue);
      expect(ready.isStale, isTrue);
      expect(failed.isFailed, isTrue);
      expect(failed.hasFailure, isTrue);
    });

    test('hasFailure includes orthogonal persistence failures', () {
      final snapshot = KacheSnapshot<String>.ready(
        data: 'fresh',
        freshness: KacheFreshness.fresh,
        source: KacheDataSource.fetch,
        fetchedAt: fetchedAt,
        persistence: KachePersistenceState.failed(_persistenceFailure(key)),
      );

      expect(snapshot.isReady, isTrue);
      expect(snapshot.isStale, isFalse);
      expect(snapshot.isFailed, isFalse);
      expect(snapshot.hasFailure, isTrue);
    });
  });

  group('KacheSnapshot branching', () {
    String render(KacheSnapshot<String> snapshot, {bool skip = true}) =>
        snapshot.when(
          skipLoadingOnRefresh: skip,
          idle: () => 'idle',
          loading: () => 'loading',
          ready: (data) => 'ready:$data',
          refreshError: (data, failure) =>
              'refresh-error:$data:${failure.kind.name}',
          failed: (failure) => 'failed:${failure.kind.name}',
        );

    test('when dispatches every primary phase', () {
      expect(render(KacheSnapshot<String>.idle()), 'idle');
      expect(render(KacheSnapshot<String>.loading()), 'loading');
      expect(
        render(
          KacheSnapshot<String>.ready(
            data: 'Ada',
            freshness: KacheFreshness.fresh,
            source: KacheDataSource.fetch,
            fetchedAt: fetchedAt,
          ),
        ),
        'ready:Ada',
      );
      expect(
        render(KacheSnapshot<String>.failed(failure: _fetchFailure(key))),
        'failed:fetch',
      );
    });

    test('when keeps cached data visible while refreshing by default', () {
      final snapshot = KacheSnapshot<String>.ready(
        data: 'cached',
        freshness: KacheFreshness.stale,
        source: KacheDataSource.persistence,
        fetchedAt: fetchedAt,
        isRefreshing: true,
      );

      expect(render(snapshot), 'ready:cached');
      expect(render(snapshot, skip: false), 'loading');
    });

    test('when never hides a refresh error behind ready data', () {
      final snapshot = KacheSnapshot<String>.ready(
        data: 'cached',
        freshness: KacheFreshness.stale,
        source: KacheDataSource.persistence,
        fetchedAt: fetchedAt,
        failure: _fetchFailure(key),
      );

      expect(render(snapshot), 'refresh-error:cached:fetch');
    });

    test('when treats cached nullable null as ready data', () {
      final snapshot = KacheSnapshot<String?>.ready(
        data: null,
        freshness: KacheFreshness.fresh,
        source: KacheDataSource.fetch,
        fetchedAt: fetchedAt,
      );

      expect(
        snapshot.when(
          idle: () => 'idle',
          loading: () => 'loading',
          ready: (data) => data ?? 'cached-null',
          refreshError: (_, __) => 'refresh-error',
          failed: (_) => 'failed',
        ),
        'cached-null',
      );
    });

    test('maybeWhen invokes a supplied branch or the fallback', () {
      final ready = KacheSnapshot<String>.ready(
        data: 'Ada',
        freshness: KacheFreshness.fresh,
        source: KacheDataSource.fetch,
        fetchedAt: fetchedAt,
      );

      expect(
        ready.maybeWhen(ready: (data) => data, orElse: () => 'fallback'),
        'Ada',
      );
      expect(
        KacheSnapshot<String>.idle().maybeWhen(
          ready: (data) => data,
          orElse: () => 'fallback',
        ),
        'fallback',
      );
    });
  });

  group('KacheSnapshot mapData', () {
    test('converts data and preserves every orthogonal state field', () {
      final failure = _fetchFailure(key);
      final persistence = KachePersistenceState.failed(
        _persistenceFailure(key),
      );
      final snapshot = KacheSnapshot<String>.ready(
        data: 'Ada',
        freshness: KacheFreshness.stale,
        source: KacheDataSource.persistence,
        fetchedAt: fetchedAt,
        isRefreshing: true,
        failure: failure,
        revision: 8,
        persistence: persistence,
      );

      final mapped = snapshot.mapData((data) => data.length);

      expect(mapped.requireData, 3);
      expect(mapped.phase, snapshot.phase);
      expect(mapped.freshness, snapshot.freshness);
      expect(mapped.source, snapshot.source);
      expect(mapped.fetchedAt, snapshot.fetchedAt);
      expect(mapped.isRefreshing, snapshot.isRefreshing);
      expect(mapped.failure, same(failure));
      expect(mapped.revision, snapshot.revision);
      expect(mapped.persistence, same(persistence));
    });

    test('maps cached nullable null instead of treating it as absent', () {
      var calls = 0;
      final snapshot = KacheSnapshot<String?>.ready(
        data: null,
        freshness: KacheFreshness.fresh,
        source: KacheDataSource.fetch,
        fetchedAt: fetchedAt,
      );

      final mapped = snapshot.mapData((data) {
        calls += 1;
        return data ?? 'null';
      });

      expect(calls, 1);
      expect(mapped.requireData, 'null');
    });

    test('preserves empty states without invoking the converter', () {
      final failure = _fetchFailure(key);
      final snapshots = <KacheSnapshot<String>>[
        KacheSnapshot<String>.idle(revision: 1),
        KacheSnapshot<String>.loading(revision: 2),
        KacheSnapshot<String>.failed(failure: failure, revision: 3),
      ];

      for (final snapshot in snapshots) {
        final mapped = snapshot.mapData<int>(
          (_) => throw StateError('converter must not run'),
        );
        expect(mapped.phase, snapshot.phase);
        expect(mapped.revision, snapshot.revision);
        expect(mapped.failure, snapshot.failure);
      }
    });

    test('propagates conversion errors without fabricating a failure', () {
      final cause = StateError('conversion failed');
      final snapshot = KacheSnapshot<String>.ready(
        data: 'Ada',
        freshness: KacheFreshness.fresh,
        source: KacheDataSource.fetch,
        fetchedAt: fetchedAt,
      );

      expect(() => snapshot.mapData<int>((_) => throw cause), throwsA(cause));
    });
  });

  group('KachePersistenceState', () {
    test('failed retains the exact persistence failure', () {
      final failure = _persistenceFailure(key);
      final state = KachePersistenceState.failed(failure);

      expect(state.phase, KachePersistencePhase.failed);
      expect(state.failure, same(failure));
    });

    test('non-failed phases never expose a failure', () {
      const states = <KachePersistenceState>[
        KachePersistenceState.idle(),
        KachePersistenceState.reading(),
        KachePersistenceState.absent(),
        KachePersistenceState.writing(),
        KachePersistenceState.persisted(),
      ];

      for (final state in states) {
        expect(state.failure, isNull);
      }
    });
  });

  group('KacheSnapshot validation', () {
    test('rejects negative revisions', () {
      expect(
        () => KacheSnapshot<String>.idle(revision: -1),
        throwsArgumentError,
      );
      expect(
        () => KacheSnapshot<String>.ready(
          data: 'invalid',
          freshness: KacheFreshness.fresh,
          source: KacheDataSource.manual,
          fetchedAt: fetchedAt,
          revision: -1,
        ),
        throwsArgumentError,
      );
    });

    test('failure rendering never includes the key or cause payload', () {
      const secret = 'secret-payload';
      final failure = KacheFailure(
        kind: KacheFailureKind.fetch,
        key: KacheKey('private', [secret]),
        cause: StateError(secret),
        stackTrace: StackTrace.current,
      );

      expect(failure.toString(), isNot(contains(secret)));
      expect(failure.toString(), contains('fetch'));
    });
  });
}

KacheFailure _fetchFailure(KacheKey key) => KacheFailure(
      kind: KacheFailureKind.fetch,
      key: key,
      cause: StateError('offline'),
      stackTrace: StackTrace.current,
    );

KacheFailure _persistenceFailure(KacheKey key) => KacheFailure(
      kind: KacheFailureKind.persistenceRead,
      key: key,
      cause: StateError('read failed'),
      stackTrace: StackTrace.current,
      persistenceStage: KachePersistenceStage.backend,
    );
