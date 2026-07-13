import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

/// Creates bindings and exposes one real backend to the central aggregator.
abstract interface class PersistenceContractHarness {
  /// The backend instance under test.
  KachePersistenceBackend get backend;

  /// Creates a binding owned by [backend].
  KachePersistenceBinding<T> bind<T>({required String fingerprint});

  /// Releases backend and test resources after a contract scenario.
  FutureOr<void> dispose();
}

/// A factory that creates an isolated persistence contract harness.
typedef PersistenceContractHarnessFactory =
    FutureOr<PersistenceContractHarness> Function();

/// Registers the reusable persistence behavior matrix for one backend.
///
/// Each scenario uses a fresh harness and exercises the real backend rather
/// than a mocking framework. Only the `tool/contract_tests` aggregator
/// registers backend harnesses. Adapter packages do not import this test
/// package; the dependency direction remains from the aggregator to adapters.
void runPersistenceContract({
  required String backendName,
  required PersistenceContractHarnessFactory createHarness,
}) {
  group('$backendName persistence contract', () {
    test('returns null for a read miss', () async {
      final harness = await _createHarness(createHarness);

      final read = await harness.backend.read<String>(
        key: KacheKey('missing'),
        binding: harness.bind<String>(fingerprint: 'string-v1'),
      );

      expect(read, isNull);
    });

    test('round-trips typed custom values', () async {
      final harness = await _createHarness(createHarness);
      final binding = harness.bind<PersistenceContractValue>(
        fingerprint: 'contract-value-v1',
      );
      final value = PersistenceContractValue('typed');
      final metadata = _metadata();

      await harness.backend.write<PersistenceContractValue>(
        key: KacheKey('typed', [1]),
        binding: binding,
        entry: KachePersistedEntry<PersistenceContractValue>(
          data: value,
          metadata: metadata,
        ),
      );
      final read = await harness.backend.read<PersistenceContractValue>(
        key: KacheKey('typed', [1]),
        binding: binding,
      );

      expect(read?.entry.data, value);
      expect(read?.entry.metadata, metadata);
    });

    test('distinguishes a persisted null from a miss', () async {
      final harness = await _createHarness(createHarness);
      final binding = harness.bind<String?>(fingerprint: 'nullable-string-v1');
      final key = KacheKey('nullable', [1]);

      await harness.backend.write<String?>(
        key: key,
        binding: binding,
        entry: KachePersistedEntry<String?>(data: null, metadata: _metadata()),
      );
      final read = await harness.backend.read<String?>(
        key: key,
        binding: binding,
      );

      expect(read, isNotNull);
      expect(read?.entry.data, isNull);
    });

    test('overwrites a compatible entry for the same key', () async {
      final harness = await _createHarness(createHarness);
      final binding = harness.bind<String>(fingerprint: 'string-v1');
      final key = KacheKey('overwrite', [1]);

      await _writeString(harness, key, binding, 'first');
      await _writeString(harness, key, binding, 'second');

      final read = await harness.backend.read<String>(
        key: key,
        binding: binding,
      );
      expect(read?.entry.data, 'second');
    });

    test('preserves invalidated metadata', () async {
      final harness = await _createHarness(createHarness);
      final binding = harness.bind<String>(fingerprint: 'string-v1');
      final key = KacheKey('invalidated');
      final metadata = KachePersistedMetadata(
        fetchedAt: DateTime.utc(2026, 3, 4),
        isInvalidated: true,
      );

      await harness.backend.write<String>(
        key: key,
        binding: binding,
        entry: KachePersistedEntry<String>(data: 'stale', metadata: metadata),
      );

      final read = await harness.backend.read<String>(
        key: key,
        binding: binding,
      );
      expect(read?.entry.metadata, metadata);
      expect(read?.entry.metadata.isInvalidated, isTrue);
    });

    test('deletes idempotently', () async {
      final harness = await _createHarness(createHarness);
      final binding = harness.bind<String>(fingerprint: 'string-v1');
      final key = KacheKey('delete', [1]);
      await _writeString(harness, key, binding, 'value');

      await harness.backend.delete(key: key);
      await harness.backend.delete(key: key);

      expect(
        await harness.backend.read<String>(key: key, binding: binding),
        isNull,
      );
    });

    test('clears only the requested namespace', () async {
      final harness = await _createHarness(createHarness);
      final binding = harness.bind<String>(fingerprint: 'string-v1');
      final first = KacheKey('accounts', [1]);
      final second = KacheKey('accounts', [2]);
      final other = KacheKey('account-settings', [1]);
      await _writeString(harness, first, binding, 'first');
      await _writeString(harness, second, binding, 'second');
      await _writeString(harness, other, binding, 'other');

      await harness.backend.clearNamespace(
        namespace: KacheNamespace('accounts'),
      );

      expect(
        await harness.backend.read<String>(key: first, binding: binding),
        isNull,
      );
      expect(
        await harness.backend.read<String>(key: second, binding: binding),
        isNull,
      );
      expect(
        (await harness.backend.read<String>(
          key: other,
          binding: binding,
        ))?.entry.data,
        'other',
      );
    });

    test('clears every entry', () async {
      final harness = await _createHarness(createHarness);
      final binding = harness.bind<String>(fingerprint: 'string-v1');
      final first = KacheKey('first');
      final second = KacheKey('second');
      await _writeString(harness, first, binding, 'first');
      await _writeString(harness, second, binding, 'second');

      await harness.backend.clear();

      expect(
        await harness.backend.read<String>(key: first, binding: binding),
        isNull,
      );
      expect(
        await harness.backend.read<String>(key: second, binding: binding),
        isNull,
      );
    });

    test('rejects a foreign binding while open', () async {
      final harness = await _createHarness(createHarness);
      final other = await _createHarness(createHarness);
      final foreignBinding = other.bind<String>(fingerprint: 'string-v1');
      final key = KacheKey('binding-mismatch');

      await expectLater(
        harness.backend.read<String>(key: key, binding: foreignBinding),
        throwsA(isA<KachePersistenceBindingException>()),
      );
      await expectLater(
        harness.backend.write<String>(
          key: key,
          binding: foreignBinding,
          entry: KachePersistedEntry<String>(
            data: 'value',
            metadata: _metadata(),
          ),
        ),
        throwsA(isA<KachePersistenceBindingException>()),
      );
    });

    for (final operation in [
      KachePersistenceOperation.read,
      KachePersistenceOperation.write,
    ]) {
      test('classifies $operation fingerprint mismatch', () async {
        final harness = await _createHarness(createHarness);
        final key = KacheKey('fingerprint-mismatch');
        final original = harness.bind<String>(fingerprint: 'string-v1');
        await _writeString(harness, key, original, 'value');
        final mismatched = harness.bind<String>(fingerprint: 'string-v2');

        final error = operation == KachePersistenceOperation.read
            ? await _capturePersistenceFailure(
                () =>
                    harness.backend.read<String>(key: key, binding: mismatched),
              )
            : await _capturePersistenceFailure(
                () => _writeString(harness, key, mismatched, 'replacement'),
              );

        _expectBackendFailure(error, operation);
      });

      test('classifies $operation reified type mismatch', () async {
        final harness = await _createHarness(createHarness);
        final key = KacheKey('type-mismatch');
        final original = harness.bind<String>(fingerprint: 'shared-v1');
        await _writeString(harness, key, original, 'value');
        final mismatched = harness.bind<int>(fingerprint: 'shared-v1');

        final error = operation == KachePersistenceOperation.read
            ? await _capturePersistenceFailure(
                () => harness.backend.read<int>(key: key, binding: mismatched),
              )
            : await _capturePersistenceFailure(
                () => harness.backend.write<int>(
                  key: key,
                  binding: mismatched,
                  entry: KachePersistedEntry<int>(
                    data: 2,
                    metadata: _metadata(),
                  ),
                ),
              );

        _expectBackendFailure(error, operation);
      });
    }

    test('closes idempotently', () async {
      final harness = await _createHarness(createHarness);

      await harness.backend.close();
      await harness.backend.close();
    });

    test('prioritizes closed state over foreign binding ownership', () async {
      final harness = await _createHarness(createHarness);
      final other = await _createHarness(createHarness);
      final foreignBinding = other.bind<String>(fingerprint: 'string-v1');
      final key = KacheKey('closed-before-binding');
      await harness.backend.close();

      final readError = await _capturePersistenceFailure(
        () => harness.backend.read<String>(key: key, binding: foreignBinding),
      );
      final writeError = await _capturePersistenceFailure(
        () => harness.backend.write<String>(
          key: key,
          binding: foreignBinding,
          entry: KachePersistedEntry<String>(
            data: 'value',
            metadata: _metadata(),
          ),
        ),
      );

      _expectBackendFailure(readError, KachePersistenceOperation.read);
      _expectBackendFailure(writeError, KachePersistenceOperation.write);
    });

    for (final operation in _operationsAfterClose) {
      test('classifies $operation after close', () async {
        final harness = await _createHarness(createHarness);
        final binding = harness.bind<String>(fingerprint: 'string-v1');
        final key = KacheKey('closed');
        await harness.backend.close();

        final error = await switch (operation) {
          KachePersistenceOperation.read => _capturePersistenceFailure(
            () => harness.backend.read<String>(key: key, binding: binding),
          ),
          KachePersistenceOperation.write => _capturePersistenceFailure(
            () => _writeString(harness, key, binding, 'value'),
          ),
          KachePersistenceOperation.delete => _capturePersistenceFailure(
            () => harness.backend.delete(key: key),
          ),
          KachePersistenceOperation.clearNamespace =>
            _capturePersistenceFailure(
              () => harness.backend.clearNamespace(
                namespace: KacheNamespace('closed'),
              ),
            ),
          KachePersistenceOperation.clear => _capturePersistenceFailure(
            harness.backend.clear,
          ),
          KachePersistenceOperation.close => throw StateError(
            'Close is intentionally excluded from this matrix.',
          ),
        };

        _expectBackendFailure(error, operation);
      });
    }
  });
}

