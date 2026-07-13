import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  test('rejects persisted queries when the client has no backend', () {
    final backend = MemoryKachePersistence();
    final query = KacheQuery<String>.persisted(
      key: KacheKey('profile'),
      binding: backend.bind<String>(fingerprint: 'profile-v1'),
      fetch: (_) async => 'Ada',
    );
    final client = KacheClient();

    expect(
      () => client.watch(query),
      throwsA(
        isA<KacheConfigurationException>().having(
          (error) => error.code,
          'code',
          'persistence_unavailable',
        ),
      ),
    );
  });

  test('rejects a binding owned by another backend', () {
    final configured = MemoryKachePersistence();
    final foreign = MemoryKachePersistence();
    final client = KacheClient(persistence: configured);
    final query = KacheQuery<String>.persisted(
      key: KacheKey('profile'),
      binding: foreign.bind<String>(fingerprint: 'profile-v1'),
      fetch: (_) async => 'Ada',
    );

    expect(
      () => client.watch(query),
      throwsA(
        isA<KacheConfigurationException>().having(
          (error) => error.code,
          'code',
          'binding_backend_mismatch',
        ),
      ),
    );
  });

  test('rejects a different value type for an active key', () {
    final client = KacheClient();
    final key = KacheKey('shared');
    final first = client.watch(
      KacheQuery<String>.memory(key: key, fetch: (_) async => 'one'),
    );

    expect(
      () =>
          client.watch(KacheQuery<int>.memory(key: key, fetch: (_) async => 1)),
      throwsA(
        isA<KacheConfigurationException>().having(
          (error) => error.code,
          'code',
          'key_type_conflict',
        ),
      ),
    );

    first.dispose();
  });

  test('rejects a different storage mode for an active key', () {
    final client = KacheClient();
    final key = KacheKey('shared');
    final first = client.watch(
      KacheQuery<String>.memory(key: key, fetch: (_) async => 'one'),
    );

    expect(
      () => client.watch(
        KacheQuery<String>.networkOnly(key: key, fetch: (_) async => 'two'),
      ),
      throwsA(
        isA<KacheConfigurationException>().having(
          (error) => error.code,
          'code',
          'key_storage_conflict',
        ),
      ),
    );

    first.dispose();
  });

  test('rejects a different binding fingerprint for an active key', () {
    final backend = MemoryKachePersistence();
    final client = KacheClient(persistence: backend);
    final key = KacheKey('shared');
    final first = client.watch(
      KacheQuery<String>.persisted(
        key: key,
        binding: backend.bind<String>(fingerprint: 'profile-v1'),
        fetch: (_) async => 'one',
      ),
    );

    expect(
      () => client.watch(
        KacheQuery<String>.persisted(
          key: key,
          binding: backend.bind<String>(fingerprint: 'profile-v2'),
          fetch: (_) async => 'two',
        ),
      ),
      throwsA(
        isA<KacheConfigurationException>().having(
          (error) => error.code,
          'code',
          'key_binding_conflict',
        ),
      ),
    );

    first.dispose();
  });

  test('configuration errors never render key or fingerprint values', () {
    const secret = 'private-fingerprint';
    final backend = MemoryKachePersistence();
    final client = KacheClient(persistence: backend);
    final first = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('private', [secret]),
        binding: backend.bind<String>(fingerprint: 'first'),
        fetch: (_) async => 'one',
      ),
    );

    Object? error;
    try {
      client.watch(
        KacheQuery<String>.persisted(
          key: KacheKey('private', [secret]),
          binding: backend.bind<String>(fingerprint: secret),
          fetch: (_) async => 'two',
        ),
      );
    } on Object catch (caught) {
      error = caught;
    }

    expect(error.toString(), isNot(contains(secret)));
    first.dispose();
  });
}
