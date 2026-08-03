import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

import 'support/scripted_persistence.dart';

// These tests reproduce three concurrency/lifecycle defects identified by the
// core state-machine review. Each fails against the previous implementation and
// passes once the independent data-commit epoch, the isRefreshing preservation,
// and the aggregated close cleanup are in place.

void main() {
  group('data-commit epoch', () {
    final now = DateTime.utc(2026, 8, 3, 12);

    test(
      'a late persistence read hit cannot overwrite a fresher fetch result',
      () async {
        final backend = _FixedReadPersistence(
          readEntry: KachePersistedEntry<String>(
            data: 'cached',
            metadata: KachePersistedMetadata(fetchedAt: now),
          ),
        )..readGate = Completer<void>();
        final binding = backend.bind<String>(fingerprint: 'value-v1');
        final client = KacheClient(persistence: backend, clock: () => now);
        final resource = client.watch(
          KacheQuery<String>.persisted(
            key: KacheKey('late-read-hit'),
            binding: binding,
            fetch: (_) async => 'fresh',
            policy: KachePolicy(
              staleAfter: const Duration(hours: 1),
              refreshOnLoad: KacheRevalidation.ifStale,
              refreshOnResume: KacheRevalidation.ifStale,
              refreshOnReconnect: KacheRevalidation.ifStale,
            ),
          ),
        );

        // load() starts the gated persistence read but cannot finish it.
        final loadFuture = resource.load();
        await Future<void>.delayed(Duration.zero);
        expect(backend.readCount, 1);

        // A concurrent refresh commits fresher data before the read resolves.
        final refreshed = await resource.refresh();
        expect(refreshed.requireData, 'fresh');
        expect(refreshed.source, KacheDataSource.fetch);

        // Releasing the gate lets the stale read resolve late.
        backend.readGate!.complete();
        final loaded = await loadFuture;

        expect(loaded.requireData, 'fresh');
        expect(loaded.source, KacheDataSource.fetch);
        expect(
          loaded.persistence?.phase,
          KachePersistencePhase.persisted,
        );

        resource.dispose();
        await client.close();
      },
    );

    test(
      'a late persistence read error cannot downgrade a fresher fetch result',
      () async {
        final backend = _FixedReadPersistence(
          readEntry: KachePersistedEntry<String>(
            data: 'cached',
            metadata: KachePersistedMetadata(fetchedAt: now),
          ),
          readError: StateError('backend read failed'),
        )..readGate = Completer<void>();
        final binding = backend.bind<String>(fingerprint: 'value-v1');
        final client = KacheClient(persistence: backend, clock: () => now);
        final resource = client.watch(
          KacheQuery<String>.persisted(
            key: KacheKey('late-read-error'),
            binding: binding,
            fetch: (_) async => 'fresh',
            policy: KachePolicy(
              staleAfter: const Duration(hours: 1),
              refreshOnLoad: KacheRevalidation.ifStale,
              refreshOnResume: KacheRevalidation.ifStale,
              refreshOnReconnect: KacheRevalidation.ifStale,
            ),
          ),
        );

        final loadFuture = resource.load();
        await Future<void>.delayed(Duration.zero);
        expect(backend.readCount, 1);

        final refreshed = await resource.refresh();
        expect(refreshed.requireData, 'fresh');

        backend.readGate!.complete();
        final loaded = await loadFuture;

        // The late error must neither attach a failure nor delete the value.
        expect(loaded.requireData, 'fresh');
        expect(loaded.failure, isNull);
        expect(loaded.persistence?.phase, KachePersistencePhase.persisted);
        expect(backend.deleteCount, 0);

        resource.dispose();
        await client.close();
      },
    );

    test(
      'a late persistence read hit delivers stale cache and retains a '
      'concurrent fetch failure',
      () async {
        final backend = _FixedReadPersistence(
          readEntry: KachePersistedEntry<String>(
            data: 'cached',
            metadata: KachePersistedMetadata(
              fetchedAt: now.subtract(const Duration(hours: 2)),
            ),
          ),
        )..readGate = Completer<void>();
        final binding = backend.bind<String>(fingerprint: 'value-v1');
        final fetchError = StateError('fetch failed');
        final client = KacheClient(persistence: backend, clock: () => now);
        final resource = client.watch(
          KacheQuery<String>.persisted(
            key: KacheKey('late-read-hit-with-failure'),
            binding: binding,
            fetch: (_) async {
              Error.throwWithStackTrace(fetchError, StackTrace.current);
            },
            policy: KachePolicy(
              staleAfter: const Duration(hours: 1),
              refreshOnLoad: KacheRevalidation.never,
              refreshOnResume: KacheRevalidation.never,
              refreshOnReconnect: KacheRevalidation.never,
            ),
          ),
        );

        // load() starts the gated persistence read but cannot finish it.
        final loadFuture = resource.load();
        await Future<void>.delayed(Duration.zero);
        expect(backend.readCount, 1);

        // A concurrent refresh fails before the gated read resolves. With no
        // memory data the entry enters a terminal failure state.
        final refreshed = await resource.refresh();
        expect(refreshed.phase, KachePhase.failure);
        expect(resource.snapshot.failure, isNotNull);

        // Releasing the gate lets the stale read resolve late. SWR semantics
        // require the cached data to surface while the concurrent fetch
        // failure stays observable instead of being silently overwritten.
        backend.readGate!.complete();
        final loaded = await loadFuture;

        expect(loaded.hasData, isTrue);
        expect(loaded.requireData, 'cached');
        expect(loaded.source, KacheDataSource.persistence);
        expect(loaded.freshness, KacheFreshness.stale);
        expect(loaded.failure, isNotNull);
        expect(loaded.failure?.cause, same(fetchError));

        resource.dispose();
        await client.close();
      },
    );

    test('load cannot replace data committed before the initial read',
        () async {
      final backend = ScriptedPersistence()
        ..storedEntry = KachePersistedEntry<String>(
          data: 'older-persisted',
          metadata: KachePersistedMetadata(fetchedAt: now),
        )
        ..writeError = StateError('write failed');
      var fetchCount = 0;
      final client = KacheClient(persistence: backend, clock: () => now);
      final resource = client.watch(
        KacheQuery<String>.persisted(
          key: KacheKey('commit-before-read'),
          binding: backend.bind<String>(fingerprint: 'value-v1'),
          fetch: (_) async => 'fresh-${++fetchCount}',
          policy: KachePolicy(
            staleAfter: const Duration(hours: 1),
            refreshOnLoad: KacheRevalidation.never,
            refreshOnResume: KacheRevalidation.never,
            refreshOnReconnect: KacheRevalidation.never,
          ),
        ),
      );

      final refreshed = await resource.refresh();
      expect(refreshed.requireData, 'fresh-1');
      expect(refreshed.persistence?.phase, KachePersistencePhase.failed);

      final loaded = await resource.load();

      expect(loaded.requireData, 'fresh-1');
      expect(loaded.source, KacheDataSource.fetch);
      expect(loaded.persistence?.phase, KachePersistencePhase.failed);
      expect(backend.readCount, 0);
      expect(fetchCount, 1);

      resource.dispose();
      await client.close();
    });
  });

  group('refreshing flag', () {
    test(
      'a freshness reclassification during refresh keeps isRefreshing alive',
      () async {
        var now = DateTime.utc(2026, 8, 3, 12);
        final refreshGate = Completer<String>();
        var fetchCalls = 0;
        final client = KacheClient(clock: () => now);
        final resource = client.watch(
          KacheQuery<String>.memory(
            key: KacheKey('refresh-flag'),
            fetch: (context) {
              fetchCalls += 1;
              if (fetchCalls == 1) {
                return Future<String>.value('cached');
              }
              return refreshGate.future;
            },
            policy: KachePolicy(
              staleAfter: const Duration(minutes: 10),
              refreshOnLoad: KacheRevalidation.ifStale,
              refreshOnResume: KacheRevalidation.ifStale,
              refreshOnReconnect: KacheRevalidation.ifStale,
            ),
          ),
        );

        final loaded = await resource.load();
        expect(loaded.requireData, 'cached');
        expect(loaded.isRefreshing, isFalse);

        // Start a gated refresh; its isRefreshing emit is synchronous.
        final refreshFuture = resource.refresh();
        expect(resource.snapshot.isRefreshing, isTrue);

        // Age the data so a concurrent revalidation reclassifies freshness.
        now = now.add(const Duration(minutes: 15));

        // Revalidation runs while the refresh is still in flight. Its
        // freshness emit must not clear the still-running refresh flag.
        final revalidateFuture = client.revalidateOnResume();
        expect(resource.snapshot.isRefreshing, isTrue);
        expect(resource.snapshot.freshness, KacheFreshness.stale);

        refreshGate.complete('fresh');
        await refreshFuture;
        await revalidateFuture;

        expect(resource.snapshot.requireData, 'fresh');
        expect(resource.snapshot.isRefreshing, isFalse);

        resource.dispose();
        await client.close();
      },
    );
  });

  group('close aggregation', () {
    test(
      'close continues cleanup when the network subscription cancel fails',
      () async {
        final persistence = ScriptedPersistence();
        final binding = persistence.bind<String>(fingerprint: 'value-v1');
        final network = _CancelThrowingNetwork();
        final client = KacheClient(
          persistence: persistence,
          persistenceOwnership: KachePersistenceOwnership.owned,
          network: network,
          networkOwnership: KacheNetworkOwnership.owned,
        );
        final resource = client.watch(
          KacheQuery<String>.persisted(
            key: KacheKey('close-race'),
            binding: binding,
            fetch: (_) async => 'value',
          ),
        );

        final events = <KacheEvent>[];
        client.events.listen(events.add);

        await expectLater(
          client.close(),
          throwsA(isA<_SubscriptionCancelError>()),
        );

        // The first error is rethrown, but every independent cleanup still ran.
        expect(resource.isDisposed, isTrue);
        expect(persistence.closeCount, 1);
        expect(network.closeCount, 1);

        final closeEvent = events.lastWhere(
          (event) => event.kind == KacheEventKind.close && event.layer == null,
        );
        expect(closeEvent.phase, KacheEventPhase.failed);
        expect(closeEvent.failure?.kind, KacheFailureKind.lifecycle);
      },
    );
    test('close preserves an earlier owned persistence failure', () async {
      final persistence = ScriptedPersistence();
      final persistenceError = StateError('persistence close failed');
      persistence.onClose = () => Future<void>.error(persistenceError);
      final network = _CancelThrowingNetwork();
      final client = KacheClient(
        persistence: persistence,
        persistenceOwnership: KachePersistenceOwnership.owned,
        network: network,
        networkOwnership: KacheNetworkOwnership.owned,
      );

      Object? thrown;
      try {
        await client.close();
      } on Object catch (error) {
        thrown = error;
      }

      expect(thrown, isA<KachePersistenceException>());
      expect(
          (thrown! as KachePersistenceException).cause, same(persistenceError));
      expect(network.closeCount, 1);
    });

    test('close does not wait for stalled network cancellation', () async {
      final network = _StalledCancelNetwork();
      final client = KacheClient(
        network: network,
        networkOwnership: KacheNetworkOwnership.owned,
      );
      final resource = client.watch(
        KacheQuery<String>.memory(
          key: KacheKey('stalled-network-cancel'),
          policy: KachePolicy.cacheOnly(),
        ),
      );

      await client.close().timeout(const Duration(seconds: 1));

      expect(network.cancellationStarted.isCompleted, isTrue);
      expect(network.closeCount, 1);
      expect(resource.isDisposed, isTrue);
      await network.releaseCancellation();
    });
  });

  group('close does not block on paused events subscription', () {
    test(
      'close completes while an events subscription is paused and delivers '
      'done after resume',
      () async {
        final client = KacheClient();
        final resource = client.watch(
          KacheQuery<String>.memory(
            key: KacheKey('paused-events'),
            fetch: (_) async => 'value',
          ),
        );
        await resource.load();

        final done = Completer<bool>();
        final subscription = client.events.listen(
          (_) {},
          onDone: () => done.complete(true),
        );
        subscription.pause();

        // The previous implementation awaited the events controller close
        // future, which never completes while any listener is paused. Close
        // must trigger the terminal done event without waiting for external
        // subscribers.
        await client.close();
        expect(done.isCompleted, isFalse);

        // The done event remains pending and is delivered once the paused
        // subscription resumes.
        subscription.resume();
        expect(await done.future, isTrue);
      },
    );
  });
}

