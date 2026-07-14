import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache_flutter/kache_flutter.dart';

void main() {
  testWidgets('observes transitions without rebuilding its child', (
    tester,
  ) async {
    final client = KacheClient();
    final controller = KacheController<int>(
      client: client,
      query: KacheQuery<int>.memory(
        key: KacheKey('listener'),
        policy: KachePolicy.cacheOnly(),
      ),
    );
    var calls = 0;
    var builds = 0;
    KacheSnapshot<int>? previous;
    KacheSnapshot<int>? current;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: KacheListener<int>(
          controller: controller,
          listener: (context, before, after) {
            calls += 1;
            previous = before;
            current = after;
          },
          child: Builder(
            builder: (context) {
              builds += 1;
              return const Text('child');
            },
          ),
        ),
      ),
    );
    final initialBuilds = builds;

    await controller.setData(5);
    await tester.pump();

    expect(calls, 1);
    expect(previous?.hasData, isFalse);
    expect(current?.requireData, 5);
    expect(builds, initialBuilds);

    controller.dispose();
    await client.close();
  });

  testWidgets('listenWhen filters transitions', (tester) async {
    final client = KacheClient();
    final controller = KacheController<int>(
      client: client,
      query: KacheQuery<int>.memory(
        key: KacheKey('listen-when'),
        policy: KachePolicy.cacheOnly(),
      ),
    );
    var calls = 0;
    await tester.pumpWidget(
      KacheListener<int>(
        controller: controller,
        listenWhen: (previous, current) => current.hasData,
        listener: (context, previous, current) => calls += 1,
        child: const SizedBox(),
      ),
    );

    await controller.setData(1);
    await controller.invalidate(refetch: false);
    await controller.remove();
    await tester.pump();

    expect(calls, 2);
    controller.dispose();
    await client.close();
  });
}
