import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache/kache.dart';
import 'package:kache_flutter/kache_flutter.dart';

void main() {
  testWidgets('renders persisted data before slow refresh', (tester) async {
    final backend = MemoryKachePersistence();
    final binding = backend.bind<String>(fingerprint: 'profile-v1');
    final key = KacheKey('profile');
    await backend.write<String>(
      key: key,
      binding: binding,
      entry: KachePersistedEntry<String>(
        data: 'cached',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2025)),
      ),
    );
    final refresh = Completer<String>();
    final client = KacheClient(persistence: backend);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: KacheScope(
          client: client,
          child: KacheBuilder<String>(
            query: KacheQuery<String>.persisted(
              key: key,
              binding: binding,
              fetch: (_) => refresh.future,
            ),
            builder: (context, snapshot, controller) => Text(
              snapshot.hasData ? snapshot.requireData : snapshot.phase.name,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('cached'), findsOneWidget);
    expect(refresh.isCompleted, isFalse);

    refresh.complete('fresh');
    await tester.pump();
    await tester.pump();
    expect(find.text('fresh'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await client.close();
  });

  testWidgets('same-key rebuild updates fetcher without duplicate load', (
    tester,
  ) async {
    final client = KacheClient();
    final key = KacheKey('same-key');
    var firstFetches = 0;
    var secondFetches = 0;
    late KacheController<String> controller;

    Widget build(KacheQuery<String> query) => Directionality(
      textDirection: TextDirection.ltr,
      child: KacheScope(
        client: client,
        child: KacheBuilder<String>(
          query: query,
          builder: (context, snapshot, value) {
            controller = value;
            return Text(snapshot.dataOrNull ?? 'empty');
          },
        ),
      ),
    );

    await tester.pumpWidget(
      build(
        KacheQuery<String>.memory(
          key: key,
          fetch: (_) async {
            firstFetches += 1;
            return 'first';
          },
        ),
      ),
    );
    await tester.pump();
    expect(firstFetches, 1);

    await tester.pumpWidget(
      build(
        KacheQuery<String>.memory(
          key: key,
          fetch: (_) async {
            secondFetches += 1;
            return 'second';
          },
        ),
      ),
    );
    await tester.pump();

    expect(secondFetches, 0);
    await controller.refresh();
    await tester.pump();
    expect(secondFetches, 1);
    expect(find.text('second'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await client.close();
  });

  testWidgets('key change releases old handle and renders new data', (
    tester,
  ) async {
    final client = KacheClient();

    Widget build(String key, String value) => Directionality(
      textDirection: TextDirection.ltr,
      child: KacheScope(
        client: client,
        child: KacheBuilder<String>(
          query: KacheQuery<String>.memory(
            key: KacheKey(key),
            fetch: (_) async => value,
          ),
          builder: (context, snapshot, controller) =>
              Text(snapshot.dataOrNull ?? 'empty'),
        ),
      ),
    );

    await tester.pumpWidget(build('first', 'one'));
    await tester.pump();
    expect(find.text('one'), findsOneWidget);

    await tester.pumpWidget(build('second', 'two'));
    await tester.pump();
    expect(find.text('two'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await client.close();
  });

  testWidgets('pending fetch after dispose causes no late widget update', (
    tester,
  ) async {
    final fetch = Completer<String>();
    final client = KacheClient();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: KacheScope(
          client: client,
          child: KacheBuilder<String>(
            query: KacheQuery<String>.memory(
              key: KacheKey('pending-dispose'),
              fetch: (_) => fetch.future,
            ),
            builder: (context, snapshot, controller) =>
                Text(snapshot.phase.name),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    fetch.complete('late');
    await tester.pump();

    expect(tester.takeException(), isNull);
    await client.close();
  });
}
