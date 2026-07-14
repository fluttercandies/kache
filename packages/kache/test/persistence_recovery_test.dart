import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

import 'support/scripted_persistence.dart';

void main() {
  final now = DateTime.utc(2026, 5, 6, 12);

  test('treats a corrupt persisted value as a miss and repairs it', () async {
    final backend = ScriptedPersistence()
      ..readError = persistenceException(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.decode,
      );
    final binding = backend.bind<String>(fingerprint: 'profile-v1');
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('profile'),
        binding: binding,
        fetch: (_) async => 'fresh',
      ),
    );

    final snapshot = await resource.load();

    expect(snapshot.requireData, 'fresh');
    expect(backend.readCount, 1);
    expect(backend.deleteCount, 1);
    expect(backend.writeCount, 1);
    expect((backend.storedEntry as KachePersistedEntry<String>).data, 'fresh');

    resource.dispose();
    await client.close();
  });

  test('publishes migrated data before lazy maintenance completes', () async {
    final maintenance = Completer<void>();
    final backend = ScriptedPersistence()
      ..storedEntry = KachePersistedEntry<String>(
        data: 'migrated',
        metadata: KachePersistedMetadata(fetchedAt: now),
      )
      ..maintenance = () => maintenance.future;
    final binding = backend.bind<String>(fingerprint: 'profile-v2');
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('profile'),
        binding: binding,
        policy: KachePolicy.cacheFirst(freshFor: const Duration(hours: 1)),
        fetch: (_) async => 'network',
      ),
    );

    final visible = await resource.stream.firstWhere(
      (snapshot) => snapshot.hasData,
    );

    expect(visible.requireData, 'migrated');
    expect(maintenance.isCompleted, isFalse);

    final persistedFuture = resource.stream.firstWhere(
      (snapshot) =>
          snapshot.persistence?.phase == KachePersistencePhase.persisted,
    );
    maintenance.complete();
    final persisted = await persistedFuture;

    expect(persisted.requireData, 'migrated');
    resource.dispose();
    await client.close();
  });

  test('retains migrated data when lazy maintenance fails', () async {
    final backend = ScriptedPersistence()
      ..storedEntry = KachePersistedEntry<String>(
        data: 'migrated',
        metadata: KachePersistedMetadata(fetchedAt: now),
      )
      ..maintenance = () => throw persistenceException(
            operation: KachePersistenceOperation.read,
            stage: KachePersistenceStage.migration,
          );
    final binding = backend.bind<String>(fingerprint: 'profile-v2');
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('profile'),
        binding: binding,
        policy: KachePolicy.cacheFirst(freshFor: const Duration(hours: 1)),
        fetch: (_) async => 'network',
      ),
    );

    final snapshot = await resource.load();

    expect(snapshot.requireData, 'migrated');
    expect(snapshot.persistence?.phase, KachePersistencePhase.failed);
    expect(
      snapshot.persistence?.failure?.kind,
      KacheFailureKind.persistenceRead,
    );

    resource.dispose();
    await client.close();
  });

  test('deletes hard-expired data before fetching replacement', () async {
    final backend = ScriptedPersistence()
      ..storedEntry = KachePersistedEntry<String>(
        data: 'expired',
        metadata: KachePersistedMetadata(
          fetchedAt: now.subtract(const Duration(hours: 2)),
        ),
      );
    final binding = backend.bind<String>(fingerprint: 'profile-v1');
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('profile'),
        binding: binding,
        policy: KachePolicy.cacheFirst(
          freshFor: const Duration(minutes: 10),
          expireAfter: const Duration(hours: 1),
        ),
        fetch: (_) async => 'fresh',
      ),
    );

    final snapshot = await resource.load();

    expect(snapshot.requireData, 'fresh');
    expect(backend.deleteCount, 1);
    expect(backend.writeCount, 1);

    resource.dispose();
    await client.close();
  });

  test('cache-only reports cache miss after corrupt data recovery', () async {
    final backend = ScriptedPersistence()
      ..readError = persistenceException(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.decode,
      );
    final binding = backend.bind<String>(fingerprint: 'profile-v1');
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('profile'),
        binding: binding,
        policy: KachePolicy.cacheOnly(),
      ),
    );

    final snapshot = await resource.load();

    expect(snapshot.phase, KachePhase.failure);
    expect(snapshot.failure?.kind, KacheFailureKind.cacheMiss);
    expect(backend.deleteCount, 1);

    resource.dispose();
    await client.close();
  });
}