/// A persistence backend whose [read] resolves to a fixed entry (or error),
/// independently of subsequent writes, so a late read can be made to return
/// data that predates a fresher fetch.
final class _FixedReadPersistence implements KachePersistenceBackend {
  _FixedReadPersistence({this.readEntry, this.readError});

  Object? readEntry;
  Object? readError;
  StackTrace? readStackTrace;
  Completer<void>? readGate;

  int readCount = 0;
  int writeCount = 0;
  int deleteCount = 0;
  int clearCount = 0;
  int closeCount = 0;
  bool isClosed = false;

  KachePersistenceBinding<T> bind<T>({required String fingerprint}) =>
      _FixedReadBinding<T>(backend: this, fingerprint: fingerprint);

  @override
  Future<KachePersistenceRead<T>?> read<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
  }) async {
    binding.ensureBackend(this);
    readCount += 1;
    final gate = readGate;
    if (gate != null) {
      await gate.future;
    }
    final error = readError;
    if (error != null) {
      Error.throwWithStackTrace(error, readStackTrace ?? StackTrace.current);
    }
    final entry = readEntry;
    if (entry == null) {
      return null;
    }
    return KachePersistenceRead<T>(
      entry: entry as KachePersistedEntry<T>,
    );
  }

  @override
  Future<void> write<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
    required KachePersistedEntry<T> entry,
  }) async {
    binding.ensureBackend(this);
    writeCount += 1;
  }

  @override
  Future<void> delete({required KacheKey key}) async {
    deleteCount += 1;
  }

  @override
  Future<void> clearNamespace({required KacheNamespace namespace}) async {
    clearCount += 1;
  }

  @override
  Future<void> clear() async {
    clearCount += 1;
  }

  @override
  Future<void> close() async {
    if (isClosed) {
      return;
    }
    closeCount += 1;
    isClosed = true;
  }
}

