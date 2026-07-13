import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 9);

  test('emits fetch lifecycle events to stream and observer', () async {
    final observed = <KacheEvent>[];
    final client = KacheClient(clock: () => now, observer: observed.add);
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('events'),
        debugName: 'profile',
        fetch: (_) async => 'Ada',
      ),
    );
    final streamed = <KacheEvent>[];
    final subscription = client.events.listen(streamed.add);

    await resource.refresh();

    expect(
      observed.map((event) => event.kind),
      containsAllInOrder(<KacheEventKind>[
        KacheEventKind.fetchStarted,
        KacheEventKind.fetchSucceeded,
      ]),
    );
    expect(
      streamed.map((event) => event.kind),
      containsAllInOrder(<KacheEventKind>[
        KacheEventKind.fetchStarted,
        KacheEventKind.fetchSucceeded,
      ]),
    );
    expect(observed.last.occurredAt, now);
    expect(observed.last.debugName, 'profile');
    expect(observed.last.key, resource.query.key);

    await subscription.cancel();
    resource.dispose();
    await client.close();
  });

  test('observer exceptions never alter cache results', () async {
    final client = KacheClient(
      clock: () => now,
      observer: (_) => throw StateError('observer failed'),
    );
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('observer'),
        fetch: (_) async => 'data',
      ),
    );

    final snapshot = await resource.refresh();

    expect(snapshot.requireData, 'data');
    resource.dispose();
    await client.close();
  });

  test('failure events preserve cause and stack trace', () async {
    final client = KacheClient(clock: () => now);
    final failureEvent = client.events.firstWhere(
      (event) => event.kind == KacheEventKind.failure,
    );
    final cause = StateError('offline');
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('failure-event'),
        fetch: (_) => Future<String>.error(cause, StackTrace.current),
      ),
    );

    await resource.refresh();
    final event = await failureEvent;

    expect(event.failure?.kind, KacheFailureKind.fetch);
    expect(event.failure?.cause, same(cause));
    expect(event.failure?.stackTrace, isNotNull);
    resource.dispose();
    await client.close();
  });

  test('event rendering excludes key, namespace, and failure payloads', () {
    const secret = 'secret-payload';
    final failure = KacheFailure(
      kind: KacheFailureKind.fetch,
      key: KacheKey('private', [secret]),
      cause: StateError(secret),
      stackTrace: StackTrace.current,
    );
    final event = KacheEvent(
      kind: KacheEventKind.failure,
      occurredAt: now,
      key: failure.key,
      failure: failure,
      debugName: 'safe-name',
    );

    expect(event.toString(), isNot(contains(secret)));
    expect(event.toString(), isNot(contains('private')));
    expect(event.toString(), contains('failure'));
  });

  test('clear events use namespace and global scopes', () async {
    final client = KacheClient(clock: () => now);
    final events = <KacheEvent>[];
    final subscription = client.events.listen(events.add);

    await client.clearNamespace(KacheNamespace('session'));
    await client.clear();

    final starts = events
        .where((event) => event.kind == KacheEventKind.clearStarted)
        .toList(growable: false);
    expect(starts, hasLength(2));
    expect(starts.first.namespace, KacheNamespace('session'));
    expect(starts.last.key, isNull);
    expect(starts.last.namespace, isNull);

    await subscription.cancel();
    await client.close();
  });

  test('client close emits lifecycle event and closes event stream', () async {
    final client = KacheClient(clock: () => now);
    final events = <KacheEvent>[];
    final done = Completer<void>();
    client.events.listen(events.add, onDone: done.complete);

    await client.close();
    await done.future;

    expect(events.last.kind, KacheEventKind.clientClosed);
  });
}
