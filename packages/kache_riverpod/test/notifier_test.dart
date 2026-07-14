import 'dart:async';

import 'package:kache_riverpod/kache_riverpod.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

void main() {
  test(
    'exposes complete snapshots and retains data after refresh failure',
    () async {
      final client = KacheClient();
      final initialFetch = Completer<String>();
      var fetchCount = 0;
      final provider = kacheProvider<String>(
        client: (ref) => client,
        query: (ref) => KacheQuery.memory(
          key: KacheKey('riverpod', <Object?>['profile']),
          fetch: (context) {
            fetchCount += 1;
            if (fetchCount == 1) {
              return initialFetch.future;
            }
            return Future<String>.error(StateError('offline'));
          },
        ),
      );
      final container = ProviderContainer();
      final subscription = container.listen(
        provider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await client.close();
      });

      await pumpEventQueue();
      await container.pump();
      expect(subscription.read().phase, KachePhase.loading);

      initialFetch.complete('Ada');
      await initialFetch.future;
      await pumpEventQueue();
      await container.pump();

      final loaded = subscription.read();
      expect(loaded.phase, KachePhase.ready);
      expect(loaded.requireData, 'Ada');
      expect(loaded.failure, isNull);

      final refreshed = await container.read(provider.notifier).refresh();
      await pumpEventQueue();
      await container.pump();

      expect(refreshed.phase, KachePhase.ready);
      expect(refreshed.requireData, 'Ada');
      expect(refreshed.failure?.kind, KacheFailureKind.fetch);
      expect(subscription.read(), same(refreshed));
    },
  );

  test('proxies cache commands without creating adapter state', () async {
    final client = KacheClient();
    final provider = kacheProvider<int>(
      client: (ref) => client,
      query: (ref) => KacheQuery.memory(
        key: KacheKey('riverpod', <Object?>['counter']),
        policy: KachePolicy.cacheOnly(),
      ),
    );
    final container = ProviderContainer();
    final subscription = container.listen(
      provider,
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await client.close();
    });
    final notifier = container.read(provider.notifier);

    expect((await notifier.load()).failure?.kind, KacheFailureKind.cacheMiss);
    expect((await notifier.setData(1)).requireData, 1);
    expect(
      (await notifier.updateData(
        (snapshot) => snapshot.requireData + 1,
      )).requireData,
      2,
    );
    final invalidated = await notifier.invalidate(refetch: false);
    expect(invalidated.freshness, KacheFreshness.stale);
    expect((await notifier.remove()).phase, KachePhase.idle);
  });
}
