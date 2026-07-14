import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache/kache.dart';
import 'package:kache_example_support/kache_example_support.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';
import 'package:kache_riverpod_example/main.dart';

void main() {
  testWidgets('loads repository data through the Riverpod notifier', (
    tester,
  ) async {
    final fetch = Completer<RepositoryProfile>();
    final store = await HiveCeKacheStore.open(
      boxName: 'riverpod_example_app_test',
      bytes: Uint8List(0),
    );
    final runtime = ExampleRuntime.fromDependencies(
      store: store,
      gateway: _ControlledGateway(fetch.future),
    );

    await tester.pumpWidget(
      KacheRiverpodExampleApp(
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

  testWidgets('policy cards show fetch counts from client events', (
    tester,
  ) async {
    final store = await HiveCeKacheStore.open(
      boxName: 'riverpod_example_policy_counts_test',
      bytes: Uint8List(0),
    );
    final runtime = ExampleRuntime.fromDependencies(
      store: store,
      gateway: _ControlledGateway(Future.value(_profile())),
    );

    await tester.pumpWidget(
      KacheRiverpodExampleApp(
        runtimeFactory: () async => runtime,
        showNetworkImage: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Policies'));
    await tester.pumpAndSettle();

    expect(find.text('Fetches'), findsNWidgets(4));
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('keepAlive controls update immediately', (tester) async {
    final store = await HiveCeKacheStore.open(
      boxName: 'riverpod_example_keep_alive_test',
      bytes: Uint8List(0),
    );
    final runtime = ExampleRuntime.fromDependencies(
      store: store,
      gateway: _ControlledGateway(Future.value(_profile())),
    );

    await tester.pumpWidget(
      KacheRiverpodExampleApp(
        runtimeFactory: () async => runtime,
        showNetworkImage: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Policies'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('Request keepAlive'), findsOneWidget);

    await tester.tap(find.text('Request keepAlive'));
    await tester.pump();
    expect(find.text('Release keepAlive'), findsOneWidget);

    await tester.tap(find.text('Release keepAlive'));
    await tester.pump();
    expect(find.text('Request keepAlive'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
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
