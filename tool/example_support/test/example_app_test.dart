import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache/kache.dart';
import 'package:kache_example_support/kache_example_support.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

void main() {
  testWidgets('shows startup progress, builds runtime, and closes ownership', (
    tester,
  ) async {
    final store = await HiveCeKacheStore.open(
      boxName: 'example_app_bootstrap',
      bytes: Uint8List(0),
    );
    final runtime = ExampleRuntime.fromDependencies(
      store: store,
      gateway: _FakeGateway(),
    );
    final opening = Completer<ExampleRuntime>();

    await tester.pumpWidget(
      KacheExampleApp(
        adapterName: 'Flutter',
        boxName: 'unused-in-test',
        runtimeFactory: () => opening.future,
        builder: (context, value) => Text(value.query.debugName!),
      ),
    );

    expect(find.text('Preparing cache'), findsOneWidget);

    opening.complete(runtime);
    await tester.pump();
    await tester.pump();

    expect(find.text('flutter/flutter repository'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(runtime.client.isClosed, isTrue);
    expect(store.box.isOpen, isFalse);
  });

  testWidgets('offers retry after runtime initialization fails', (
    tester,
  ) async {
    final store = await HiveCeKacheStore.open(
      boxName: 'example_app_retry',
      bytes: Uint8List(0),
    );
    final runtime = ExampleRuntime.fromDependencies(
      store: store,
      gateway: _FakeGateway(),
    );
    var attempts = 0;

    await tester.pumpWidget(
      KacheExampleApp(
        adapterName: 'Provider',
        boxName: 'unused-in-test',
        runtimeFactory: () async {
          attempts += 1;
          if (attempts == 1) {
            throw StateError('startup failed');
          }
          return runtime;
        },
        builder: (context, value) => const Text('Runtime ready'),
      ),
    );
    await tester.pump();

    expect(find.text('Cache startup failed'), findsOneWidget);

    await tester.tap(find.text('Retry startup'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Runtime ready'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

final class _FakeGateway implements RepositoryGateway {
  @override
  Future<RepositoryProfile> fetch(KacheFetchContext context) async =>
      throw StateError('Not used by bootstrap tests.');
}
