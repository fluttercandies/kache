import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache_provider/kache_provider.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('provides cached snapshots and direct controller commands', (
    tester,
  ) async {
    final client = KacheClient();
    final fetch = Completer<int>();
    final query = KacheQuery.memory(
      key: KacheKey('provider', <Object?>['counter']),
      fetch: (context) => fetch.future,
    );
    late BuildContext consumerContext;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: KacheScope(
          client: client,
          child: KacheProvider<int>(
            query: query,
            child: KacheConsumer<int>(
              builder: (context, snapshot, controller, child) {
                consumerContext = context;
                final watched = context.watchKache<int>();
                return Text('${watched.phase.name}:${watched.dataOrNull}');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('loading:null'), findsOneWidget);

    fetch.complete(1);
    await fetch.future;
    await tester.pump();
    await tester.pump();

    expect(find.text('ready:1'), findsOneWidget);

    await consumerContext.readKache<int>().setData(2);
    await tester.pump();

    expect(find.text('ready:2'), findsOneWidget);

    final controller = consumerContext.readKache<int>();
    expect(
      (await controller.invalidate(refetch: false)).freshness,
      KacheFreshness.stale,
    );
    expect((await controller.refresh()).requireData, 1);
    await tester.pump();
    expect(find.text('ready:1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await client.close();
  });

  testWidgets('can be installed directly in MultiProvider', (tester) async {
    final client = KacheClient();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MultiProvider(
          providers: [
            KacheProvider<int>(
              client: client,
              query: KacheQuery.memory(
                key: KacheKey('provider', <Object?>['multi']),
                fetch: (context) async => 5,
              ),
            ),
          ],
          child: KacheConsumer<int>(
            builder: (context, snapshot, controller, child) =>
                Text('${snapshot.dataOrNull}'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('5'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await client.close();
  });
}