const _operationsAfterClose = <KachePersistenceOperation>[
  KachePersistenceOperation.read,
  KachePersistenceOperation.write,
  KachePersistenceOperation.delete,
  KachePersistenceOperation.clearNamespace,
  KachePersistenceOperation.clear,
];

Future<PersistenceContractHarness> _createHarness(
  PersistenceContractHarnessFactory factory,
) async {
  final harness = await factory();
  addTearDown(harness.dispose);
  return harness;
}

KachePersistedMetadata _metadata() =>
    KachePersistedMetadata(fetchedAt: DateTime.utc(2026, 1, 2));

Future<void> _writeString(
  PersistenceContractHarness harness,
  KacheKey key,
  KachePersistenceBinding<String> binding,
  String data,
) => harness.backend.write<String>(
  key: key,
  binding: binding,
  entry: KachePersistedEntry<String>(data: data, metadata: _metadata()),
);

Future<KachePersistenceException> _capturePersistenceFailure<T>(
  Future<T> Function() action,
) async {
  late Future<T> future;
  try {
    future = action();
  } on Object catch (error, stackTrace) {
    fail(
      'Persistence operation threw synchronously '
      '(${error.runtimeType}).\n$stackTrace',
    );
  }
  try {
    await future;
  } on KachePersistenceException catch (error) {
    return error;
  }
  fail('Expected KachePersistenceException.');
}

void _expectBackendFailure(
  KachePersistenceException error,
  KachePersistenceOperation operation,
) {
  expect(error.operation, operation);
  expect(error.stage, KachePersistenceStage.backend);
  expect(error.cause, isNotNull);
  expect(error.stackTrace.toString(), isNotEmpty);
}

/// A typed custom value used by the shared persistence contract.
///
/// Serialized backends can recognize this public fixture type when selecting
/// their test-only codec.
final class PersistenceContractValue {
  /// Creates a contract fixture containing [value].
  const PersistenceContractValue(this.value);

  /// The value that must survive a persistence round trip.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistenceContractValue && value == other.value;

  @override
  int get hashCode => value.hashCode;
}
