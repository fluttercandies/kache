import 'package:kache/kache.dart';
import 'package:test/test.dart';

import 'support/scripted_persistence.dart';

void main() {
  final now = DateTime.utc(2026, 11, 12);

  test('preserves a correctly classified persistence failure', () async {
    final backend = ScriptedPersistence();
    final failure = persistenceException(
      operation: KachePersistenceOperation.read,
      stage: KachePersistenceStage.decode,
    );
    backend.readError = failure;
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(_query(backend, 'matching-read'));

    final snapshot = await resource.load();

    expect(snapshot.persistence?.failure?.cause, same(failure.cause));
    expect(
      snapshot.persistence?.failure?.stackTrace,
      same(failure.stackTrace),
    );
    expect(
      snapshot.persistence?.failure?.persistenceStage,
      KachePersistenceStage.decode,
    );
    resource.dispose();
    await client.close();
  });

  test('does not trust a mismatched read operation', () async {
    final backend = ScriptedPersistence();
    final mismatch = _mismatch(KachePersistenceOperation.write);
    backend.readError = mismatch;
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(_query(backend, 'mismatched-read'));

    final snapshot = await resource.load();

    _expectContractFailure(snapshot.persistence?.failure, mismatch);
    resource.dispose();
    await client.close();
  });

  test('does not trust a mismatched write operation', () async {
    final backend = ScriptedPersistence();
    final mismatch = _mismatch(KachePersistenceOperation.read);
    backend.writeError = mismatch;
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(_query(backend, 'mismatched-write'));

    final snapshot = await resource.setData('value');

    _expectContractFailure(snapshot.persistence?.failure, mismatch);
    resource.dispose();
    await client.close();
  });

  test('does not trust a mismatched delete operation', () async {
    final backend = ScriptedPersistence();
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(_query(backend, 'mismatched-delete'));
    await resource.setData('value');
    final mismatch = _mismatch(KachePersistenceOperation.write);
    backend.deleteError = mismatch;

    final snapshot = await resource.remove();

    _expectContractFailure(snapshot.persistence?.failure, mismatch);
    resource.dispose();
    await client.close();
  });

  for (final namespace in <KacheNamespace?>[
    null,
    KacheNamespace('session'),
  ]) {
    final label = namespace == null ? 'clear' : 'namespace clear';
    test('does not trust a mismatched $label operation', () async {
      final backend = ScriptedPersistence();
      final mismatch = _mismatch(KachePersistenceOperation.read);
      backend.onClear = () => throw mismatch;
      final client = KacheClient(persistence: backend, clock: () => now);

      final result = namespace == null
          ? await client.clear()
          : await client.clearNamespace(namespace);

      _expectContractFailure(result.failures.single, mismatch);
      await client.close();
    });
  }

  test('normalizes a mismatched owned-backend close operation', () async {
    final backend = ScriptedPersistence();
    final mismatch = _mismatch(KachePersistenceOperation.read);
    backend.onClose = () => throw mismatch;
    final client = KacheClient(
      persistence: backend,
      persistenceOwnership: KachePersistenceOwnership.owned,
      clock: () => now,
    );

    await expectLater(
      client.close(),
      throwsA(
        isA<KachePersistenceException>()
            .having(
              (error) => error.operation,
              'operation',
              KachePersistenceOperation.close,
            )
            .having(
              (error) => error.stage,
              'stage',
              KachePersistenceStage.backend,
            )
            .having((error) => error.cause, 'cause', same(mismatch)),
      ),
    );
  });
}

KacheQuery<String> _query(ScriptedPersistence backend, String id) =>
    KacheQuery<String>.persisted(
      key: KacheKey('persistence-contract', <Object?>[id]),
      binding: backend.bind<String>(fingerprint: 'string-v1'),
      policy: KachePolicy.cacheOnly(),
    );

KachePersistenceException _mismatch(KachePersistenceOperation operation) =>
    KachePersistenceException(
      operation: operation,
      stage: KachePersistenceStage.backend,
      cause: StateError('mismatched persistence operation'),
      stackTrace: StackTrace.current,
    );

void _expectContractFailure(
  KacheFailure? failure,
  KachePersistenceException mismatch,
) {
  expect(failure, isNotNull);
  expect(failure?.cause, same(mismatch));
  expect(failure?.persistenceStage, KachePersistenceStage.backend);
  expect(failure?.stackTrace.toString(), isNotEmpty);
}
