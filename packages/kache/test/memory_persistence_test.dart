import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryKachePersistence', () {
    test('creates opaque bindings owned by the backend', () {
      final backend = MemoryKachePersistence();

      final binding = backend.bind<String>(fingerprint: 'string-v1');

      expect(binding.backend, same(backend));
      expect(binding.fingerprint, 'string-v1');
    });

    test('keeps typed values by reference without maintenance', () async {
      final backend = MemoryKachePersistence();
      final binding = backend.bind<_MutableValue>(
        fingerprint: 'mutable-value-v1',
      );
      final value = _MutableValue(1);
      final key = KacheKey('references', [1]);

      await backend.write<_MutableValue>(
        key: key,
        binding: binding,
        entry: KachePersistedEntry<_MutableValue>(
          data: value,
          metadata: KachePersistedMetadata(
            fetchedAt: DateTime.utc(2026, 7, 14),
          ),
        ),
      );
      value.count = 2;
      final read = await backend.read<_MutableValue>(
        key: key,
        binding: binding,
      );

      expect(read?.entry.data, same(value));
      expect(read?.entry.data.count, 2);
      expect(read?.hasMaintenance, isFalse);
    });

    test(
      'does not expose stored keys, bindings, or data in mismatches',
      () async {
        const keySecret = 'private-account-key';
        const storedFingerprint = 'private-codec-v1';
        const requestedFingerprint = 'private-codec-v2';
        final backend = MemoryKachePersistence();
        final storedBinding = backend.bind<_SensitiveValue>(
          fingerprint: storedFingerprint,
        );
        final requestedBinding = backend.bind<_SensitiveValue>(
          fingerprint: requestedFingerprint,
        );
        final data = _SensitiveValue('private-payload');
        final key = KacheKey(keySecret, [1]);
        await backend.write<_SensitiveValue>(
          key: key,
          binding: storedBinding,
          entry: KachePersistedEntry<_SensitiveValue>(
            data: data,
            metadata: KachePersistedMetadata(
              fetchedAt: DateTime.utc(2026, 7, 14),
            ),
          ),
        );

        final error = await _capturePersistenceException(
          backend.read<_SensitiveValue>(key: key, binding: requestedBinding),
        );
        final rendered = '${error.toString()} ${error.cause}';

        expect(error.operation, KachePersistenceOperation.read);
        expect(error.stage, KachePersistenceStage.backend);
        expect(error.stackTrace.toString(), isNotEmpty);
        expect(rendered, isNot(contains(keySecret)));
        expect(rendered, isNot(contains(storedFingerprint)));
        expect(rendered, isNot(contains(requestedFingerprint)));
        expect(rendered, isNot(contains(data.secret)));
        expect(data.wasRendered, isFalse);
      },
    );

    test(
      'checks binding ownership before closed state for read and write',
      () async {
        final backend = MemoryKachePersistence();
        final otherBackend = MemoryKachePersistence();
        final foreignBinding = otherBackend.bind<String>(
          fingerprint: 'string-v1',
        );
        final key = KacheKey('binding-first');
        await backend.close();

        await expectLater(
          backend.read<String>(key: key, binding: foreignBinding),
          throwsA(isA<KachePersistenceBindingException>()),
        );
        await expectLater(
          backend.write<String>(
            key: key,
            binding: foreignBinding,
            entry: KachePersistedEntry<String>(
              data: 'value',
              metadata: KachePersistedMetadata(
                fetchedAt: DateTime.utc(2026, 7, 14),
              ),
            ),
          ),
          throwsA(isA<KachePersistenceBindingException>()),
        );
      },
    );
  });
}

final class _MutableValue {
  _MutableValue(this.count);

  int count;
}

final class _SensitiveValue {
  _SensitiveValue(this.secret);

  final String secret;
  bool wasRendered = false;

  @override
  String toString() {
    wasRendered = true;
    return secret;
  }
}

Future<KachePersistenceException> _capturePersistenceException(
  Future<Object?> future,
) async {
  try {
    await future;
  } on KachePersistenceException catch (error) {
    return error;
  }
  fail('Expected KachePersistenceException.');
}
