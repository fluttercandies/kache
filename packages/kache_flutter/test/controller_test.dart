import 'package:flutter_test/flutter_test.dart';
import 'package:kache/kache.dart';
import 'package:kache_flutter/kache_flutter.dart';

void main() {
  test('adapts a resource to ValueListenable and commands', () async {
    final client = KacheClient();
    final controller = KacheController<int>(
      client: client,
      query: KacheQuery<int>.memory(
        key: KacheKey('controller'),
        fetch: (_) async => 1,
      ),
    );
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    await controller.load();
    await controller.setData(2);
    await controller.updateData((snapshot) => snapshot.requireData + 1);

    expect(controller.value.requireData, 3);
    expect(notifications, greaterThan(0));
    controller.dispose();
    await client.close();
  });

  test('same-key query update changes fetcher without auto load', () async {
    final client = KacheClient();
    var firstFetches = 0;
    var secondFetches = 0;
    final key = KacheKey('controller-rebind');
    final controller = KacheController<String>(
      client: client,
      query: KacheQuery<String>.memory(
        key: key,
        fetch: (_) async {
          firstFetches += 1;
          return 'first';
        },
      ),
    );
    await controller.load();

    controller.updateQuery(
      KacheQuery<String>.memory(
        key: key,
        fetch: (_) async {
          secondFetches += 1;
          return 'second';
        },
      ),
    );

    expect(firstFetches, 1);
    expect(secondFetches, 0);
    expect((await controller.refresh()).requireData, 'second');
    controller.dispose();
    await client.close();
  });

  test(
    'different-key query update rebinds and loads the new resource',
    () async {
      final client = KacheClient();
      final controller = KacheController<String>(
        client: client,
        query: KacheQuery<String>.memory(
          key: KacheKey('first'),
          fetch: (_) async => 'first',
        ),
      );
      await controller.load();

      controller.updateQuery(
        KacheQuery<String>.memory(
          key: KacheKey('second'),
          fetch: (_) async => 'second',
        ),
      );
      await controller.load();

      expect(controller.value.requireData, 'second');
      controller.dispose();
      await client.close();
    },
  );

  test('dispose is idempotent and rejects later commands', () async {
    final client = KacheClient();
    final controller = KacheController<int>(
      client: client,
      query: KacheQuery<int>.memory(
        key: KacheKey('disposed-controller'),
        fetch: (_) async => 1,
      ),
    );

    controller.dispose();
    controller.dispose();

    expect(controller.isDisposed, isTrue);
    expect(controller.refresh, throwsA(isA<KacheLifecycleException>()));
    await client.close();
  });
}
