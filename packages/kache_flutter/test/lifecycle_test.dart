import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache_flutter/kache_flutter.dart';

void main() {
  testWidgets('app resume revalidates active resources by policy', (
    tester,
  ) async {
    final client = KacheClient();
    var fetches = 0;
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('app-resume'),
        policy: KachePolicy.cacheFirst(
          freshFor: const Duration(hours: 1),
          refreshOnResume: KacheRevalidation.always,
        ),
        fetch: (_) async => ++fetches,
      ),
    );
    await resource.load();
    await tester.pumpWidget(
      KacheScope(client: client, child: const SizedBox()),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(fetches, 2);
    resource.dispose();
    await client.close();
  });

  testWidgets('host can explicitly refresh active resources', (tester) async {
    final client = KacheClient();
    var fetches = 0;
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('network-restored'),
        fetch: (_) async => ++fetches,
      ),
    );
    await resource.load();
    late BuildContext scopedContext;
    await tester.pumpWidget(
      KacheScope(
        client: client,
        child: Builder(
          builder: (context) {
            scopedContext = context;
            return const SizedBox();
          },
        ),
      ),
    );

    await KacheScope.refreshActive(scopedContext);

    expect(fetches, 2);
    resource.dispose();
    await client.close();
  });
}
