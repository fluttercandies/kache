import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

import 'support/scripted_persistence.dart';

void main() {
  test('manual cancel completes immediately and isolates a late success',
      () async {
    final response = Completer<String>();
    final events = <KacheEvent>[];
    final client = KacheClient(observer: events.add);
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('cancel-late-success'),
        fetch: (_) => response.future,
      ),
    );
    final refresh = resource.refresh();
    await pumpEventQueue();
    expect(resource.snapshot.isLoading, isTrue);

    expect(resource.cancel(), isTrue);
    final cancelled = await refresh.timeout(const Duration(seconds: 1));

    expect(cancelled.phase, KachePhase.idle);
    expect(cancelled.revision, 2);
    expect(resource.cancel(), isFalse);
    final event = events.singleWhere(
      (event) => event.phase == KacheEventPhase.cancelled,
    );
    expect(event.kind, KacheEventKind.fetch);
    expect(event.cancelReason, KacheCancelReason.manual);
    expect(event.failure, isNull);
    expect(event.hasData, isFalse);

    response.complete('late');
    await response.future;
    await pumpEventQueue();
    expect(resource.snapshot.phase, KachePhase.idle);
    expect(
      events.where(
        (event) =>
            event.kind == KacheEventKind.fetch &&
            event.phase == KacheEventPhase.succeeded,
      ),
      isEmpty,
    );

    resource.dispose();
    await client.close();
  });

  test('late fetch errors are consumed after logical cancellation', () async {
    final response = Completer<int>();
    final events = <KacheEvent>[];
    final client = KacheClient(observer: events.add);
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('cancel-late-error'),
        fetch: (_) => response.future,
      ),
    );
    final refresh = resource.refresh();
    await pumpEventQueue();

    expect(client.cancel(resource.key), isTrue);
    await refresh;
    response.completeError(StateError('late-error'), StackTrace.current);
    await pumpEventQueue();

    expect(resource.snapshot.failure, isNull);
    expect(
      events.where((event) => event.phase == KacheEventPhase.failed),
      isEmpty,
    );

    resource.dispose();
    await client.close();
  });

  test('manual cancel restores all visible stale-data state', () async {
    var fetches = 0;
    final pending = Completer<int>();
    final client = KacheClient();
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('cancel-restore'),
        fetch: (_) {
          fetches += 1;
          if (fetches == 1) {
            throw StateError('refresh failed');
          }
          return pending.future;
        },
      ),
    );
    await resource.setData(7);
    final failed = await resource.refresh();
    expect(failed.failure?.kind, KacheFailureKind.fetch);
    final fetchedAt = failed.fetchedAt;
    final source = failed.source;
    final failure = failed.failure;

    final refresh = resource.refresh();
    await pumpEventQueue();
    expect(resource.snapshot.isRefreshing, isTrue);
    expect(resource.snapshot.failure, isNull);
    expect(resource.cancel(), isTrue);
    final restored = await refresh;

    expect(restored.requireData, 7);
    expect(restored.isRefreshing, isFalse);
    expect(restored.freshness, KacheFreshness.stale);
    expect(restored.fetchedAt, fetchedAt);
    expect(restored.source, source);
    expect(restored.failure, same(failure));

    pending.complete(8);
    await pending.future;
    await pumpEventQueue();
    expect(resource.snapshot.requireData, 7);
    resource.dispose();
    await client.close();
  });

  test('same-key handles share cancellation and cancelAll counts keys',
      () async {
    final firstGate = Completer<int>();
    final secondGate = Completer<int>();
    final client = KacheClient();
    final query = KacheQuery<int>.memory(
      key: KacheKey('shared-cancel'),
      fetch: (_) => firstGate.future,
    );
    final first = client.watch(query);
    final second = client.watch(query);
    final firstRefresh = first.refresh();
    final secondRefresh = second.refresh();
    await pumpEventQueue();

    expect(second.cancel(), isTrue);
    expect((await firstRefresh).phase, KachePhase.idle);
    expect((await secondRefresh).phase, KachePhase.idle);

    final third = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('other-cancel'),
        fetch: (_) => secondGate.future,
      ),
    );
    final restarted = first.refresh();
    final other = third.refresh();
    await pumpEventQueue();
    expect(client.cancelAll(), 2);
    await Future.wait(<Future<KacheSnapshot<int>>>[restarted, other]);
    expect(client.cancelAll(), 0);

    firstGate.complete(1);
    secondGate.complete(2);
    await pumpEventQueue();
    first.dispose();
    second.dispose();
    third.dispose();
    await client.close();
  });

  test('fetchers receive the exact cancellation reason', () async {
    final reason = Completer<KacheCancelReason>();
    final client = KacheClient();
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('cooperative-cancel'),
        fetch: (context) async {
          reason.complete(await context.cancellation.whenCancelled);
          context.throwIfCancelled();
          return 1;
        },
      ),
    );
    final refresh = resource.refresh();
    await pumpEventQueue();

    await resource.setData(2);

    expect(await reason.future, KacheCancelReason.dataSet);
    expect((await refresh).requireData, 2);
    expect(resource.snapshot.requireData, 2);
    resource.dispose();
    await client.close();
  });

  test('cancel returns false after fetched data is accepted', () async {
    final backend = ScriptedPersistence();
    final binding = backend.bind<int>(fingerprint: 'cancel-write-v2');
    final writeStarted = Completer<void>();
    final writeGate = Completer<void>();
    backend.onWrite = (_) async {
      writeStarted.complete();
      await writeGate.future;
    };
    final client = KacheClient(persistence: backend);
    final resource = client.watch(
      KacheQuery<int>.persisted(
        key: KacheKey('accepted-data'),
        binding: binding,
        fetch: (_) async => 1,
      ),
    );
    final refresh = resource.refresh();
    await writeStarted.future;

    expect(resource.snapshot.requireData, 1);
    expect(resource.cancel(), isFalse);
    writeGate.complete();
    expect((await refresh).requireData, 1);

    resource.dispose();
    await client.close();
    await backend.close();
  });

  test('commands expose precise fetch cancellation reasons', () async {
    expect(
      await _cancelReasonFor((resource, client) => resource.setData(1)),
      KacheCancelReason.dataSet,
    );
    expect(
      await _cancelReasonFor(
        (resource, client) => resource.invalidate(refetch: false),
      ),
      KacheCancelReason.invalidate,
    );
    expect(
      await _cancelReasonFor((resource, client) => resource.remove()),
      KacheCancelReason.remove,
    );
    expect(
      await _cancelReasonFor((resource, client) => client.clear()),
      KacheCancelReason.clear,
    );
    expect(
      await _cancelReasonFor((resource, client) => client.close()),
      KacheCancelReason.close,
    );
  });

  test('started read and write spans terminate when superseded', () async {
    final backend = ScriptedPersistence();
    final binding = backend.bind<int>(fingerprint: 'operation-cancel-v2');
    final readStarted = Completer<void>();
    final readGate = Completer<void>();
    backend.onRead = () async {
      readStarted.complete();
      await readGate.future;
    };
    final events = <KacheEvent>[];
    final client = KacheClient(persistence: backend, observer: events.add);
    final resource = client.watch(
      KacheQuery<int>.persisted(
        key: KacheKey('read-cancel'),
        binding: binding,
        policy: KachePolicy.cacheOnly(),
      ),
    );
    final load = resource.load();
    await readStarted.future;

    await resource.setData(1);
    await load;
    final cancelledRead = events.singleWhere(
      (event) =>
          event.kind == KacheEventKind.read &&
          event.phase == KacheEventPhase.cancelled,
    );
    expect(cancelledRead.cancelReason, KacheCancelReason.dataSet);

    readGate.complete();
    await pumpEventQueue();
    final writeStarted = Completer<void>();
    final writeGate = Completer<void>();
    backend.onWrite = (_) async {
      if (!writeStarted.isCompleted) {
        writeStarted.complete();
        await writeGate.future;
      }
    };
    final firstWrite = resource.setData(2);
    await writeStarted.future;
    final secondWrite = resource.setData(3);
    writeGate.complete();
    await Future.wait(<Future<KacheSnapshot<int>>>[firstWrite, secondWrite]);

    final cancelledWrite = events.singleWhere(
      (event) =>
          event.kind == KacheEventKind.write &&
          event.phase == KacheEventPhase.cancelled,
    );
    expect(cancelledWrite.cancelReason, KacheCancelReason.dataSet);
    expect(resource.snapshot.requireData, 3);

    resource.dispose();
    await client.close();
    await backend.close();
  });

  test('clear cancels a started persistence read with its exact reason',
      () async {
    final backend = ScriptedPersistence();
    final binding = backend.bind<int>(fingerprint: 'clear-read-v2');
    final readStarted = Completer<void>();
    final readGate = Completer<void>();
    backend.onRead = () async {
      readStarted.complete();
      await readGate.future;
    };
    final events = <KacheEvent>[];
    final client = KacheClient(persistence: backend, observer: events.add);
    final resource = client.watch(
      KacheQuery<int>.persisted(
        key: KacheKey('clear-read-cancel'),
        binding: binding,
        policy: KachePolicy.cacheOnly(),
      ),
    );
    final load = resource.load();
    await readStarted.future;

    expect((await client.clear()).isSuccess, isTrue);
    await load;

    final read = events.where(
      (event) => event.kind == KacheEventKind.read,
    );
    expect(read.map((event) => event.phase), <KacheEventPhase>[
      KacheEventPhase.started,
      KacheEventPhase.cancelled,
    ]);
    expect(read.last.cancelReason, KacheCancelReason.clear);
    _expectStartedSpansTerminate(events);

    readGate.complete();
    await pumpEventQueue();
    resource.dispose();
    await client.close();
    await backend.close();
  });

  test('setData supersedes a started delete and persists the new value',
      () async {
    final backend = ScriptedPersistence();
    final binding = backend.bind<int>(fingerprint: 'delete-cancel-v2');
    final deleteStarted = Completer<void>();
    final deleteGate = Completer<void>();
    final events = <KacheEvent>[];
    final client = KacheClient(persistence: backend, observer: events.add);
    final resource = client.watch(
      KacheQuery<int>.persisted(
        key: KacheKey('delete-cancel'),
        binding: binding,
        policy: KachePolicy.cacheOnly(),
      ),
    );
    await resource.setData(1);
    events.clear();
    backend.onDelete = () async {
      deleteStarted.complete();
      await deleteGate.future;
    };

    final remove = resource.remove();
    await deleteStarted.future;
    final replacement = resource.setData(2);
    deleteGate.complete();
    await Future.wait(<Future<KacheSnapshot<int>>>[remove, replacement]);

    final delete = events.where(
      (event) => event.kind == KacheEventKind.delete,
    );
    expect(delete.map((event) => event.phase), <KacheEventPhase>[
      KacheEventPhase.started,
      KacheEventPhase.cancelled,
    ]);
    expect(delete.last.cancelReason, KacheCancelReason.dataSet);
    expect(
      (backend.storedEntry as KachePersistedEntry<int>).data,
      2,
    );
    expect(resource.snapshot.requireData, 2);
    _expectStartedSpansTerminate(events);

    resource.dispose();
    await client.close();
    await backend.close();
  });

  test('non-draining close cancels a started write with its exact reason',
      () async {
    final backend = ScriptedPersistence();
    final binding = backend.bind<int>(fingerprint: 'close-active-write-v2');
    final writeStarted = Completer<void>();
    final writeGate = Completer<void>();
    backend.onWrite = (_) async {
      writeStarted.complete();
      await writeGate.future;
    };
    final events = <KacheEvent>[];
    final client = KacheClient(persistence: backend, observer: events.add);
    final resource = client.watch(
      KacheQuery<int>.persisted(
        key: KacheKey('close-active-write-cancel'),
        binding: binding,
        policy: KachePolicy.cacheOnly(),
      ),
    );
    final write = resource.setData(1);
    await writeStarted.future;

    final close = client.close(drainWrites: false);
    writeGate.complete();
    await write;
    await close;

    final writes = events.where(
      (event) => event.kind == KacheEventKind.write,
    );
    expect(writes.map((event) => event.phase), <KacheEventPhase>[
      KacheEventPhase.started,
      KacheEventPhase.cancelled,
    ]);
    expect(writes.last.cancelReason, KacheCancelReason.close);
    _expectStartedSpansTerminate(events);
    await backend.close();
  });

  test('non-draining close skips a queued write before its span starts',
      () async {
    final backend = ScriptedPersistence();
    final binding = backend.bind<int>(fingerprint: 'close-write-v2');
    final writeStarted = Completer<void>();
    final writeGate = Completer<void>();
    backend.onWrite = (_) async {
      if (!writeStarted.isCompleted) {
        writeStarted.complete();
        await writeGate.future;
      }
    };
    final events = <KacheEvent>[];
    final client = KacheClient(persistence: backend, observer: events.add);
    final resource = client.watch(
      KacheQuery<int>.persisted(
        key: KacheKey('close-write-cancel'),
        binding: binding,
        policy: KachePolicy.cacheOnly(),
      ),
    );
    final first = resource.setData(1);
    await writeStarted.future;
    final second = resource.setData(2);

    final close = client.close(drainWrites: false);
    writeGate.complete();
    await Future.wait(<Future<KacheSnapshot<int>>>[first, second]);
    await close;

    final writes = events.where(
      (event) => event.kind == KacheEventKind.write,
    );
    expect(writes.map((event) => event.phase), <KacheEventPhase>[
      KacheEventPhase.started,
      KacheEventPhase.cancelled,
    ]);
    expect(writes.last.cancelReason, KacheCancelReason.dataSet);
    expect(backend.writeCount, 1);
    _expectStartedSpansTerminate(events);
    await backend.close();
  });

  test('disposing a handle does not cancel its shared fetch', () async {
    final gate = Completer<int>();
    late KacheCancellationToken token;
    final client = KacheClient();
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('dispose-no-cancel'),
        fetch: (context) {
          token = context.cancellation;
          return gate.future;
        },
      ),
    );
    final refresh = resource.refresh();
    await pumpEventQueue();

    resource.dispose();
    expect(token.isCancelled, isFalse);
    gate.complete(1);
    expect((await refresh).requireData, 1);
    await client.close();
  });
}

