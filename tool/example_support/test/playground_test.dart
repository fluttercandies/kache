import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache/kache.dart';
import 'package:kache_example_support/kache_example_support.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

void main() {
  testWidgets('KachePlayground switches between its four tabs', (tester) async {
    final store = await HiveCeKacheStore.open(
      boxName: 'playground_shell',
      bytes: Uint8List(0),
    );
    final runtime = ExampleRuntime.fromDependencies(
      store: store,
      gateway: _FakeGateway(),
    );
    addTearDown(() => runtime.close());

    await tester.pumpWidget(
      MaterialApp(
        home: KachePlayground(
          adapterName: 'Flutter',
          repository: (context) => const Center(child: Text('repository-tab')),
          slots: PlaygroundSlots(
            commands: (context) => const Center(child: Text('commands-tab')),
            policies: (context) => const Center(child: Text('policies-tab')),
            activity: (context) => ActivityPlayground(
              client: runtime.client,
              peekQuery: runtime.query,
            ),
          ),
        ),
      ),
    );

    // Repository is the initial tab.
    expect(find.text('repository-tab'), findsOneWidget);
    // All four tab labels are present.
    expect(find.text('Repository'), findsOneWidget);
    expect(find.text('Commands'), findsOneWidget);
    expect(find.text('Policies'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);

    // Activity tab exposes the client-level commands.
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Client commands'), findsOneWidget);
    expect(find.text('Lifecycle toggles'), findsOneWidget);
  });

  testWidgets('empty policy snapshots do not report stale freshness', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PolicyPlayground(
          cards: <PolicyCardModel>[
            PolicyCardModel(
              name: 'cacheOnly',
              description: 'Never fetch automatically.',
              snapshot: KacheSnapshot<RepositoryProfile>.idle(),
              fetchCount: 0,
              onForceFetch: () {},
            ),
          ],
        ),
      ),
    );

    final freshness = tester.widget<PlaygroundStatusItem>(
      find.widgetWithText(PlaygroundStatusItem, 'Freshness'),
    );
    expect(freshness.value, 'None');
  });

  testWidgets('commands requiring data are disabled for an empty snapshot', (
    tester,
  ) async {
    final snapshot = KacheSnapshot<RepositoryProfile>.idle();
    Future<KacheSnapshot<RepositoryProfile>> unchanged() async => snapshot;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandPlayground(
            snapshot: snapshot,
            commands: PlaygroundCommandSet(
              load: unchanged,
              refresh: unchanged,
              setData: unchanged,
              updateData: unchanged,
              invalidate: unchanged,
              invalidateNoRefetch: unchanged,
              remove: unchanged,
            ),
          ),
        ),
      ),
    );

    final setData = tester.widget<ActionChip>(
      find.widgetWithText(ActionChip, 'Set +1 star'),
    );
    final updateData = tester.widget<ActionChip>(
      find.widgetWithText(ActionChip, 'Update value'),
    );
    expect(setData.onPressed, isNull);
    expect(updateData.onPressed, isNull);
  });
}

final class _FakeGateway implements RepositoryGateway {
  @override
  Future<RepositoryProfile> fetch(KacheFetchContext context) async =>
      throw StateError('Not fetched by the shell test.');
}