final class _FixedReadBinding<T> extends KachePersistenceBinding<T> {
  _FixedReadBinding({required super.backend, required super.fingerprint});
}

final class _SubscriptionCancelError implements Exception {
  const _SubscriptionCancelError();

  @override
  String toString() => 'network subscription cancel failed';
}

/// A network source whose subscription cancel fails, while its owned [close]
/// succeeds, so close must keep cleaning up after the cancel error.
final class _CancelThrowingNetwork implements KacheNetwork {
  // Single-subscription controller: its onCancel is FutureOr<void>, so a
  // synchronous throw propagates through StreamSubscription.cancel() as the
  // error of the returned future. (A broadcast controller's onCancel is a
  // void callback whose throws become uncaught zone errors and never reach
  // cancel().) The client subscribes exactly once, so this is safe.
  final StreamController<KacheNetworkState> _states =
      StreamController<KacheNetworkState>(
    sync: true,
    onCancel: () {
      throw const _SubscriptionCancelError();
    },
  );

  int closeCount = 0;

  @override
  Stream<KacheNetworkState> get states => _states.stream;

  @override
  Future<void> close() async {
    closeCount += 1;
  }
}

final class _StalledCancelNetwork implements KacheNetwork {
  final Completer<void> cancellationStarted = Completer<void>();
  final Completer<void> _cancellationGate = Completer<void>();
  late final StreamController<KacheNetworkState> _states =
      StreamController<KacheNetworkState>(
    sync: true,
    onCancel: () {
      cancellationStarted.complete();
      return _cancellationGate.future;
    },
  );

  int closeCount = 0;

  @override
  Stream<KacheNetworkState> get states => _states.stream;

  @override
  Future<void> close() async {
    closeCount += 1;
  }

  Future<void> releaseCancellation() async {
    _cancellationGate.complete();
    await _states.close();
  }
}
