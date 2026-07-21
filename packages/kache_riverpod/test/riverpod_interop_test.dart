import 'dart:async';

import 'package:kache_riverpod/kache_riverpod.dart';
import 'package:riverpod/misc.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

void main() {
  test('preserves name, scoped dependencies, select, and observers', () async {
    final client = KacheClient();
    final dependency = Provider<int>((_) => 1, dependencies: const []);
    final provider = kacheProvider<int>(
      name: 'scopedKache',
      dependencies: <ProviderOrFamily>[dependency],
      client: (_) => client,
      query: (ref) {
        final value = ref.watch(dependency);
        return KacheQuery<int>.memory(
          key: KacheKey('riverpod-scope', <Object?>[value]),
          fetch: (_) async => value,
        );
      },
    );
    final observer = _Observer();
    final root = ProviderContainer();
    final child = ProviderContainer(
      parent: root,
      observers: <ProviderObserver>[observer],
      overrides: <Override>[dependency.overrideWithValue(2)],
    );
    final snapshots = child.listen(
      provider,
      (previous, next) {},
      fireImmediately: true,
    );
    final selectedValues = <int?>[];
    final selected = child.listen(
      provider.select((snapshot) => snapshot.dataOrNull),
      (previous, next) => selectedValues.add(next),
    );
    addTearDown(() async {
      selected.close();
      snapshots.close();
      child.dispose();
      root.dispose();
      await client.close();
    });

    await pumpEventQueue();
    await child.pump();

    expect(provider.name, 'scopedKache');
    expect(provider.dependencies, contains(dependency));
    expect(snapshots.read().requireData, 2);
    expect(
      child.read(provider.notifier).query.key,
      KacheKey('riverpod-scope', <Object?>[2]),
    );

    selectedValues.clear();
    observer.updated.clear();
    await child.read(provider.notifier).setData(3);
    await child.pump();

    expect(selectedValues, <int?>[3]);
    expect(observer.updated, contains(provider));
  });

  test(
    'provider rebuild commands and Kache refresh have distinct effects',
    () async {
      final client = KacheClient();
      var fetches = 0;
      final provider = kacheProvider<int>(
        client: (_) => client,
        query:
            (_) => KacheQuery<int>.memory(
              key: KacheKey('riverpod-refresh'),
              fetch: (_) async => ++fetches,
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

      final notifier = container.read(provider.notifier);
      final firstResource = notifier.resource;
      expect(subscription.read().requireData, 1);

      await notifier.refresh();
      await container.pump();
      expect(fetches, 2);
      expect(notifier.resource, same(firstResource));

      container.refresh(provider);
      await pumpEventQueue();
      await container.pump();
      expect(container.read(provider.notifier), same(notifier));
      final refreshedResource = container.read(provider.notifier).resource;
      expect(fetches, 3);
      expect(refreshedResource, isNot(same(firstResource)));

      container.invalidate(provider);
      await pumpEventQueue();
      await container.pump();
      expect(fetches, 4);
      expect(subscription.read().requireData, 4);
    },
  );

  test('paused subscriptions replay only the latest Kache snapshot', () async {
    final client = KacheClient();
    final provider = kacheProvider<int>(
      client: (_) => client,
      query:
          (_) => KacheQuery<int>.memory(
            key: KacheKey('riverpod-pause'),
            policy: KachePolicy.cacheOnly(),
          ),
    );
    final values = <int?>[];
    final container = ProviderContainer();
    final subscription = container.listen(
      provider,
      (previous, next) => values.add(next.dataOrNull),
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await client.close();
    });
    await pumpEventQueue();
    await container.pump();
    values.clear();

    subscription.pause();
    expect(subscription.isPaused, isTrue);
    await container.read(provider.notifier).setData(1);
    await container.read(provider.notifier).setData(2);
    await container.pump();
    expect(values, isEmpty);

    subscription.resume();
    expect(subscription.isPaused, isFalse);
    expect(values, <int?>[2]);
  });

  test('regular and family aliases preserve native override APIs', () async {
    final originalClient = KacheClient();
    final overrideClient = KacheClient();
    final provider = kacheProvider<String>(
      client: (_) => originalClient,
      query: (_) => _query('regular', 'original'),
    );
    final family = kacheProvider.family<String, int>(
      client: (_) => originalClient,
      query: (_, id) => _query('family-$id', 'original-$id'),
    );
    final container = ProviderContainer(
      overrides: <Override>[
        provider.overrideWith(
          () => KacheNotifier<String>(
            client: (_) => overrideClient,
            query: (_) => _query('regular-override', 'override'),
          ),
        ),
        family.overrideWith2(
          (id) => KacheNotifier<String>(
            client: (_) => overrideClient,
            query: (_) => _query('family-override-$id', 'override-$id'),
          ),
        ),
      ],
    );
    final regular = container.listen(
      provider,
      (previous, next) {},
      fireImmediately: true,
    );
    final parameterized = container.listen(
      family(9),
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      regular.close();
      parameterized.close();
      container.dispose();
      await originalClient.close();
      await overrideClient.close();
    });
    await pumpEventQueue();
    await container.pump();

    expect(regular.read().requireData, 'override');
    expect(parameterized.read().requireData, 'override-9');
  });

  test(
    'build errors and Kache fetch failures keep distinct channels',
    () async {
      final client = KacheClient();
      var builds = 0;
      final buildFailureProvider = kacheProvider<int>(
        client: (_) {
          builds += 1;
          if (builds == 1) {
            throw StateError('client unavailable');
          }
          return client;
        },
        query: (_) => _queryInt('build-retry', 1),
      );
      final buildErrors = <Object>[];
      final container = ProviderContainer();
      final buildSubscription = container.listen(
        buildFailureProvider,
        (previous, next) {},
        onError: (error, stackTrace) => buildErrors.add(error),
        fireImmediately: true,
      );
      addTearDown(() async {
        buildSubscription.close();
        container.dispose();
        await client.close();
      });

      await container.pump();
      expect(builds, 1);
      expect(buildErrors.single, isA<StateError>());

      final fetchFailureProvider = kacheProvider<int>(
        client: (_) => client,
        query:
            (_) => KacheQuery<int>.memory(
              key: KacheKey('riverpod-fetch-failure'),
              fetch: (_) => Future<int>.error(StateError('offline')),
            ),
      );
      final fetchSubscription = container.listen(
        fetchFailureProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(fetchSubscription.close);
      await pumpEventQueue();
      await container.pump();

      expect(fetchSubscription.read().failure?.kind, KacheFailureKind.fetch);
    },
  );
}

KacheQuery<String> _query(String key, String value) =>
    KacheQuery<String>.memory(
      key: KacheKey('riverpod-override', <Object?>[key]),
      fetch: (_) async => value,
    );

KacheQuery<int> _queryInt(String key, int value) => KacheQuery<int>.memory(
  key: KacheKey('riverpod-retry', <Object?>[key]),
  fetch: (_) async => value,
);

final class _Observer extends ProviderObserver {
  final List<ProviderBase<Object?>> updated = <ProviderBase<Object?>>[];

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    updated.add(context.provider);
  }
}
