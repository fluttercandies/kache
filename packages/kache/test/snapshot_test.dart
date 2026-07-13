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
