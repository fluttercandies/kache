import 'package:kache/kache.dart';
import 'package:test/test.dart';

import 'support/scripted_persistence.dart';

void main() {
  final now = DateTime.utc(2026, 10, 11);

  test('write failure does not block a later successful write', () async {
    final backend = ScriptedPersistence()
      ..writeError = persistenceException(
        operation: KachePersistenceOperation.write,
        stage: KachePersistenceStage.backend,
      );
    final binding = backend.bind<String>(fingerprint: 'value-v1');
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('write-recovery'),
        binding: binding,
        fetch: (_) async => 'network',
      ),
    );

    final failed = await resource.setData('first');
    backend.writeError = null;
    final recovered = await resource.setData('second');

    expect(failed.persistence?.phase, KachePersistencePhase.failed);
    expect(recovered.persistence?.phase, KachePersistencePhase.persisted);
    expect((backend.storedEntry as KachePersistedEntry<String>).data, 'second');
    resource.dispose();
    await client.close();
  });

  test('synchronous fetch throws retain the original stack', () async {
    final client = KacheClient(clock: () => now);
    final cause = StateError('sync fetch failure');
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('sync-fetch'),
        fetch: (_) => throw cause,
      ),
    );

    final snapshot = await resource.refresh();

    expect(snapshot.failure?.cause, same(cause));
    expect(
      snapshot.failure?.stackTrace.toString(),
      contains('failure_injection_test.dart'),
    );
    resource.dispose();
    await client.close();
  });

  test('delete failure is classified without restoring removed data', () async {
    final backend = ScriptedPersistence()
      ..deleteError = persistenceException(
        operation: KachePersistenceOperation.delete,
        stage: KachePersistenceStage.backend,
      );
    final binding = backend.bind<String>(fingerprint: 'value-v1');
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('delete-failure'),
        binding: binding,
        fetch: (_) async => 'network',
      ),
    );
    await resource.setData('value');

    final removed = await resource.remove();

    expect(removed.hasData, isFalse);
    expect(removed.persistence?.failure?.kind, KacheFailureKind.delete);
    resource.dispose();
    await client.close();
  });

  test('clear failure returns a global classified result', () async {
    final backend = _ClearFailingPersistence();
    final client = KacheClient(persistence: backend, clock: () => now);

    final result = await client.clear();

    expect(result.isSuccess, isFalse);
    expect(result.failures.single.kind, KacheFailureKind.clear);
    expect(result.failures.single.scope, KacheFailureScope.global);
    expect(result.failures.single.cause, same(backend.cause));
    await client.close();
  });

  test('namespace clear failure preserves namespace scope', () async {
    final backend = _ClearFailingPersistence();
    final client = KacheClient(persistence: backend, clock: () => now);
    final namespace = KacheNamespace('session');

    final result = await client.clearNamespace(namespace);

    expect(result.failures.single.scope, KacheFailureScope.namespace);
    expect(result.failures.single.namespace, namespace);
    await client.close();
  });
}

final class _ClearFailingPersistence implements KachePersistenceBackend {
  final StateError cause = StateError('clear failed');

  @override
  Future<void> clear() async => _fail(KachePersistenceOperation.clear);

  @override
  Future<void> clearNamespace({required KacheNamespace namespace}) async =>
      _fail(KachePersistenceOperation.clearNamespace);

  @override
  Future<void> close() async {}

  @override
  Future<void> delete({required KacheKey key}) async {}

  @override
  Future<KachePersistenceRead<T>?> read<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
  }) async => null;

  @override
  Future<void> write<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
    required KachePersistedEntry<T> entry,
  }) async {}

  Never _fail(KachePersistenceOperation operation) {
    throw KachePersistenceException(
      operation: operation,
      stage: KachePersistenceStage.backend,
      cause: cause,
      stackTrace: StackTrace.current,
    );
  }
}
