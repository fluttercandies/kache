import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

import 'support/scripted_persistence.dart';

void main() {
  test('drainWrites true waits for queued persistence work', () async {
    final backend = ScriptedPersistence();
    final writeStarted = Completer<void>();
    final writeGate = Completer<void>();
    backend.onWrite = (_) {
      writeStarted.complete();
      return writeGate.future;
    };
    final binding = backend.bind<String>(fingerprint: 'value-v1');
    final client = KacheClient(
      persistence: backend,
      persistenceOwnership: KachePersistenceOwnership.owned,
    );
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('drain'),
        binding: binding,
        fetch: (_) async => 'network',
      ),
    );
    final write = resource.setData('queued');
    await writeStarted.future;
    var didClose = false;

    final close = client.close();
    unawaited(close.then<void>((_) => didClose = true));
    await Future<void>.value();
    expect(didClose, isFalse);

    writeGate.complete();
    await write;
    await close;

    expect(backend.writeCount, 1);
    expect(backend.closeCount, 1);
  });

  test('drainWrites false skips work that has not started', () async {
    final backend = ScriptedPersistence();
    final firstStarted = Completer<void>();
    final firstGate = Completer<void>();
    backend.onWrite = (_) async {
      if (backend.writeCount == 1) {
        firstStarted.complete();
        await firstGate.future;
      }
    };
    final binding = backend.bind<String>(fingerprint: 'value-v1');
    final client = KacheClient(
      persistence: backend,
      persistenceOwnership: KachePersistenceOwnership.owned,
    );
    final resource = client.watch(
      KacheQuery<String>.persisted(
        key: KacheKey('discard'),
        binding: binding,
        fetch: (_) async => 'network',
      ),
    );
    final first = resource.setData('first');
    await firstStarted.future;
    final second = resource.setData('second');

    final close = client.close(drainWrites: false);
    firstGate.complete();
    await Future.wait(<Future<KacheSnapshot<String>>>[first, second]);
    await close;

    expect(backend.writeCount, 1);
    expect(backend.closeCount, 1);
  });

  test(
    'close cooperatively cancels fetch without waiting for its payload',
    () async {
      final cancellationObserved = Completer<void>();
      final client = KacheClient();
      final resource = client.watch(
        KacheQuery<String>.memory(
          key: KacheKey('cancel-fetch'),
          fetch: (context) async {
            await context.cancellation.whenCancelled;
            cancellationObserved.complete();
            context.throwIfCancelled();
            return 'unreachable';
          },
        ),
      );
      final refresh = resource.refresh();

      await client.close();
      await cancellationObserved.future;
      await refresh;

      expect(client.isClosed, isTrue);
    },
  );

  test('borrowed persistence is never closed by the client', () async {
    final backend = ScriptedPersistence();
    final client = KacheClient(persistence: backend);

    await client.close();

    expect(backend.closeCount, 0);
    expect(backend.isClosed, isFalse);
  });

  test('close is idempotent and the first drain mode wins', () async {
    final client = KacheClient();

    final first = client.close(drainWrites: false);
    final second = client.close();

    expect(second, same(first));
    await Future.wait(<Future<void>>[first, second]);
  });

  test('owned backend close waits for an active clear operation', () async {
    final backend = ScriptedPersistence();
    final clearStarted = Completer<void>();
    final clearGate = Completer<void>();
    var clearCompleted = false;
    backend.onClear = () async {
      clearStarted.complete();
      await clearGate.future;
      clearCompleted = true;
    };
    backend.onClose = () async => expect(clearCompleted, isTrue);
    final client = KacheClient(
      persistence: backend,
      persistenceOwnership: KachePersistenceOwnership.owned,
    );
    final clear = client.clear();
    await clearStarted.future;

    final close = client.close();
    expect(backend.closeCount, 0);

    clearGate.complete();
    await clear;
    await close;

    expect(backend.closeCount, 1);
  });
}
