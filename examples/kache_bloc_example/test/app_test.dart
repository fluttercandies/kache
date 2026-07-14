import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache/kache.dart';
import 'package:kache_bloc_example/main.dart';
import 'package:kache_example_support/kache_example_support.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

void main() {
  testWidgets('loads repository data through KacheCubit', (tester) async {
    final fetch = Completer<RepositoryProfile>();
    final store = await HiveCeKacheStore.open(
      boxName: 'bloc_example_app_test',
      bytes: Uint8List(0),
    );
    final runtime = ExampleRuntime.fromDependencies(
      store: store,
      gateway: _ControlledGateway(fetch.future),
    );

    await tester.pumpWidget(
      KacheBlocExampleApp(
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

  testWidgets('policy cards rebuild when their cubits finish fetching', (
    tester,
  ) async {
    final gateway = _SwitchableGateway(_profile());
    final store = await HiveCeKacheStore.open(
      boxName: 'bloc_example_policy_rebuild_test',
      bytes: Uint8List(0),
    );
    final runtime = ExampleRuntime.fromDependencies(
      store: store,
      gateway: gateway,
    );

    await tester.pumpWidget(
      KacheBlocExampleApp(
        runtimeFactory: () async => runtime,
        showNetworkImage: false,
      ),
    );
    await tester.pumpAndSettle();
    gateway.hold = true;
    await tester.tap(find.text('Policies'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(gateway.pending, isNotEmpty);

    gateway.completePending(_profile(stars: 170123));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('170123'), findsWidgets);

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

RepositoryProfile _profile({int stars = 170000}) => RepositoryProfile(
  fullName: 'flutter/flutter',
  description: 'Flutter makes it easy to build beautiful apps.',
  htmlUrl: 'https://github.com/flutter/flutter',
  ownerAvatarUrl: 'https://avatars.example/flutter.png',
  stars: stars,
  forks: 29000,
  openIssues: 12000,
  language: 'Dart',
  updatedAt: DateTime.utc(2026, 7, 14, 8, 30),
);

final class _SwitchableGateway implements RepositoryGateway {
  _SwitchableGateway(this.immediate);

  final RepositoryProfile immediate;
  bool hold = false;
  final List<Completer<RepositoryProfile>> pending =
      <Completer<RepositoryProfile>>[];

  @override
  Future<RepositoryProfile> fetch(KacheFetchContext context) {
    if (!hold) {
      return Future<RepositoryProfile>.value(immediate);
    }
    final completer = Completer<RepositoryProfile>();
    pending.add(completer);
    return completer.future;
  }

  void completePending(RepositoryProfile profile) {
    for (final completer in pending) {
      completer.complete(profile);
    }
    pending.clear();
  }
}
