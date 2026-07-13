import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  group('KacheQuery.memory', () {
    test('uses SWR and process memory by default', () async {
      final query = KacheQuery<String>.memory(
        key: KacheKey('profile', [1]),
        fetch: (_) async => 'Ada',
      );

      expect(query.storageMode, KacheStorageMode.memory);
      expect(query.policy, KachePolicy.staleWhileRevalidate());
      expect(query.binding, isNull);
      expect(await query.fetch!(const KacheFetchContext()), 'Ada');
    });

    test('allows a cache-only declaration without a fetcher', () {
      final query = KacheQuery<String>.memory(
        key: KacheKey('profile', [1]),
        policy: KachePolicy.cacheOnly(),
      );

      expect(query.fetch, isNull);
      expect(query.policy.isCacheOnly, isTrue);
    });
  });

  group('KacheQuery.persisted', () {
    test('keeps the typed opaque binding', () {
      final backend = MemoryKachePersistence();
      final binding = backend.bind<String>(fingerprint: 'profile-v1');
      final query = KacheQuery<String>.persisted(
        key: KacheKey('profile', [1]),
        fetch: (_) async => 'Ada',
        binding: binding,
      );

      expect(query.storageMode, KacheStorageMode.persisted);
      expect(query.binding, same(binding));
    });

    test('supports persisted nullable values', () {
      final backend = MemoryKachePersistence();
      final binding = backend.bind<String?>(fingerprint: 'nullable-v1');

      final query = KacheQuery<String?>.persisted(
        key: KacheKey('nullable'),
        fetch: (_) async => null,
        binding: binding,
      );

      expect(query.binding, same(binding));
    });
  });

  group('KacheQuery.networkOnly', () {
    test('uses no storage and fixed always-revalidate policy', () {
      final query = KacheQuery<int>.networkOnly(
        key: KacheKey('counter'),
        fetch: (_) async => 1,
      );

      expect(query.storageMode, KacheStorageMode.none);
      expect(query.binding, isNull);
      expect(query.policy, KachePolicy.staleWhileRevalidate());
      expect(query.policy.refreshOnLoad, KacheRevalidation.always);
    });
  });

  group('KacheQuery validation', () {
    test('requires a fetcher unless the policy is cache-only', () {
      expect(
        () => KacheQuery<String>.memory(
          key: KacheKey('profile'),
          policy: KachePolicy.cacheFirst(freshFor: Duration(minutes: 1)),
        ),
        throwsA(isA<KacheConfigurationException>()),
      );
    });

    test('rejects empty debug names without exposing metadata', () {
      const secret = 'private-value';

      Object? error;
      try {
        KacheQuery<String>.memory(
          key: KacheKey('profile'),
          fetch: (_) async => 'Ada',
          debugName: '  ',
          metadata: const <String, Object?>{'secret': secret},
        );
      } on Object catch (caught) {
        error = caught;
      }

      expect(error, isA<KacheConfigurationException>());
      expect(error.toString(), isNot(contains(secret)));
    });

    test('defensively copies metadata', () {
      final metadata = <String, Object?>{'screen': 'profile'};
      final query = KacheQuery<String>.memory(
        key: KacheKey('profile'),
        fetch: (_) async => 'Ada',
        metadata: metadata,
      );

      metadata['screen'] = 'changed';

      expect(query.metadata, const <String, Object?>{'screen': 'profile'});
      expect(() => query.metadata['other'] = 'invalid', throwsUnsupportedError);
    });
  });

  group('KacheFetchContext', () {
    test('starts active and supports cooperative cancellation', () {
      final controller = KacheCancellationController();
      final context = KacheFetchContext(cancellation: controller.token);

      expect(context.isCancelled, isFalse);
      expect(() => context.throwIfCancelled(), returnsNormally);

      controller.cancel();

      expect(context.isCancelled, isTrue);
      expect(
        () => context.throwIfCancelled(),
        throwsA(isA<KacheCancelledException>()),
      );
      expect(() => controller.cancel(), returnsNormally);
    });

    test('default context never cancels', () {
      const context = KacheFetchContext();

      expect(context.isCancelled, isFalse);
      expect(() => context.throwIfCancelled(), returnsNormally);
    });
  });
}
