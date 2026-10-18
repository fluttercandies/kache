import 'package:kache_riverpod/kache_riverpod.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

void main() {
  test('concurrent commands keep provider revisions monotonic', () async {
    final backend = MemoryKachePersistence();
    final binding = backend.bind<int>(fingerprint: 'riverpod-revision-v1');
    final client = KacheClient(persistence: backend);
    var fetches = 0;
    final provider = kacheProvider<int>(
      client: (_) => client,
      query:
          (_) => KacheQuery<int>.persisted(
            key: KacheKey('riverpod-revision'),
            binding: binding,
            fetch: (_) async => ++fetches,
          ),
    );
    final container = ProviderContainer();
    final revisions = <int>[];
    final subscription = container.listen(
      provider,
      (previous, next) => revisions.add(next.revision),
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await client.close();
    });
    await pumpEventQueue();
    await container.pump();
    revisions.clear();

    final notifier = container.read(provider.notifier);
    await Future.wait<KacheSnapshot<int>>(<Future<KacheSnapshot<int>>>[
      notifier.refresh(),
      notifier.setData(7),
      notifier.refresh(),
    ]);
    await pumpEventQueue();
    await container.pump();

    expect(revisions, isNotEmpty);
    for (var index = 1; index < revisions.length; index++) {
      expect(
        revisions[index],
        greaterThan(revisions[index - 1]),
        reason: 'revisions $revisions',
      );
    }
    expect(subscription.read(), same(notifier.resource.snapshot));
  });

  test('subscription replay of the built snapshot never notifies', () async {
    final client = KacheClient();
    final key = KacheKey('riverpod-replay');
    final warm = client.watch(
      KacheQuery<int>.memory(key: key, policy: KachePolicy.cacheOnly()),
    );
    await warm.setData(1);
    final provider = kacheProvider<int>(
      client: (_) => client,
      query:
          (_) =>
              KacheQuery<int>.memory(key: key, policy: KachePolicy.cacheOnly()),
    );
    final container = ProviderContainer();
    final notifications = <KacheSnapshot<int>>[];
    final subscription = container.listen(
      provider,
      (previous, next) => notifications.add(next),
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      warm.dispose();
      await client.close();
    });

    final built = subscription.read();
    await pumpEventQueue();
    await container.pump();

    expect(built.requireData, 1);
    // The automatic load may publish newer snapshots; the replay of the
    // snapshot returned by build must never reach listeners.
    expect(
      notifications.map((snapshot) => snapshot.revision),
      everyElement(greaterThan(built.revision)),
    );
    expect(
      notifications.where((snapshot) => identical(snapshot, built)),
      isEmpty,
    );
  });
}
