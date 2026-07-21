import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache_flutter_hooks/kache_flutter_hooks.dart';

void main() {
  testWidgets(
    'scope client loads once and same-key updates keep the controller',
    (tester) async {
      final client = KacheClient();
      final key = KacheKey('hooks', <Object?>['profile']);
      var firstFetches = 0;
      var secondFetches = 0;
      KacheController<String>? controller;

      Widget app(KacheQuery<String> query) => KacheScope(
        client: client,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: _HookView<String>(
            query: query,
            onBuild: (value) => controller = value,
          ),
        ),
      );

      await tester.pumpWidget(
        app(
          KacheQuery<String>.memory(
            key: key,
            fetch: (_) async {
              firstFetches += 1;
              return 'cached-first';
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final original = controller!;
      expect(firstFetches, 1);
      expect(find.text('cached-first'), findsOneWidget);

      await tester.pumpWidget(
        app(
          KacheQuery<String>.memory(
            key: key,
            fetch: (_) async {
              secondFetches += 1;
              return 'fresh-second';
            },
          ),
        ),
      );
      await tester.pump();

      expect(controller, same(original));
      expect(secondFetches, 0);

      await controller!.refresh();
      await tester.pump();
      expect(secondFetches, 1);
      expect(find.text('fresh-second'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      expect(original.isDisposed, isTrue);
      await client.close();
    },
  );

  testWidgets('key and client changes isolate pending results and dispose', (
    tester,
  ) async {
    final firstClient = KacheClient();
    final secondClient = KacheClient();
    final pending = Completer<String>();
    final controllers = <KacheController<String>>[];

    Widget app({
      required KacheClient client,
      required KacheQuery<String> query,
    }) => Directionality(
      textDirection: TextDirection.ltr,
      child: _HookView<String>(
        client: client,
        query: query,
        onBuild: (value) {
          if (controllers.isEmpty || !identical(controllers.last, value)) {
            controllers.add(value);
          }
        },
      ),
    );

    await tester.pumpWidget(
      app(
        client: firstClient,
        query: KacheQuery<String>.memory(
          key: KacheKey('hooks', <Object?>['old']),
          fetch: (_) => pending.future,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('loading'), findsOneWidget);

    await tester.pumpWidget(
      app(
        client: firstClient,
        query: KacheQuery<String>.memory(
          key: KacheKey('hooks', <Object?>['new']),
          fetch: (_) async => 'new-client-one',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(controllers, hasLength(2));
    expect(controllers.first.isDisposed, isTrue);
    expect(find.text('new-client-one'), findsOneWidget);

    pending.complete('late-old');
    await pending.future;
    await tester.pump();
    expect(find.text('late-old'), findsNothing);

    await tester.pumpWidget(
      app(
        client: secondClient,
        query: KacheQuery<String>.memory(
          key: KacheKey('hooks', <Object?>['new']),
          fetch: (_) async => 'new-client-two',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(controllers, hasLength(3));
    expect(controllers[1].isDisposed, isTrue);
    expect(find.text('new-client-two'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(controllers.last.isDisposed, isTrue);
    await firstClient.close();
    await secondClient.close();
  });

  testWidgets('explicit client works without KacheScope', (tester) async {
    final client = KacheClient();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _HookView<int>(
          client: client,
          query: KacheQuery<int>.memory(
            key: KacheKey('hooks', <Object?>['explicit']),
            fetch: (_) async => 42,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('42'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await client.close();
  });
}

final class _HookView<T> extends HookWidget {
  const _HookView({required this.query, this.client, this.onBuild});

  final KacheQuery<T> query;
  final KacheClient? client;
  final ValueChanged<KacheController<T>>? onBuild;

  @override
  Widget build(BuildContext context) {
    final cache = useKache(query, client: client);
    onBuild?.call(cache);
    return Text(
      cache.snapshot.hasData
          ? '${cache.snapshot.requireData}'
          : cache.snapshot.phase.name,
    );
  }
}
