import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

import 'support/scripted_persistence.dart';

void main() {
  final now = DateTime.utc(2026, 6, 7);

  test('coalesces highly concurrent refresh calls for one key', () async {
    final fetch = Completer<int>();
    var fetchCount = 0;
    final client = KacheClient(clock: () => now);
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('single-flight'),
        fetch: (_) {
          fetchCount += 1;
          return fetch.future;
        },
      ),
    );

    final refreshes = List<Future<KacheSnapshot<int>>>.generate(
      100,
      (_) => resource.refresh(),
    );
    expect(fetchCount, 1);

    fetch.complete(42);
    final snapshots = await Future.wait(refreshes);

    expect(snapshots.every((snapshot) => snapshot.requireData == 42), isTrue);
    resource.dispose();
    await client.close();
  });

  test(
    'setData prevents an older fetch from overwriting manual data',
    () async {
      final firstFetch = Completer<String>();
      final client = KacheClient(clock: () => now);
      final resource = client.watch(
        KacheQuery<String>.memory(
          key: KacheKey('generation-set'),
          fetch: (_) => firstFetch.future,
        ),
      );
      final refresh = resource.refresh();

      final manual = await resource.setData('manual');
      firstFetch.complete('obsolete');
      await refresh;

      expect(manual.requireData, 'manual');
      expect(resource.snapshot.requireData, 'manual');
      expect(resource.snapshot.source, KacheDataSource.manual);

      resource.dispose();
      await client.close();
    },
  );

  test('invalidate cancels and isolates an older fetch result', () async {
    final oldFetch = Completer<String>();
    final client = KacheClient(clock: () => now);
    var fetchCount = 0;
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('generation-invalidate'),
        fetch: (context) {
          fetchCount += 1;
          if (fetchCount == 1) {
            return Future<String>.value('cached');
          }
          return oldFetch.future;
        },
      ),
    );
    await resource.load();
    final refresh = resource.refresh();

    final invalidated = await resource.invalidate(refetch: false);
    oldFetch.complete('obsolete');
    await refresh;

    expect(invalidated.requireData, 'cached');
    expect(resource.snapshot.requireData, 'cached');
    expect(resource.snapshot.freshness, KacheFreshness.stale);

    resource.dispose();
    await client.close();
  });

  test('remove prevents an older fetch from reviving data', () async {
    final oldFetch = Completer<String>();
    final client = KacheClient(clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('generation-remove'),
        fetch: (_) => oldFetch.future,
      ),
    );
    final refresh = resource.refresh();

    final removed = await resource.remove();
    oldFetch.complete('obsolete');
    await refresh;

    expect(removed.phase, KachePhase.idle);
    expect(resource.snapshot.hasData, isFalse);

    resource.dispose();
    await client.close();
  });

  test('serializes writes and leaves the newest value persisted', () async {
    final backend = ScriptedPersistence();
    final firstWrite = Completer<void>();
    final firstWriteStarted = Completer<void>();
    var activeWrites = 0;
    var maximumActiveWrites = 0;
    backend.onWrite = (_) async {
      activeWrites += 1;
      maximumActiveWrites = activeWrites > maximumActiveWrites
          ? activeWrites
          : maximumActiveWrites;
      if (backend.writeCount == 1) {
        firstWriteStarted.complete();
        await firstWrite.future;
      }
      activeWrites -= 1;
    };
    final binding = backend.bind<String>(fingerprint: 'value-v1');
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('write-order'),
        binding: binding,
        fetch: (_) async => 'network',
      ),
    );

    final first = resource.setData('first');
    await firstWriteStarted.future;
    final second = resource.setData('second');
    firstWrite.complete();
    await Future.wait(<Future<KacheSnapshot<String>>>[first, second]);

    expect(maximumActiveWrites, 1);
    expect((backend.storedEntry as KachePersistedEntry<String>).data, 'second');

    resource.dispose();
    await client.close();
  });

  test('namespace clear is a barrier against queued writes', () async {
    final backend = ScriptedPersistence();
    final writeGate = Completer<void>();
    final writeStarted = Completer<void>();
    backend.onWrite = (_) {
      writeStarted.complete();
      return writeGate.future;
    };
    final binding = backend.bind<String>(fingerprint: 'value-v1');
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('session', [1]),
        binding: binding,
        fetch: (_) async => 'network',
      ),
    );
    final write = resource.setData('private');
    await writeStarted.future;

    final clear = client.clearNamespace(KacheNamespace('session'));
    writeGate.complete();
    await write;
    final result = await clear;

    expect(result.isSuccess, isTrue);
    expect(backend.storedEntry, isNull);
    expect(resource.snapshot.hasData, isFalse);

    resource.dispose();
    await client.close();
  });

  test('overlapping clears defer refetch until the last clear', () async {
    final backend = ScriptedPersistence();
    final firstClearStarted = Completer<void>();
    final firstClearGate = Completer<void>();
    backend.onClear = () async {
      if (backend.clearCount == 1) {
        firstClearStarted.complete();
        await firstClearGate.future;
      }
    };
    final binding = backend.bind<String>(fingerprint: 'clear-race-v1');
    var fetches = 0;
    final client = KacheClient(persistence: backend, clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('overlapping-clear'),
        binding: binding,
        fetch: (_) async => 'network-${++fetches}',
      ),
    );
    await resource.setData('cached');

    final first = client.clear(refetch: true);
    await firstClearStarted.future;
    final second = client.clear(refetch: true);
    firstClearGate.complete();

    expect((await first).isSuccess, isTrue);
    expect((await second).isSuccess, isTrue);
    expect(fetches, 1);
    expect(resource.snapshot.requireData, 'network-1');
    resource.dispose();
    await client.close();
  });

  test('namespace clear leaves other namespace memory intact', () async {
    final client = KacheClient(clock: () => now);
    final session = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('session'),
        fetch: (_) async => 'session',
      ),
    );
    final public = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('public'),
        fetch: (_) async => 'public',
      ),
    );
    await Future.wait(<Future<KacheSnapshot<String>>>[
      session.setData('private'),
      public.setData('visible'),
    ]);

    await client.clearNamespace(KacheNamespace('session'));

    expect(session.snapshot.hasData, isFalse);
    expect(public.snapshot.requireData, 'visible');

    session.dispose();
    public.dispose();
    await client.close();
  });

  test('global clear prevents an older fetch from reviving data', () async {
    final fetch = Completer<String>();
    final client = KacheClient(clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('global-clear'),
        fetch: (_) => fetch.future,
      ),
    );
    final refresh = resource.refresh();

    await client.clear();
    fetch.complete('obsolete');
    await refresh;

    expect(resource.snapshot.hasData, isFalse);
    resource.dispose();
    await client.close();
  });
}
