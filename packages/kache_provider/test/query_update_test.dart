import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache_provider/kache_provider.dart';

void main() {
  testWidgets('query changes reuse the controller and bind the new key', (
    tester,
  ) async {
    final client = KacheClient();
    late KacheController<int> controller;

    Widget build(int parameter) => Directionality(
          textDirection: TextDirection.ltr,
          child: KacheProvider<int>(
            client: client,
            query: KacheQuery.memory(
              key: KacheKey('provider-parameter', <Object?>[parameter]),
              fetch: (context) async => parameter,
            ),
            child: KacheConsumer<int>(
              builder: (context, snapshot, value, child) {
                controller = value;
                return Text('${snapshot.dataOrNull}');
              },
            ),
          ),
        );

    await tester.pumpWidget(build(1));
    await tester.pump();
    await tester.pump();
    final original = controller;
    expect(find.text('1'), findsOneWidget);

    await tester.pumpWidget(build(2));
    await tester.pump();
    await tester.pump();

    expect(controller, same(original));
    expect(controller.query.key, KacheKey('provider-parameter', <Object?>[2]));
    expect(find.text('2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await client.close();
  });

  testWidgets('client changes replace the controller without closing clients', (
    tester,
  ) async {
    final firstClient = KacheClient();
    final secondClient = KacheClient();
    late KacheController<int> controller;

    Widget build(KacheClient client, int value) => KacheProvider<int>(
          client: client,
          query: KacheQuery.memory(
            key: KacheKey('provider-client', <Object?>[value]),
            policy: KachePolicy.cacheOnly(),
          ),
          child: KacheConsumer<int>(
            builder: (context, snapshot, current, child) {
              controller = current;
              return const SizedBox();
            },
          ),
        );

    await tester.pumpWidget(build(firstClient, 1));
    final firstController = controller;

    await tester.pumpWidget(build(secondClient, 2));

    expect(firstController.isDisposed, isTrue);
    expect(controller, isNot(same(firstController)));
    expect(firstClient.isClosed, isFalse);
    expect(secondClient.isClosed, isFalse);

    await tester.pumpWidget(const SizedBox());
    await firstClient.close();
    await secondClient.close();
  });
}
