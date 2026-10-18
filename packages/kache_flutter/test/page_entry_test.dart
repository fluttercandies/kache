import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache_flutter/kache_flutter.dart';

void main() {
  late MemoryKachePersistence backend;
  late KachePersistenceBinding<String> binding;
  final key = KacheKey('page-entry');

  setUp(() async {
    backend = MemoryKachePersistence();
    binding = backend.bind<String>(fingerprint: 'page-entry-v1');
    await backend.write<String>(
      key: key,
      binding: binding,
      entry: KachePersistedEntry<String>(
        data: 'cached',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2025)),
      ),
    );
  });

  KacheQuery<String> query(Completer<String> refresh) =>
      KacheQuery<String>.persisted(
        key: key,
        binding: binding,
        fetch: (_) => refresh.future,
      );

  test('subscription replay never rolls the controller value back', () async {
    final client = KacheClient(persistence: backend);
    final refresh = Completer<String>();
    final controller = KacheController<String>(
      client: client,
      query: query(refresh),
    );
    final observed = <KacheSnapshot<String>>[controller.value];
    controller.addListener(() => observed.add(controller.value));

    await Future<void>.delayed(Duration.zero);
    refresh.complete('fresh');
    await controller.resource.stream.firstWhere(
      (snapshot) =>
          snapshot.source == KacheDataSource.fetch &&
          snapshot.persistence?.phase == KachePersistencePhase.persisted,
    );
    await Future<void>.delayed(Duration.zero);

    final revisions = observed.map((snapshot) => snapshot.revision).toList();
    for (var index = 1; index < revisions.length; index++) {
      expect(
        revisions[index],
        greaterThan(revisions[index - 1]),
        reason: 'revisions $revisions',
      );
    }
    expect(observed.first.phase, KachePhase.loading);
    expect(
      observed.skip(1).every((snapshot) => snapshot.hasData),
      isTrue,
      reason: 'after the read, a cached page never falls back to empty',
    );
    expect(
      observed.where((snapshot) => snapshot.phase == KachePhase.idle),
      isEmpty,
    );
    expect(observed.last.requireData, 'fresh');

    controller.dispose();
    await client.close();
  });

  testWidgets('listener sees no false ready to idle transition', (
    tester,
  ) async {
    final client = KacheClient(persistence: backend);
    final refresh = Completer<String>();
    final controller = KacheController<String>(
      client: client,
      query: query(refresh),
    );
    final transitions = <(KachePhase, KachePhase)>[];

    await tester.pumpWidget(
      KacheListener<String>(
        controller: controller,
        listener: (context, previous, current) =>
            transitions.add((previous.phase, current.phase)),
        child: const SizedBox(),
      ),
    );
    await tester.pump();
    refresh.complete('fresh');
    await tester.pump();
    await tester.pump();

    expect(
      transitions,
      everyElement(
        isA<(KachePhase, KachePhase)>().having(
          (transition) => transition.$2,
          'current phase',
          KachePhase.ready,
        ),
      ),
      reason: 'transitions $transitions',
    );
    expect(controller.value.requireData, 'fresh');

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await client.close();
  });

  testWidgets('first frame renders cache without replay rebuilds', (
    tester,
  ) async {
    final client = KacheClient(persistence: backend);
    final refresh = Completer<String>();
    final built = <String>[];

    await tester.pumpWidget(
      KacheScope(
        client: client,
        child: KacheBuilder<String>(
          query: query(refresh),
          builder: (context, snapshot, controller) {
            built.add(
              snapshot.hasData ? snapshot.requireData : snapshot.phase.name,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    // The core awaits the persistence read, so the first frame shows the
    // read in progress and the cached value lands before the next frame.
    expect(built, <String>['loading']);
    await tester.pump();
    expect(built, <String>['loading', 'cached']);

    await tester.pumpWidget(const SizedBox());
    await client.close();
  });

  testWidgets('buildWhen skips persistence-only rebuilds', (tester) async {
    final client = KacheClient(persistence: backend);
    final refresh = Completer<String>();
    final built = <String>[];
    final evaluated = <(int, int)>[];

    await tester.pumpWidget(
      KacheScope(
        client: client,
        child: KacheBuilder<String>(
          query: query(refresh),
          buildWhen: (previous, current) {
            evaluated.add((previous.revision, current.revision));
            return !previous.hasData ||
                !current.hasData ||
                !identical(previous.requireData, current.requireData) ||
                previous.isRefreshing != current.isRefreshing;
          },
          builder: (context, snapshot, controller) {
            built.add(
              snapshot.hasData
                  ? '${snapshot.requireData}:${snapshot.persistence?.phase.name}'
                  : snapshot.phase.name,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    refresh.complete('fresh');
    await tester.pump();
    await tester.pump();

    expect(evaluated, isNotEmpty);
    expect(built.last, startsWith('fresh:'));
    expect(
      built.where((entry) => entry.startsWith('fresh:')),
      hasLength(1),
      reason: 'the writing -> persisted change must not rebuild: $built',
    );

    await tester.pumpWidget(const SizedBox());
    await client.close();
  });

  testWidgets('buildWhen rebuilds from the accepted snapshot only', (
    tester,
  ) async {
    final client = KacheClient();
    final controllerQuery = KacheQuery<int>.memory(
      key: KacheKey('accepted'),
      policy: KachePolicy.cacheOnly(),
    );
    KacheController<int>? controller;
    final built = <int?>[];
    late StateSetter rebuildParent;

    await tester.pumpWidget(
      KacheScope(
        client: client,
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuildParent = setState;
            return KacheBuilder<int>(
              query: controllerQuery,
              buildWhen: (previous, current) =>
                  current.hasData && current.requireData.isEven,
              builder: (context, snapshot, active) {
                controller = active;
                built.add(snapshot.hasData ? snapshot.requireData : null);
                return const SizedBox();
              },
            );
          },
        ),
      ),
    );
    await tester.pump();
    final initialBuilds = built.length;

    await controller!.setData(1);
    await tester.pump();
    expect(built, hasLength(initialBuilds));

    rebuildParent(() {});
    await tester.pump();
    expect(built.last, isNot(1));

    await controller!.setData(2);
    await tester.pump();
    expect(built.last, 2);

    await tester.pumpWidget(const SizedBox());
    await client.close();
  });

  testWidgets('a key change always rebuilds despite buildWhen', (
    tester,
  ) async {
    final client = KacheClient();
    final cacheOnly = KachePolicy.cacheOnly();
    final first = KacheQuery<String>.memory(
      key: KacheKey('first'),
      policy: cacheOnly,
    );
    final second = KacheQuery<String>.memory(
      key: KacheKey('second'),
      policy: cacheOnly,
    );
    final firstResource = client.watch(first);
    await firstResource.setData('one');
    final secondResource = client.watch(second);
    await secondResource.setData('two');

    Widget build(KacheQuery<String> active) => KacheScope(
          client: client,
          child: KacheBuilder<String>(
            query: active,
            buildWhen: (previous, current) => false,
            builder: (context, snapshot, controller) => Text(
              snapshot.hasData ? snapshot.requireData : 'empty',
              textDirection: TextDirection.ltr,
            ),
          ),
        );

    await tester.pumpWidget(build(first));
    expect(find.text('one'), findsOneWidget);

    await tester.pumpWidget(build(second));
    await tester.pump();
    expect(find.text('two'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    firstResource.dispose();
    secondResource.dispose();
    await client.close();
  });
}
