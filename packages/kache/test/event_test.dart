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

  test('cache lookup events require an exact cache layer', () {
    final hit = KacheEvent(
      kind: KacheEventKind.cacheHit,
      occurredAt: now,
      key: KacheKey('lookup'),
      layer: KacheCacheLayer.memory,
    );

    expect(hit.layer, KacheCacheLayer.memory);
    expect(
      () => KacheEvent(
        kind: KacheEventKind.cacheMiss,
        occurredAt: now,
        key: KacheKey('lookup'),
      ),
      throwsArgumentError,
    );
    expect(
      () => KacheEvent(
        kind: KacheEventKind.cacheHit,
        occurredAt: now,
        layer: KacheCacheLayer.memory,
      ),
      throwsArgumentError,
    );
    expect(
      () => KacheEvent(
        kind: KacheEventKind.fetchStarted,
        occurredAt: now,
        key: KacheKey('lookup'),
        layer: KacheCacheLayer.persistence,
      ),
      throwsArgumentError,
    );
  });

  test('memory loads report misses and active-entry hits', () async {
    final events = <KacheEvent>[];
    final client = KacheClient(clock: () => now, observer: events.add);
    final query = KacheQuery<String>.memory(
      key: KacheKey('memory-lookup'),
      policy: KachePolicy.cacheFirst(freshFor: const Duration(hours: 1)),
      fetch: (_) async => 'value',
    );
    final first = client.watch(query);

    await first.load();
    final second = client.watch(query);
    await second.load();

    final lookups = events.where((event) => event.layer != null).toList();
    expect(
      lookups.map((event) => (event.kind, event.layer)),
      <(KacheEventKind, KacheCacheLayer?)>[
        (KacheEventKind.cacheMiss, KacheCacheLayer.memory),
        (KacheEventKind.cacheHit, KacheCacheLayer.memory),
      ],
    );
    expect(second.snapshot.source, KacheDataSource.fetch);
    first.dispose();
    second.dispose();
    await client.close();
  });

  test('persistence loads report hit and miss outcomes', () async {
    final backend = MemoryKachePersistence();
    final binding = backend.bind<String>(fingerprint: 'events-v1');
    final hitKey = KacheKey('persistence-lookup', ['hit']);
    await backend.write(
      key: hitKey,
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
    final policy = KachePolicy.cacheFirst(freshFor: const Duration(hours: 1));
    final hit = client.watch(
      KacheQuery<String>.persisted(
        key: hitKey,
        binding: binding,
        policy: policy,
        fetch: (_) async => 'network',
      ),
    );
    final miss = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('persistence-lookup', ['miss']),
        binding: binding,
        policy: policy,
        fetch: (_) async => 'network',
      ),
    );

    expect((await hit.load()).requireData, 'cached');
    expect((await miss.load()).requireData, 'network');

    final lookups = events.where((event) => event.layer != null).toList();
    expect(
      lookups.map((event) => (event.kind, event.layer)),
      <(KacheEventKind, KacheCacheLayer?)>[
        (KacheEventKind.cacheHit, KacheCacheLayer.persistence),
        (KacheEventKind.cacheMiss, KacheCacheLayer.persistence),
      ],
    );
    hit.dispose();
    miss.dispose();
    await client.close();
    await backend.close();
  });

  test(
    'hard-expired persistence reports expiry without a miss event',
    () async {
      final backend = MemoryKachePersistence();
      final binding = backend.bind<String>(fingerprint: 'expiry-v1');
      final key = KacheKey('expired-lookup');
      await backend.write(
        key: key,
        binding: binding,
        entry: KachePersistedEntry(
          data: 'expired',
          metadata: KachePersistedMetadata(
            fetchedAt: now.subtract(const Duration(minutes: 2)),
          ),
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
          policy: KachePolicy.cacheOnly(
            expireAfter: const Duration(minutes: 1),
          ),
        ),
      );

      expect((await resource.load()).isFailed, isTrue);

      final lookups = events.where((event) => event.layer != null).toList();
      expect(lookups, hasLength(1));
      expect(lookups.single.kind, KacheEventKind.cacheExpired);
      expect(lookups.single.layer, KacheCacheLayer.persistence);
      resource.dispose();
      await client.close();
      await backend.close();
    },
  );

  test('hard-expired active data reports a memory expiry', () async {
    var current = now;
    final events = <KacheEvent>[];
    final client = KacheClient(clock: () => current, observer: events.add);
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('expired-memory'),
        policy: KachePolicy.cacheFirst(
          freshFor: const Duration(minutes: 1),
          expireAfter: const Duration(minutes: 1),
        ),
        fetch: (_) async => 'value',
      ),
    );
    await resource.load();
    events.clear();
    current = current.add(const Duration(minutes: 2));

    await resource.load();

    final lookups = events.where((event) => event.layer != null).toList();
    expect(lookups, hasLength(1));
    expect(lookups.single.kind, KacheEventKind.cacheExpired);
    expect(lookups.single.layer, KacheCacheLayer.memory);
    resource.dispose();
    await client.close();
  });

  test('network-only loads do not emit cache lookup events', () async {
    final events = <KacheEvent>[];
    final client = KacheClient(clock: () => now, observer: events.add);
    final resource = client.watch(
      KacheQuery<String>.networkOnly(
        key: KacheKey('network-events'),
        fetch: (_) async => 'network',
      ),
    );

    await resource.load();

    expect(events.where((event) => event.layer != null), isEmpty);
    resource.dispose();
    await client.close();
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