void _expectStartedSpansTerminate(List<KacheEvent> events) {
  for (final started
      in events.where((event) => event.phase == KacheEventPhase.started)) {
    expect(
      events.where(
        (event) =>
            event.clientId == started.clientId &&
            event.id == started.id &&
            event.phase != KacheEventPhase.started,
      ),
      hasLength(1),
      reason: '${started.kind.name} ${started.id}',
    );
  }
}

Future<KacheCancelReason> _cancelReasonFor(
  FutureOr<Object?> Function(KacheResource<int>, KacheClient) command,
) async {
  final gate = Completer<int>();
  final events = <KacheEvent>[];
  final client = KacheClient(observer: events.add);
  final resource = client.watch(
    KacheQuery<int>.memory(
      key: KacheKey('reason-${command.hashCode}'),
      fetch: (_) => gate.future,
    ),
  );
  final refresh = resource.refresh();
  await pumpEventQueue();
  await command(resource, client);
  await refresh;
  final cancelled = events.singleWhere(
    (event) =>
        event.kind == KacheEventKind.fetch &&
        event.phase == KacheEventPhase.cancelled,
  );
  if (!client.isClosed) {
    resource.dispose();
    await client.close();
  }
  gate.complete(1);
  await pumpEventQueue();
  return cancelled.cancelReason!;
}
