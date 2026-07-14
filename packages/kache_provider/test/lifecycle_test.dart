import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache_provider/kache_provider.dart';

void main() {
  testWidgets('borrowed scope disposes controller but not client', (
    tester,
  ) async {
    final client = KacheClient();
    late KacheController<int> controller;

    await tester.pumpWidget(
      KacheScope(
        client: client,
        child: KacheProvider<int>(
          query: _cacheOnlyQuery('borrowed'),
          child: KacheConsumer<int>(
            builder: (context, snapshot, value, child) {
              controller = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    await tester.pumpWidget(const SizedBox());

    expect(controller.isDisposed, isTrue);
    expect(client.isClosed, isFalse);
    await client.close();
  });

  testWidgets('owned scope remains the only owner that closes the client', (
    tester,
  ) async {
    final client = KacheClient();

    await tester.pumpWidget(
      KacheScope(
        client: client,
        ownership: KacheScopeOwnership.owned,
        child: KacheProvider<int>(
          query: _cacheOnlyQuery('owned'),
          child: const SizedBox(),
        ),
      ),
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(client.isClosed, isTrue);
  });

  testWidgets('pending fetch after dispose cannot notify the widget tree', (
    tester,
  ) async {
    final client = KacheClient();
    final fetch = Completer<int>();
    late KacheController<int> controller;

    await tester.pumpWidget(
      KacheProvider<int>(
        client: client,
        query: KacheQuery.memory(
          key: KacheKey('provider-lifecycle', <Object?>['pending']),
          fetch: (context) => fetch.future,
        ),
        child: KacheConsumer<int>(
          builder: (context, snapshot, value, child) {
            controller = value;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    expect(controller.isDisposed, isTrue);

    fetch.complete(1);
    await fetch.future;
    await tester.pump();

    expect(tester.takeException(), isNull);
    await client.close();
  });

  testWidgets('requires an explicit client or KacheScope', (tester) async {
    await tester.pumpWidget(
      KacheProvider<int>(
        query: _cacheOnlyQuery('missing-client'),
        child: const SizedBox(),
      ),
    );

    expect(
      tester.takeException(),
      isA<FlutterError>().having(
        (error) => error.message,
        'message',
        contains('explicit client or a KacheScope'),
      ),
    );
  });
}

KacheQuery<int> _cacheOnlyQuery(String id) => KacheQuery.memory(
      key: KacheKey('provider-lifecycle', <Object?>[id]),
      policy: KachePolicy.cacheOnly(),
    );
