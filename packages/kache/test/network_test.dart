import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  test('reconnect revalidates active handles according to policy', () async {
    final network = _FakeNetwork();
    final events = <KacheEvent>[];
    final client = KacheClient(network: network, observer: events.add);
    var fetches = 0;
    final active = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('network-active'),
        policy: KachePolicy.staleWhileRevalidate(
          refreshOnLoad: KacheRevalidation.never,
        ),
        fetch: (_) async => 'network-${++fetches}',
      ),
    );
    final cacheOnly = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('network-cache-only'),
        policy: KachePolicy.cacheOnly(),
      ),
    );
    await active.setData('cached');
    await cacheOnly.setData('offline');

    network.emit(KacheNetworkState.available);
    await pumpEventQueue();
    expect(fetches, 0);

    network.emit(KacheNetworkState.unavailable);
    final completed = client.events.firstWhere(
      (event) => event.kind == KacheEventKind.reconnectCompleted,
    );
    network.emit(KacheNetworkState.available);
    await completed;

    expect(fetches, 1);
    expect(active.snapshot.requireData, 'network-1');
    expect(cacheOnly.snapshot.requireData, 'offline');
    expect(cacheOnly.snapshot.failure, isNull);
    expect(
      events.where((event) => event.kind == KacheEventKind.reconnectStarted),
      hasLength(1),
    );
    active.dispose();
    cacheOnly.dispose();
    await client.close();
  });

  test('pause coalesces a reconnect until resume', () async {
    final network = _FakeNetwork();
    final client = KacheClient(network: network);
    var fetches = 0;
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('network-paused'),
        policy: KachePolicy.staleWhileRevalidate(
          refreshOnLoad: KacheRevalidation.never,
        ),
        fetch: (_) async => ++fetches,
      ),
    );
    network.emit(KacheNetworkState.unavailable);
    client.pauseReconnect();
    network.emit(KacheNetworkState.available);
    await pumpEventQueue();
    expect(fetches, 0);

    final completed = client.events.firstWhere(
      (event) => event.kind == KacheEventKind.reconnectCompleted,
    );
    client.resumeReconnect();
    await completed;

    expect(fetches, 1);
    resource.dispose();
    await client.close();
  });

  test('in-flight reconnect keeps at most one trailing run', () async {
    final network = _FakeNetwork();
    final client = KacheClient(network: network);
    final first = Completer<int>();
    final second = Completer<int>();
    var fetches = 0;
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('network-coalesced'),
        policy: KachePolicy.staleWhileRevalidate(
          refreshOnLoad: KacheRevalidation.never,
        ),
        fetch: (_) {
          fetches += 1;
          return fetches == 1 ? first.future : second.future;
        },
      ),
    );
    final completions = client.events
        .where((event) => event.kind == KacheEventKind.reconnectCompleted)
        .take(2)
        .toList();
    network.emit(KacheNetworkState.unavailable);
    network.emit(KacheNetworkState.available);
    await pumpEventQueue();
    expect(fetches, 1);

    network.emit(KacheNetworkState.unavailable);
    network.emit(KacheNetworkState.available);
    network.emit(KacheNetworkState.unavailable);
    network.emit(KacheNetworkState.available);
    expect(fetches, 1);

    first.complete(1);
    await pumpEventQueue();
    expect(fetches, 2);
    second.complete(2);
    await completions;

    expect(fetches, 2);
    resource.dispose();
    await client.close();
  });

  test(
    'network stream errors and unexpected completion are observable',
    () async {
      final network = _FakeNetwork();
      final client = KacheClient(network: network);
      final failures = client.events
          .where(
            (event) =>
                event.kind == KacheEventKind.failure &&
                event.failure?.kind == KacheFailureKind.connectivity,
          )
          .take(2)
          .toList();
      final error = StateError('network failed');

      network.emitError(error);
      await network.end();
      final observed = await failures;

      expect(observed, hasLength(2));
      expect(observed.first.failure?.cause, same(error));
      expect(observed.every((event) => event.key == null), isTrue);
      await client.close();
    },
  );

  test('network ownership controls close', () async {
    final borrowed = _FakeNetwork();
    final borrowedClient = KacheClient(network: borrowed);
    await borrowedClient.close();
    expect(borrowed.closeCount, 0);
    await borrowed.close();

    final owned = _FakeNetwork();
    final ownedClient = KacheClient(
      network: owned,
      networkOwnership: KacheNetworkOwnership.owned,
    );
    await ownedClient.close();
    await ownedClient.close();
    expect(owned.closeCount, 1);
  });

  test(
    'close cancels an active reconnect without waiting for payload',
    () async {
      final network = _FakeNetwork();
      final started = Completer<void>();
      final cancelled = Completer<void>();
      final client = KacheClient(network: network);
      client.watch(
        KacheQuery<int>.memory(
          key: KacheKey('network-close-active'),
          policy: KachePolicy.staleWhileRevalidate(
            refreshOnLoad: KacheRevalidation.never,
          ),
          fetch: (context) async {
            started.complete();
            await context.cancellation.whenCancelled;
            cancelled.complete();
            context.throwIfCancelled();
            return 1;
          },
        ),
      );
      network.emit(KacheNetworkState.unavailable);
      network.emit(KacheNetworkState.available);
      await started.future;

      await client.close();
      await cancelled.future;
      await pumpEventQueue();

      expect(client.isClosed, isTrue);
      await network.close();
    },
  );

  test('owned network requires a configured source', () {
    expect(
      () => KacheClient(networkOwnership: KacheNetworkOwnership.owned),
      throwsA(isA<KacheConfigurationException>()),
    );
  });
}

final class _FakeNetwork implements KacheNetwork {
  final StreamController<KacheNetworkState> _states =
      StreamController<KacheNetworkState>.broadcast(sync: true);
  int closeCount = 0;

  @override
  Stream<KacheNetworkState> get states => _states.stream;

  void emit(KacheNetworkState state) => _states.add(state);

  void emitError(Object error) => _states.addError(error, StackTrace.current);

  Future<void> end() => _states.close();

  @override
  Future<void> close() async {
    if (_states.isClosed) {
      return;
    }
    closeCount += 1;
    await _states.close();
  }
}
