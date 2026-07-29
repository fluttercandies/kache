import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

import 'support/scripted_persistence.dart';

void main() {
  final now = DateTime.utc(2026, 8, 9);

  test('fetch events expose trusted data after state commits', () async {
    const secret = 'private-profile';
    final value = _Value(secret);
    final observed = <KacheEvent>[];
    late KacheResource<_Value> resource;
    final client = KacheClient(
      id: 'profile-client',
      clock: () => now,
      observer: (event) {
        if (event.kind == KacheEventKind.fetch) {
          if (event.phase == KacheEventPhase.started) {
            expect(resource.snapshot.isLoading, isTrue);
          } else if (event.phase == KacheEventPhase.succeeded) {
            expect(resource.snapshot.requireData, same(value));
          }
        }
        observed.add(event);
      },
    );
    resource = client.watch(
      KacheQuery<_Value>.memory(
        key: KacheKey('profiles', <Object?>[secret]),
        debugName: 'profile',
        metadata: const <String, Object?>{'screen': secret},
        fetch: (_) async => value,
      ),
    );
    final streamed = <KacheEvent>[];
    final subscription = client.events.listen(streamed.add);

    await resource.refresh();

    final fetch =
        observed.where((event) => event.kind == KacheEventKind.fetch).toList();
    expect(fetch.map((event) => event.phase), <KacheEventPhase>[
      KacheEventPhase.started,
      KacheEventPhase.succeeded,
    ]);
    expect(fetch.first.id, fetch.last.id);
    expect(fetch.first.traceId, fetch.last.traceId);
    expect(fetch.first.parentId, isNull);
    expect(fetch.first.duration, isNull);
    expect(fetch.last.duration, isNotNull);
    expect(fetch.last.duration!.isNegative, isFalse);
    expect(fetch.last.clientId, 'profile-client');
    expect(fetch.last.trigger, KacheEventTrigger.refresh);
    expect(fetch.last.occurredAt, now);
    expect(fetch.last.revision, resource.snapshot.revision);
    expect(fetch.last.debugName, 'profile');
    expect(fetch.last.metadata, const <String, Object?>{'screen': secret});
    expect(() => fetch.last.metadata['other'] = 1, throwsUnsupportedError);
    expect(fetch.last.hasData, isTrue);
    expect(fetch.last.requireData<_Value>(), same(value));
    expect(fetch.first.hasData, isFalse);
    expect(() => fetch.first.requireData<_Value>(), throwsStateError);
    expect(fetch.last.toString(), isNot(contains(secret)));
    expect(fetch.last.toString(), isNot(contains('profiles')));
    expect(fetch.last.toString(), contains('hasData: true'));
    expect(
      observed.map((event) => event.sequence),
      orderedEquals(List<int>.generate(observed.length, (index) => index + 1)),
    );
    expect(streamed, hasLength(observed.length));
    for (var index = 0; index < observed.length; index += 1) {
      expect(streamed[index], same(observed[index]));
    }

    await subscription.cancel();
    resource.dispose();
    await client.close();
  });

  test('nullable success distinguishes data from absence', () async {
    final events = <KacheEvent>[];
    final client = KacheClient(observer: events.add);
    final resource = client.watch(
      KacheQuery<String?>.memory(
        key: KacheKey('nullable-event'),
        fetch: (_) async => null,
      ),
    );

    await resource.load();

    final lookup = events.singleWhere(
      (event) => event.kind == KacheEventKind.lookup,
    );
    final fetch = events.singleWhere(
      (event) =>
          event.kind == KacheEventKind.fetch &&
          event.phase == KacheEventPhase.succeeded,
    );
    expect(lookup.lookup, KacheLookupResult.miss);
    expect(lookup.hasData, isFalse);
    expect(fetch.hasData, isTrue);
    expect(fetch.dataOrNull, isNull);
    expect(fetch.requireData<String?>(), isNull);

    resource.dispose();
    await client.close();
  });

  test('the initiating same-key handle supplies event context', () async {
    final events = <KacheEvent>[];
    final client = KacheClient(observer: events.add);
    final key = KacheKey('handle-context');
    final first = client.watch(
      KacheQuery<int>.memory(
        key: key,
        debugName: 'first',
        metadata: const <String, Object?>{'owner': 1},
        policy: KachePolicy.cacheFirst(freshFor: const Duration(hours: 1)),
        fetch: (_) async => 1,
      ),
    );
    await first.load();
    events.clear();
    final second = client.watch(
      KacheQuery<int>.memory(
        key: key,
        debugName: 'second',
        metadata: const <String, Object?>{'owner': 2},
        policy: KachePolicy.cacheFirst(freshFor: const Duration(hours: 1)),
        fetch: (_) async => 1,
      ),
    );

    await second.load();

    final lookup = events.singleWhere(
      (event) => event.kind == KacheEventKind.lookup,
    );
    expect(lookup.debugName, 'second');
    expect(lookup.metadata, const <String, Object?>{'owner': 2});
    expect(lookup.requireData<int>(), 1);

    first.dispose();
    second.dispose();
    await client.close();
  });

  test('single-flight keeps initiator and waiter event contexts distinct',
      () async {
    final gate = Completer<int>();
    final events = <KacheEvent>[];
    final client = KacheClient(observer: events.add);
    final key = KacheKey('shared-handle-context');
    final first = client.watch(
      KacheQuery<int>.memory(
        key: key,
        debugName: 'initiator',
        metadata: const <String, Object?>{'owner': 1},
        fetch: (_) => gate.future,
      ),
    );
    final second = client.watch(
      KacheQuery<int>.memory(
        key: key,
        debugName: 'waiter',
        metadata: const <String, Object?>{'owner': 2},
        fetch: (_) => gate.future,
      ),
    );

    final firstLoad = first.load();
    await pumpEventQueue();
    final secondLoad = second.load();
    await pumpEventQueue();
    gate.complete(1);
    await Future.wait(<Future<KacheSnapshot<int>>>[firstLoad, secondLoad]);

    final fetch = events.where(
      (event) => event.kind == KacheEventKind.fetch,
    );
    expect(fetch, hasLength(2));
    expect(fetch.every((event) => event.debugName == 'initiator'), isTrue);
    expect(
      fetch.every(
        (event) => event.metadata.length == 1 && event.metadata['owner'] == 1,
      ),
      isTrue,
    );
    final waiterLookup = events.singleWhere(
      (event) =>
          event.kind == KacheEventKind.lookup && event.debugName == 'waiter',
    );
    expect(waiterLookup.metadata, const <String, Object?>{'owner': 2});
    expect(waiterLookup.lookup, KacheLookupResult.miss);
    expect(waiterLookup.traceId, isNot(fetch.first.traceId));
    _expectPairedSpans(events);

    first.dispose();
    second.dispose();
    await client.close();
  });

  test('persistence read waiters emit lookup traces with their own context',
      () async {
    final readStarted = Completer<void>();
    final readGate = Completer<void>();
    final backend = ScriptedPersistence()
      ..storedEntry = KachePersistedEntry<int>(
        data: 7,
        metadata: KachePersistedMetadata(fetchedAt: now),
      )
      ..onRead = () async {
        readStarted.complete();
        await readGate.future;
      };
    final binding = backend.bind<int>(fingerprint: 'waiter-context-v2');
    final events = <KacheEvent>[];
    final client = KacheClient(
      persistence: backend,
      clock: () => now,
      observer: events.add,
    );
    final key = KacheKey('persistence-waiter-context');
    final first = client.watch(
      KacheQuery<int>.persisted(
        key: key,
        binding: binding,
        debugName: 'reader',
        metadata: const <String, Object?>{'owner': 1},
        policy: KachePolicy.cacheOnly(),
      ),
    );
    final waiter = client.watch(
      KacheQuery<int>.persisted(
        key: key,
        binding: binding,
        debugName: 'waiter',
        metadata: const <String, Object?>{'owner': 2},
        policy: KachePolicy.cacheOnly(),
      ),
    );

    final firstLoad = first.load();
    await readStarted.future;
    final waiterLoad = waiter.load();
    readGate.complete();
    await Future.wait(<Future<KacheSnapshot<int>>>[firstLoad, waiterLoad]);

    final read = events.singleWhere(
      (event) =>
          event.kind == KacheEventKind.read &&
          event.phase == KacheEventPhase.started,
    );
    final waiterLookup = events.singleWhere(
      (event) =>
          event.kind == KacheEventKind.lookup && event.debugName == 'waiter',
    );
    expect(waiterLookup.layer, KacheLayer.memory);
    expect(waiterLookup.lookup, KacheLookupResult.hit);
    expect(waiterLookup.requireData<int>(), 7);
    expect(waiterLookup.metadata, const <String, Object?>{'owner': 2});
    expect(waiterLookup.traceId, isNot(read.traceId));

    first.dispose();
    waiter.dispose();
    await client.close();
    await backend.close();
  });

  test('persistence spans pair and preserve trace hierarchy', () async {
    final backend = MemoryKachePersistence();
    final binding = backend.bind<String>(fingerprint: 'events-v2');
    final key = KacheKey('persisted-events');
    await backend.write(
      key: key,
      binding: binding,
      entry: KachePersistedEntry(
        data: 'cached',
        metadata: KachePersistedMetadata(fetchedAt: now),
      ),
    );
    final events = <KacheEvent>[];
    final client = KacheClient(
      persistence: backend,
      clock: () => now,
      observer: events.add,
    );
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: key,
        binding: binding,
        policy: KachePolicy.cacheFirst(freshFor: const Duration(hours: 1)),
        fetch: (_) async => 'network',
      ),
    );

    expect((await resource.load()).requireData, 'cached');
    await resource.setData('manual');
    await resource.remove();

    _expectPairedSpans(events);
    final read = events.where((event) => event.kind == KacheEventKind.read);
    expect(read.map((event) => event.phase), <KacheEventPhase>[
      KacheEventPhase.started,
      KacheEventPhase.succeeded,
    ]);
    expect(read.last.requireData<String>(), 'cached');
    final hit = events.singleWhere(
      (event) =>
          event.kind == KacheEventKind.lookup &&
          event.lookup == KacheLookupResult.hit,
    );
    expect(hit.layer, KacheLayer.persistence);
    expect(hit.requireData<String>(), 'cached');

    final setTrace = events.singleWhere(
      (event) =>
          event.kind == KacheEventKind.set &&
          event.phase == KacheEventPhase.started,
    );
    expect(setTrace.id, setTrace.traceId);
    final write = events.where(
      (event) =>
          event.kind == KacheEventKind.write &&
          event.traceId == setTrace.traceId,
    );
    expect(write, hasLength(2));
    expect(write.first.parentId, setTrace.id);
    expect(write.last.requireData<String>(), 'manual');
    expect(
      events.any((event) => event.kind == KacheEventKind.delete),
      isTrue,
    );

    resource.dispose();
    await client.close();
    await backend.close();
  });

  test('memory lookup reports miss, hit, and expiry without leaked data',
      () async {
    var current = now;
    var fetches = 0;
    final events = <KacheEvent>[];
    final client = KacheClient(clock: () => current, observer: events.add);
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('lookup-events'),
        policy: KachePolicy.cacheFirst(
          freshFor: const Duration(minutes: 1),
          expireAfter: const Duration(minutes: 2),
        ),
        fetch: (_) async => ++fetches,
      ),
    );

    await resource.load();
    await resource.load();
    current = now.add(const Duration(minutes: 3));
    await resource.load();

    final lookups =
        events.where((event) => event.kind == KacheEventKind.lookup).toList();
    expect(
      lookups.map((event) => event.lookup),
      <KacheLookupResult>[
        KacheLookupResult.miss,
        KacheLookupResult.hit,
        KacheLookupResult.expired,
      ],
    );
    expect(lookups.every((event) => event.layer == KacheLayer.memory), isTrue);
    expect(lookups[1].requireData<int>(), 1);
    expect(lookups[0].hasData, isFalse);
    expect(lookups[2].hasData, isFalse);

    resource.dispose();
    await client.close();
  });

  test('failed operations retain original cause after snapshot commit',
      () async {
    final cause = StateError('offline-secret');
    final events = <KacheEvent>[];
    late KacheResource<String> resource;
    final client = KacheClient(observer: (event) {
      if (event.phase == KacheEventPhase.failed) {
        expect(resource.snapshot.failure, same(event.failure));
      }
      events.add(event);
    });
    resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('failure-event'),
        fetch: (_) => Future<String>.error(cause, StackTrace.current),
      ),
    );

    await resource.refresh();

    final failure = events.singleWhere(
      (event) => event.phase == KacheEventPhase.failed,
    );
    expect(failure.kind, KacheEventKind.fetch);
    expect(failure.failure?.cause, same(cause));
    expect(failure.failure?.stackTrace, isNotNull);
    expect(failure.toString(), isNot(contains('offline-secret')));
    _expectPairedSpans(events);

    resource.dispose();
    await client.close();
  });

  test('clear and close terminate before the event stream closes', () async {
    final events = <KacheEvent>[];
    final done = Completer<void>();
    final client = KacheClient(id: 'lifecycle-events');
    client.events.listen(events.add, onDone: done.complete);
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('clear-events'),
        fetch: (_) async => 1,
      ),
    );
    await resource.setData(1);

    await client.clearNamespace(KacheNamespace('clear-events'));
    await client.close();
    await done.future;

    _expectPairedSpans(events);
    final clear = events.where((event) => event.kind == KacheEventKind.clear);
    expect(clear.map((event) => event.phase), <KacheEventPhase>[
      KacheEventPhase.started,
      KacheEventPhase.succeeded,
    ]);
    expect(clear.last.scope, KacheFailureScope.namespace);
    expect(events.last.kind, KacheEventKind.close);
    expect(events.last.phase, KacheEventPhase.succeeded);
  });

  test('clear failure terminates its span and leaves commands available',
      () async {
    final backend = ScriptedPersistence();
    final binding = backend.bind<int>(fingerprint: 'clear-events-v2');
    final cause = StateError('clear-secret');
    backend.onClear = () async => throw cause;
    final events = <KacheEvent>[];
    final client = KacheClient(persistence: backend, observer: events.add);
    final resource = client.watch(
      KacheQuery<int>.persisted(
        key: KacheKey('clear-failure-events'),
        binding: binding,
        policy: KachePolicy.cacheOnly(),
      ),
    );
    await resource.setData(1);

    final result = await client.clear();

    expect(result.failures, hasLength(1));
    expect(result.failures.single.cause, same(cause));
    final clear = events.where(
      (event) => event.kind == KacheEventKind.clear,
    );
    expect(clear.map((event) => event.phase), <KacheEventPhase>[
      KacheEventPhase.started,
      KacheEventPhase.failed,
    ]);
    expect(clear.last.failure, same(result.failures.single));
    expect(clear.last.toString(), isNot(contains('clear-secret')));
    _expectPairedSpans(events);
    expect((await resource.remove()).phase, KachePhase.idle);

    resource.dispose();
    await client.close();
    await backend.close();
  });

  test('observer exceptions never alter results or stream delivery', () async {
    final client = KacheClient(observer: (_) => throw StateError('observer'));
    final streamed = <KacheEvent>[];
    final subscription = client.events.listen(streamed.add);
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('observer-isolation'),
        fetch: (_) async => 'data',
      ),
    );

    expect((await resource.refresh()).requireData, 'data');
    expect(streamed, isNotEmpty);

    await subscription.cancel();
    resource.dispose();
    await client.close();
  });

  test('owned persistence close failure terminates child and client spans',
      () async {
    final backend = ScriptedPersistence();
    final cause = StateError('close-secret');
    backend.onClose = () async => throw cause;
    final events = <KacheEvent>[];
    final client = KacheClient(
      persistence: backend,
      persistenceOwnership: KachePersistenceOwnership.owned,
    );
    client.events.listen(events.add);

    await expectLater(
        client.close(), throwsA(isA<KachePersistenceException>()));

    final closeEvents =
        events.where((event) => event.kind == KacheEventKind.close).toList();
    _expectPairedSpans(closeEvents);
    final dependency = closeEvents.singleWhere(
      (event) =>
          event.layer == KacheLayer.persistence &&
          event.phase == KacheEventPhase.failed,
    );
    expect(dependency.failure?.kind, KacheFailureKind.persistenceClose);
    expect(dependency.failure?.cause, same(cause));
    expect(dependency.toString(), isNot(contains('close-secret')));
    expect(closeEvents.last.layer, isNull);
    expect(closeEvents.last.phase, KacheEventPhase.failed);
    expect(closeEvents.last.failure, same(dependency.failure));
  });

  test('owned persistence and network close spans pair before client close',
      () async {
    final backend = ScriptedPersistence();
    final network = _EventNetwork();
    final events = <KacheEvent>[];
    final client = KacheClient(
      persistence: backend,
      persistenceOwnership: KachePersistenceOwnership.owned,
      network: network,
      networkOwnership: KacheNetworkOwnership.owned,
    );
    client.events.listen(events.add);

    await client.close();

    final closeEvents = events
        .where(
          (event) => event.kind == KacheEventKind.close,
        )
        .toList();
    _expectPairedSpans(closeEvents);
    expect(
      closeEvents
          .where((event) => event.phase == KacheEventPhase.started)
          .map((event) => event.layer),
      <KacheLayer?>[null, KacheLayer.persistence, KacheLayer.network],
    );
    expect(closeEvents.last.layer, isNull);
    expect(closeEvents.last.phase, KacheEventPhase.succeeded);
    expect(backend.closeCount, 1);
    expect(network.closeCount, 1);
  });
}

void _expectPairedSpans(List<KacheEvent> events) {
  for (final started
      in events.where((event) => event.phase == KacheEventPhase.started)) {
    final terminal = events.where(
      (event) =>
          event.clientId == started.clientId &&
          event.id == started.id &&
          event.phase != KacheEventPhase.started,
    );
    expect(terminal, hasLength(1), reason: '${started.kind} ${started.id}');
  }
}

final class _Value {
  const _Value(this.secret);

  final String secret;

  @override
  String toString() => secret;
}

final class _EventNetwork implements KacheNetwork {
  final StreamController<KacheNetworkState> _states =
      StreamController<KacheNetworkState>.broadcast(sync: true);
  int closeCount = 0;

  @override
  Stream<KacheNetworkState> get states => _states.stream;

  @override
  Future<void> close() async {
    closeCount += 1;
    await _states.close();
  }
}
