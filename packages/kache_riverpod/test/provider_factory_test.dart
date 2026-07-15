import 'package:kache_riverpod/kache_riverpod.dart';
import 'package:riverpod/misc.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

void main() {
  test('family builds independent queries from each argument', () async {
    final client = KacheClient();
    final family = kacheProvider.family<String, int>(
      client: (ref) => client,
      query:
          (ref, userId) => KacheQuery.memory(
            key: KacheKey('users', <Object?>[userId]),
            fetch: (context) async => 'user-$userId',
          ),
    );
    final container = ProviderContainer();
    final first = container.listen(
      family(1),
      (previous, next) {},
      fireImmediately: true,
    );
    final second = container.listen(
      family(2),
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      first.close();
      second.close();
      container.dispose();
      await client.close();
    });

    await pumpEventQueue();
    await container.pump();

    expect(first.read().requireData, 'user-1');
    expect(second.read().requireData, 'user-2');
    expect(
      container.read(family(1).notifier).query.key,
      KacheKey('users', <Object?>[1]),
    );
  });

  test('auto-dispose family accepts a named record argument', () async {
    final client = KacheClient();
    final family = kacheProvider.autoDispose
        .family<String, ({String text, int page})>(
          client: (ref) => client,
          query:
              (ref, args) => KacheQuery.memory(
                key: KacheKey('search', <Object?>[args.text, args.page]),
                fetch: (context) async => '${args.text}:${args.page}',
              ),
        );
    final container = ProviderContainer();
    final first = container.listen(
      family((text: 'flutter', page: 1)),
      (previous, next) {},
      fireImmediately: true,
    );
    final second = container.listen(
      family((text: 'flutter', page: 2)),
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      first.close();
      second.close();
      container.dispose();
      await client.close();
    });

    await pumpEventQueue();
    await container.pump();

    expect(first.read().requireData, 'flutter:1');
    expect(second.read().requireData, 'flutter:2');
    expect(
      family((text: 'flutter', page: 1)),
      family((text: 'flutter', page: 1)),
    );
  });

  test('ref dependencies rebuild the notifier with a new query', () async {
    final client = KacheClient();
    final parameterProvider = NotifierProvider<_ParameterNotifier, int>(
      _ParameterNotifier.new,
    );
    final fetchCounts = <int, int>{};
    final provider = kacheProvider<String>(
      client: (ref) => client,
      query: (ref) {
        final parameter = ref.watch(parameterProvider);
        return KacheQuery.memory(
          key: KacheKey('dependency', <Object?>[parameter]),
          fetch: (context) async {
            fetchCounts.update(
              parameter,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
            return 'value-$parameter';
          },
          policy: KachePolicy.staleWhileRevalidate(gcAfter: Duration.zero),
        );
      },
      dependencies: <ProviderOrFamily>[parameterProvider],
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
    expect(subscription.read().requireData, 'value-1');

    container.read(parameterProvider.notifier).setValue(2);
    await container.pump();
    await pumpEventQueue();
    await container.pump();

    expect(subscription.read().requireData, 'value-2');
    expect(
      container.read(provider.notifier).query.key,
      KacheKey('dependency', <Object?>[2]),
    );
    expect(fetchCounts, <int, int>{1: 1, 2: 1});
  });
}

final class _ParameterNotifier extends Notifier<int> {
  @override
  int build() => 1;

  void setValue(int value) => state = value;
}
