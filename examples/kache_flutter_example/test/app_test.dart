import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache/kache.dart';
import 'package:kache_example_support/kache_example_support.dart';
import 'package:kache_flutter_example/main.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

void main() {
  testWidgets('loads repository data and clears the cached value', (
    tester,
  ) async {
    final fetch = Completer<RepositoryProfile>();
    final store = await HiveCeKacheStore.open(
      boxName: 'flutter_example_app_test',
      bytes: Uint8List(0),
    );
    final runtime = ExampleRuntime.fromDependencies(
      store: store,
      gateway: _ControlledGateway(fetch.future),
    );

    await tester.pumpWidget(
      KacheFlutterExampleApp(
        runtimeFactory: () async => runtime,
        showNetworkImage: false,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Loading repository'), findsOneWidget);

    fetch.complete(_profile());
    await fetch.future;
    await tester.pump();
    await tester.pump();
    expect(find.text('flutter/flutter'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear cached repository'));
    await tester.pump();
    await tester.pump();
    expect(find.text('No cached repository'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(runtime.client.isClosed, isTrue);
  });

  testWidgets('commands tab renders the snapshot inspector and command chips', (
    tester,
  ) async {
    final fetch = Completer<RepositoryProfile>();
    final store = await HiveCeKacheStore.open(
      boxName: 'flutter_example_commands_test',
      bytes: Uint8List(0),
    );
    final runtime = ExampleRuntime.fromDependencies(
      store: store,
      gateway: _ControlledGateway(fetch.future),
    );

    await tester.pumpWidget(
      KacheFlutterExampleApp(
        runtimeFactory: () async => runtime,
        showNetworkImage: false,
      ),
    );
    await tester.pump();
    await tester.pump();

    // Switch to the Commands tab and let the initial fetch resolve.
    await tester.tap(find.text('Commands'));
    await tester.pump();
    fetch.complete(_profile());
    await fetch.future;
    await tester.pumpAndSettle();

    // The snapshot inspector renders the expected sections and fields.
    expect(find.text('Snapshot'), findsOneWidget);
    expect(find.text('Commands'), findsWidgets);
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Refresh'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(runtime.client.isClosed, isTrue);
  });
}

final class _ControlledGateway implements RepositoryGateway {
  _ControlledGateway(this.result);

  final Future<RepositoryProfile> result;

  @override
  Future<RepositoryProfile> fetch(KacheFetchContext context) => result;
}

RepositoryProfile _profile() => RepositoryProfile(
  fullName: 'flutter/flutter',
  description: 'Flutter makes it easy to build beautiful apps.',
  htmlUrl: 'https://github.com/flutter/flutter',
  ownerAvatarUrl: 'https://avatars.example/flutter.png',
  stars: 170000,
  forks: 29000,
  openIssues: 12000,
  language: 'Dart',
  updatedAt: DateTime.utc(2026, 7, 14, 8, 30),
);
