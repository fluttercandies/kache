import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

import 'support/scripted_persistence.dart';

void main() {
  final now = DateTime.utc(2026, 7, 8);

  test(
    'prefetch loads data and peek reads active memory synchronously',
    () async {
      final client = KacheClient(clock: () => now);
      final query = KacheQuery<String>.memory(
        key: KacheKey('prefetch'),
        fetch: (_) async => 'prefetched',
      );

      final prefetched = await client.prefetch(query);
      final peeked = client.peek<String>(query.key);

      expect(prefetched.requireData, 'prefetched');
      expect(peeked?.requireData, 'prefetched');
      await client.close();
    },
  );

  test('peek never creates entries or performs I/O', () async {
    final client = KacheClient(clock: () => now);
    final key = KacheKey('missing-peek');

    expect(client.peek<String>(key), isNull);

    final resource = client.watch(
      KacheQuery<int>.memory(key: key, fetch: (_) async => 1),
    );
    expect(resource.snapshot.phase, KachePhase.idle);
    resource.dispose();
    await client.close();
  });

  test(
    'peek rejects an incompatible requested type without key leakage',
    () async {
      const secret = 'private-key-part';
      final client = KacheClient(clock: () => now);
      final key = KacheKey('private', [secret]);
      final resource = client.watch(
        KacheQuery<String>.memory(key: key, fetch: (_) async => 'value'),
      );

      Object? error;
      try {
        client.peek<int>(key);
      } on Object catch (caught) {
        error = caught;
      }

      expect(error, isA<KacheConfigurationException>());
      expect(error.toString(), isNot(contains(secret)));
      resource.dispose();
      await client.close();
    },
  );

  test('concurrent updateData calls do not lose updates', () async {
    final client = KacheClient(clock: () => now);
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('atomic-update'),
        fetch: (_) async => 0,
      ),
    );
    await resource.setData(0);

    final updates = List<Future<KacheSnapshot<int>>>.generate(
      100,
      (_) => resource.updateData((snapshot) => snapshot.requireData + 1),
    );
    await Future.wait(updates);

    expect(resource.snapshot.requireData, 100);
    resource.dispose();
    await client.close();
  });

  test('invalidate persists metadata and can skip refetch', () async {
    final backend = ScriptedPersistence();
    final binding = backend.bind<String>(fingerprint: 'value-v1');
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('invalidate'),
        binding: binding,
        fetch: (_) async => 'network',
      ),
    );
    await resource.setData('manual');

    final invalidated = await resource.invalidate(refetch: false);

    expect(invalidated.freshness, KacheFreshness.stale);
    expect(
      (backend.storedEntry as KachePersistedEntry<String>)
          .metadata
          .isInvalidated,
      isTrue,
    );
    resource.dispose();
    await client.close();
  });

  test('remove deletes persistence and does not refetch', () async {
    final backend = ScriptedPersistence();
    final binding = backend.bind<String>(fingerprint: 'value-v1');
    var fetchCount = 0;
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('remove'),
        binding: binding,
        fetch: (_) async {
          fetchCount += 1;
          return 'network';
        },
      ),
    );
    await resource.setData('manual');

    final removed = await resource.remove();

    expect(removed.phase, KachePhase.idle);
    expect(backend.storedEntry, isNull);
    expect(fetchCount, 0);
    resource.dispose();
    await client.close();
  });

  test(
    'snapshot throwIfFailed aggregates primary and persistence failures',
    () {
      final key = KacheKey('failures');
      final primary = KacheFailure(
        kind: KacheFailureKind.fetch,
        key: key,
        cause: StateError('offline'),
        stackTrace: StackTrace.current,
      );
      final persistence = KacheFailure(
        kind: KacheFailureKind.persistenceWrite,
        key: key,
        cause: StateError('disk'),
        stackTrace: StackTrace.current,
        persistenceStage: KachePersistenceStage.backend,
      );
      final snapshot = KacheSnapshot<String>.ready(
        data: 'cached',
        freshness: KacheFreshness.stale,
        source: KacheDataSource.manual,
        fetchedAt: now,
        failure: primary,
        persistence: KachePersistenceState.failed(persistence),
      );

      expect(
        snapshot.throwIfFailed,
        throwsA(
          isA<KacheCommandException>().having(
            (error) => error.failures,
            'failures',
            <KacheFailure>[primary, persistence],
          ),
        ),
      );
    },
  );

  test('clear result throwIfFailed exposes classified failures', () {
    final failure = KacheFailure(
      kind: KacheFailureKind.clear,
      cause: StateError('clear failed'),
      stackTrace: StackTrace.current,
      persistenceStage: KachePersistenceStage.backend,
    );
    final result = KacheClearResult(failures: <KacheFailure>[failure]);

    expect(result.isSuccess, isFalse);
    expect(result.throwIfFailed, throwsA(isA<KacheCommandException>()));
  });

  test('cache-only refresh reports fetchUnavailable', () async {
    final client = KacheClient(clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('cache-only-refresh'),
        policy: KachePolicy.cacheOnly(),
      ),
    );

    final snapshot = await resource.refresh();

    expect(snapshot.failure?.kind, KacheFailureKind.fetchUnavailable);
    expect(snapshot.throwIfFailed, throwsA(isA<KacheCommandException>()));
    resource.dispose();
    await client.close();
  });
}
