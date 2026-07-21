import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kache_hooks_riverpod/kache_hooks_riverpod.dart';

void main() {
  testWidgets('hook watches one provider resource and delegates commands', (
    tester,
  ) async {
    final client = KacheClient();
    var fetches = 0;
    final provider = kacheProvider<int>(
      client: (_) => client,
      query: (_) => KacheQuery<int>.memory(
        key: KacheKey('hooks-riverpod', <Object?>['commands']),
        fetch: (_) async => ++fetches,
      ),
    );
    KacheProviderBinding<int>? binding;

    await tester.pumpWidget(
      ProviderScope(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: _BindingView<int>(
            provider: provider,
            onBuild: (value) => binding = value,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(fetches, 1);
    expect(find.text('1'), findsOneWidget);
    expect(binding!.resource, same(binding!.notifier.resource));

    expect((await binding!.load()).requireData, 2);
    expect((await binding!.refresh()).requireData, 3);
    expect((await binding!.setData(10)).requireData, 10);
    expect(
      (await binding!.updateData(
        (snapshot) => snapshot.requireData + 1,
      )).requireData,
      11,
    );
    expect(
      (await binding!.invalidate(refetch: false)).freshness,
      KacheFreshness.stale,
    );
    expect((await binding!.remove()).phase, KachePhase.idle);
    await tester.pump();

    expect(find.text('idle'), findsOneWidget);
    expect(fetches, 3);
    await tester.pumpWidget(const SizedBox());
    await client.close();
  });

  testWidgets(
    'provider and family overrides remain native Riverpod overrides',
    (tester) async {
      final originalClient = KacheClient();
      final overrideClient = KacheClient();
      final provider = kacheProvider<String>(
        client: (_) => originalClient,
        query: (_) => _stringQuery('regular', 'original'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            provider.overrideWith(
              () => KacheNotifier<String>(
                client: (_) => overrideClient,
                query: (_) => _stringQuery('regular-override', 'override'),
              ),
            ),
          ],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: _BindingView<String>(provider: provider),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('override'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      final family = kacheProvider.family<String, int>(
        client: (_) => originalClient,
        query: (_, id) => _stringQuery('family-$id', 'original-$id'),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            family.overrideWith2(
              (id) => KacheNotifier<String>(
                client: (_) => overrideClient,
                query: (_) =>
                    _stringQuery('family-override-$id', 'override-$id'),
              ),
            ),
          ],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: _BindingView<String>(provider: family(7)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('override-7'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await originalClient.close();
      await overrideClient.close();
    },
  );

  test('hook watches provider state and notifier as build dependencies', () {
    final source = File('lib/src/use_kache_provider.dart').readAsStringSync();

    expect(source, contains('ref.watch(provider);'));
    expect(source, contains('ref.watch(provider.notifier);'));
    expect(source, isNot(contains('ref.read(provider.notifier);')));
  });

  testWidgets('autoDispose releases its resource after the hook unmounts', (
    tester,
  ) async {
    final client = KacheClient();
    final key = KacheKey('hooks-riverpod', <Object?>['auto-dispose']);
    final provider = kacheProvider.autoDispose<int>(
      client: (_) => client,
      query: (_) => KacheQuery<int>.memory(
        key: key,
        policy: KachePolicy.cacheOnly(gcAfter: Duration.zero),
      ),
    );
    KacheProviderBinding<int>? binding;
    ProviderContainer? container;
    late StateSetter updateHost;
    var show = true;

    await tester.pumpWidget(
      ProviderScope(
        child: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            container = ProviderScope.containerOf(context);
            return show
                ? Directionality(
                    textDirection: TextDirection.ltr,
                    child: _BindingView<int>(
                      provider: provider,
                      onBuild: (value) => binding = value,
                    ),
                  )
                : const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    await binding!.setData(8);
    await tester.pump();
    expect(client.peek<int>(key)?.requireData, 8);
    final resource = binding!.resource;

    updateHost(() => show = false);
    await tester.pump();
    await container!.pump();
    expect(resource.isDisposed, isTrue);
    await tester.pump(Duration.zero);

    expect(client.peek<int>(key), isNull);
    await tester.pumpWidget(const SizedBox());
    await client.close();
  });
}

KacheQuery<String> _stringQuery(String key, String value) =>
    KacheQuery<String>.memory(
      key: KacheKey('hooks-riverpod', <Object?>[key]),
      fetch: (_) async => value,
    );

final class _BindingView<T> extends HookConsumerWidget {
  const _BindingView({required this.provider, this.onBuild});

  final KacheProvider<T> provider;
  final ValueChanged<KacheProviderBinding<T>>? onBuild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final binding = useKacheProvider(ref, provider);
    onBuild?.call(binding);
    return Text(
      binding.snapshot.hasData
          ? '${binding.snapshot.requireData}'
          : binding.snapshot.phase.name,
    );
  }
}
