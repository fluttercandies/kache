import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 3, 4, 12);

  test('emits persisted data before a slow refresh completes', () async {
    final backend = MemoryKachePersistence();
    final binding = backend.bind<String>(fingerprint: 'profile-v1');
    final key = KacheKey('profile', [1]);
    await backend.write(
      key: key,
      binding: binding,
      entry: KachePersistedEntry<String>(
        data: 'cached',
        metadata: KachePersistedMetadata(
          fetchedAt: now.subtract(const Duration(days: 1)),
        ),
      ),
    );
    final refresh = Completer<String>();
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: key,
        binding: binding,
        fetch: (_) => refresh.future,
      ),
    );

    final cached = await resource.stream.firstWhere(
      (snapshot) => snapshot.hasData,
    );

    expect(cached.requireData, 'cached');
    expect(cached.source, KacheDataSource.persistence);
    expect(refresh.isCompleted, isFalse);

    final refreshedFuture = resource.stream.firstWhere(
      (snapshot) => snapshot.dataOrNull == 'fresh',
    );
    refresh.complete('fresh');
    final refreshed = await refreshedFuture;

    expect(refreshed.source, KacheDataSource.fetch);
    expect(refreshed.failure, isNull);
    expect(
      (await backend.read(key: key, binding: binding))?.entry.data,
      'fresh',
    );

    resource.dispose();
    await client.close();
  });

  test('retains old data and exposes a refresh failure', () async {
    final client = KacheClient(clock: () => now);
    var fetchCount = 0;
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('profile', [2]),
        fetch: (_) async {
          fetchCount += 1;
          if (fetchCount == 1) {
            return 'cached-in-memory';
          }
          throw StateError('offline');
        },
      ),
    );
    await resource.load();

    final failedRefresh = await resource.refresh();

    expect(failedRefresh.phase, KachePhase.ready);
    expect(failedRefresh.requireData, 'cached-in-memory');
    expect(failedRefresh.failure?.kind, KacheFailureKind.fetch);
    expect(failedRefresh.isRefreshing, isFalse);

    resource.dispose();
    await client.close();
  });

  test('clears old data on refresh failure when configured', () async {
    final client = KacheClient(clock: () => now);
    var fetchCount = 0;
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('profile', [3]),
        policy: KachePolicy.staleWhileRevalidate(retainDataOnError: false),
        fetch: (_) async {
          fetchCount += 1;
          if (fetchCount == 1) {
            return 'temporary';
          }
          throw StateError('offline');
        },
      ),
    );
    await resource.load();

    final failedRefresh = await resource.refresh();

    expect(failedRefresh.phase, KachePhase.failure);
    expect(failedRefresh.hasData, isFalse);
    expect(failedRefresh.failure?.kind, KacheFailureKind.fetch);

    resource.dispose();
    await client.close();
  });

  test('reports a no-cache fetch failure as terminal failure', () async {
    final client = KacheClient(clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('profile', [4]),
        fetch: (_) async => throw StateError('offline'),
      ),
    );

    final snapshot = await resource.load();

    expect(snapshot.phase, KachePhase.failure);
    expect(snapshot.hasData, isFalse);
    expect(snapshot.failure?.kind, KacheFailureKind.fetch);
    expect(snapshot.failure?.cause, isA<StateError>());

    resource.dispose();
    await client.close();
  });

  test('preserves a fetched null as present data', () async {
    final client = KacheClient(clock: () => now);
    final resource = client.watch(
      KacheQuery<String?>.memory(
        key: KacheKey('nullable'),
        fetch: (_) async => null,
      ),
    );

    final snapshot = await resource.load();

    expect(snapshot.hasData, isTrue);
    expect(snapshot.requireData, isNull);

    resource.dispose();
    await client.close();
  });
}
