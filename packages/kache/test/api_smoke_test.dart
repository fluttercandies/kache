import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  test('progressive public API supports a complete command workflow', () async {
    final now = DateTime.utc(2026, 9, 10);
    final persistence = MemoryKachePersistence();
    final binding = persistence.bind<int>(fingerprint: 'counter-v1');
    final observed = <KacheEvent>[];
    final client = KacheClient(
      persistence: persistence,
      persistenceOwnership: KachePersistenceOwnership.owned,
      clock: () => now,
      observer: observed.add,
    );
    final query = KacheQuery<int>.persisted(
      key: KacheKey('counter', [1]),
      binding: binding,
      policy: KachePolicy.cacheFirst(
        freshFor: const Duration(minutes: 5),
        expireAfter: const Duration(hours: 1),
      ),
      fetch: (_) async => 1,
      debugName: 'counter',
      metadata: const <String, Object?>{'feature': 'smoke'},
    );

    final prefetched = await client.prefetch(query);
    prefetched.throwIfFailed();
    final resource = client.watch(query);
    expect(client.peek<int>(query.key)?.requireData, 1);

    await resource.load();
    await resource.refresh();
    await resource.setData(2);
    await resource.updateData((snapshot) => snapshot.requireData + 1);
    await resource.invalidate(refetch: false);
    await resource.remove();

    final namespaceClear = await client.clearNamespace(
      KacheNamespace('counter'),
    );
    namespaceClear.throwIfFailed();
    final globalClear = await client.clear();
    globalClear.throwIfFailed();

    expect(observed, isNotEmpty);
    resource.dispose();
    await client.close();
  });

  test('networkOnly and cacheOnly constructors remain explicit', () async {
    final client = KacheClient();
    final network = client.watch(
      KacheQuery<String>.networkOnly(
        key: KacheKey('network'),
        fetch: (_) async => 'network',
      ),
    );
    final cache = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('cache'),
        policy: KachePolicy.cacheOnly(),
      ),
    );

    expect((await network.load()).requireData, 'network');
    expect((await cache.load()).failure?.kind, KacheFailureKind.cacheMiss);

    network.dispose();
    cache.dispose();
    await client.close();
  });
}
