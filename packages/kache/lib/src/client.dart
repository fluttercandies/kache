import 'dart:async';
import 'dart:collection';

import 'cancellation.dart';
import 'clock.dart';
import 'command.dart';
import 'failure.dart';
import 'key.dart';
import 'network.dart';
import 'persistence.dart';
import 'policy.dart';
import 'query.dart';
import 'scheduler.dart';
import 'snapshot.dart';

part 'coordinator.dart';
part 'client_network.dart';
part 'entry.dart';
part 'entry_commands.dart';
part 'entry_persistence.dart';
part 'entry_snapshot.dart';
part 'event.dart';
part 'resource.dart';

int _nextGeneratedClientId = 0;

String _resolveClientId(String? value) {
  if (value == null) {
    return 'kache-${++_nextGeneratedClientId}';
  }
  if (value.trim().isEmpty) {
    throw const KacheConfigurationException(
      'invalid_client_id',
      'A client id must contain at least one non-whitespace character.',
    );
  }
  return value;
}

typedef _KachePersistenceError = ({
  Object cause,
  StackTrace stackTrace,
  KachePersistenceStage stage,
});

_KachePersistenceError _normalizePersistenceError({
  required Object error,
  required StackTrace stackTrace,
  required KachePersistenceOperation expectedOperation,
  required KachePersistenceStage fallbackStage,
}) {
  if (error case final KachePersistenceException persistenceError) {
    if (persistenceError.operation == expectedOperation) {
      return (
        cause: persistenceError.cause,
        stackTrace: persistenceError.stackTrace,
        stage: persistenceError.stage,
      );
    }
    return (
      cause: persistenceError,
      stackTrace: stackTrace,
      stage: KachePersistenceStage.backend,
    );
  }
  return (cause: error, stackTrace: stackTrace, stage: fallbackStage);
}

/// Coordinates typed cache resources, persistence, and shared key state.
final class KacheClient {
  /// Creates a cache client with optional [persistence].
  ///
  /// Injected persistence is borrowed by default. Select
  /// [KachePersistenceOwnership.owned] when this client must close it.
  KacheClient({
    String? id,
    this.persistence,
    this.persistenceOwnership = KachePersistenceOwnership.borrowed,
    this.network,
    this.networkOwnership = KacheNetworkOwnership.borrowed,
    KacheClock clock = systemKacheClock,
    KacheScheduler scheduler = systemKacheScheduler,
    KacheObserver? observer,
  })  : id = _resolveClientId(id),
        _clock = clock,
        _scheduler = scheduler,
        _observer = observer {
    if (persistence == null &&
        persistenceOwnership == KachePersistenceOwnership.owned) {
      throw const KacheConfigurationException(
        'owned_persistence_missing',
        'Owned persistence requires a configured backend.',
      );
    }
    if (network == null && networkOwnership == KacheNetworkOwnership.owned) {
      throw const KacheConfigurationException(
        'owned_network_missing',
        'Owned network requires a configured source.',
      );
    }
    _startNetwork();
  }

  /// Stable identity included in every event emitted by this client.
  final String id;

  /// The optional persistence backend used by persisted queries.
  final KachePersistenceBackend? persistence;

  /// Whether this client closes [persistence].
  final KachePersistenceOwnership persistenceOwnership;

  /// Optional network source used for reconnect revalidation.
  final KacheNetwork? network;

  /// Whether this client closes [network].
  final KacheNetworkOwnership networkOwnership;

  final KacheClock _clock;
  final KacheScheduler _scheduler;
  final KacheObserver? _observer;
  final StreamController<KacheEvent> _events =
      StreamController<KacheEvent>.broadcast(sync: true);
  final Map<String, _KacheEntryBase> _entries = <String, _KacheEntryBase>{};
  final Set<_KacheResourceBase> _resources = <_KacheResourceBase>{};
  final Map<String, int> _namespaceEpochs = <String, int>{};
  int _globalEpoch = 0;
  Future<void>? _clearTail;
  bool _isClosed = false;
  bool _isPollingPaused = false;
  bool _isReconnectPaused = false;
  bool _reconnectQueued = false;
  KacheNetworkState? _networkState;
  StreamSubscription<KacheNetworkState>? _networkSubscription;
  Future<void>? _reconnectFuture;
  Future<void>? _closeFuture;
  int _eventId = 0;
  int _eventSequence = 0;
  final Queue<KacheEvent> _eventQueue = ListQueue<KacheEvent>();
  bool _isDispatchingEvents = false;

  /// Whether [close] has started.
  bool get isClosed => _isClosed;

  /// Latest state emitted by [network], or `null` before its first state.
  KacheNetworkState? get networkState => _networkState;

  /// Broadcast trusted in-process lifecycle events without replay.
  Stream<KacheEvent> get events => _events.stream;

  /// Creates an independent resource handle for [query].
  ///
  /// Compatible handles share data and in-flight work for the same key while
  /// retaining their own fetcher and policy declarations.
  KacheResource<T> watch<T>(KacheQuery<T> query) {
    _ensureOpen();
    _validatePersistence(query);

    final storageKey = query.key.storageKey;
    final existing = _entries[storageKey];
    late final _KacheEntry<T> entry;
    if (existing == null) {
      entry = _KacheEntry<T>(client: this, query: query);
      _entries[storageKey] = entry;
    } else {
      _validateCompatibility<T>(existing, query);
      entry = existing as _KacheEntry<T>;
    }

    final resource = KacheResource<T>._(
      client: this,
      entry: entry,
      query: query,
    );
    _resources.add(resource);
    return resource;
  }

  /// Revalidates active handles according to each resume policy.
  Future<void> revalidateOnResume() {
    _ensureOpen();
    final resources = _resources.toList(growable: false);
    return Future.wait<void>(
      resources.map((resource) => resource.revalidateOnResume()),
    );
  }

  /// Revalidates active handles according to each reconnect policy.
  Future<void> revalidateOnReconnect() {
    _ensureOpen();
    return _runReconnect();
  }

  /// Forces refresh on every active handle.
  Future<void> refreshActive() {
    _ensureOpen();
    final resources = _resources.toList(growable: false);
    return Future.wait<void>(
      resources.map((resource) => resource.refreshActive()),
    );
  }

  /// Pauses interval-based refresh without affecting manual commands.
  void pausePolling() {
    _ensureOpen();
    if (_isPollingPaused) {
      return;
    }
    _isPollingPaused = true;
    for (final resource in _resources.toList(growable: false)) {
      resource.pausePolling();
    }
  }

  /// Resumes interval-based refresh for active resources.
  void resumePolling() {
    _ensureOpen();
    if (!_isPollingPaused) {
      return;
    }
    _isPollingPaused = false;
    for (final resource in _resources.toList(growable: false)) {
      resource.resumePolling();
    }
  }

  /// Pauses network-recovery revalidation without stopping state observation.
  void pauseReconnect() {
    _ensureOpen();
    _isReconnectPaused = true;
  }

  /// Resumes network-recovery revalidation and consumes one pending recovery.
  void resumeReconnect() {
    _ensureOpen();
    if (!_isReconnectPaused) {
      return;
    }
    _isReconnectPaused = false;
    if (_reconnectQueued) {
      _reconnectQueued = false;
      _requestReconnect();
    }
  }

  /// Loads [query] without retaining a public resource handle.
  Future<KacheSnapshot<T>> prefetch<T>(KacheQuery<T> query) async {
    final resource = watch(query);
    try {
      return await resource._loadWith(KacheEventTrigger.prefetch);
    } finally {
      resource.dispose();
    }
  }

  /// Cancels the shared in-flight fetch for [key].
  ///
  /// Cached data and future polling remain unchanged. Returns `false` when the
  /// key has no active cancellable fetch.
  bool cancel(KacheKey key) {
    _ensureOpen();
    return _entries[key.storageKey]?.cancelFetch(KacheCancelReason.manual) ??
        false;
  }

  /// Cancels every currently cancellable fetch and returns the affected count.
  int cancelAll() {
    _ensureOpen();
    var count = 0;
    for (final entry in _entries.values.toList(growable: false)) {
      if (entry.cancelFetch(KacheCancelReason.manual)) {
        count += 1;
      }
    }
    return count;
  }

  /// Returns the active in-memory snapshot for [key] without I/O or loading.
  KacheSnapshot<T>? peek<T>(KacheKey key) {
    _ensureOpen();
    final existing = _entries[key.storageKey];
    if (existing == null) {
      return null;
    }
    if (existing.valueType != T) {
      throw const KacheConfigurationException(
        'key_type_conflict',
        'The active cache key is registered for another value type.',
      );
    }
    return (existing as _KacheEntry<T>).snapshot;
  }

  /// Closes resources and, when owned, the configured persistence backend.
  ///
  /// Repeated calls return the same completion future.
  Future<void> close({bool drainWrites = true}) {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    _isClosed = true;
    final completion = Completer<void>();
    final future = completion.future;
    _closeFuture = future;
    try {
      final trace = _trace(KacheEventTrigger.close);
      final span = trace.span(KacheEventKind.close)..start();
      unawaited(
        _performClose(drainWrites: drainWrites, span: span).then<void>(
          (_) => completion.complete(),
          onError: (Object error, StackTrace stackTrace) {
            completion.completeError(error, stackTrace);
          },
        ),
      );
    } on Object catch (error, stackTrace) {
      completion.completeError(error, stackTrace);
    }
    return future;
  }

  /// Clears active memory and persisted entries in [namespace].
  Future<KacheClearResult> clearNamespace(
    KacheNamespace namespace, {
    bool refetch = false,
  }) {
    _ensureOpen();
    final trace = _trace(
      KacheEventTrigger.clear,
      namespace: namespace,
    );
    final span = trace.span(KacheEventKind.clear);
    _namespaceEpochs.update(
      namespace.value,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    final entries = _entries.values
        .where((entry) => entry.key.namespace == namespace.value)
        .toList(growable: false);
    for (final entry in entries) {
      entry.prepareForClear();
    }
    span.start();
    return _scheduleClear(
      () => _performClear(
        entries: entries,
        namespace: namespace,
        refetch: refetch,
        trace: trace,
        span: span,
      ),
      span,
    );
  }

  /// Clears every active memory and persisted cache entry.
  Future<KacheClearResult> clear({bool refetch = false}) {
    _ensureOpen();
    final trace = _trace(KacheEventTrigger.clear);
    final span = trace.span(KacheEventKind.clear);
    _globalEpoch += 1;
    final entries = _entries.values.toList(growable: false);
    for (final entry in entries) {
      entry.prepareForClear();
    }
    span.start();
    return _scheduleClear(
      () => _performClear(
        entries: entries,
        refetch: refetch,
        trace: trace,
        span: span,
      ),
      span,
    );
  }

  DateTime _now() => _clock().toUtc();

  _KacheOperationVersion _captureVersion(
    KacheKey key,
    int generation,
    KacheCancellationToken cancellation,
  ) =>
      _KacheOperationVersion(
        generation: generation,
        globalEpoch: _globalEpoch,
        namespaceEpoch: _namespaceEpochs[key.namespace] ?? 0,
        cancellation: cancellation,
      );

  bool _isEpochCurrent(KacheKey key, _KacheOperationVersion version) =>
      version.globalEpoch == _globalEpoch &&
      version.namespaceEpoch == (_namespaceEpochs[key.namespace] ?? 0);

  String _nextEventId() => '$id:${++_eventId}';

  _KacheTrace _trace(
    KacheEventTrigger trigger, {
    KacheQuery<dynamic>? query,
    KacheKey? key,
    KacheNamespace? namespace,
  }) =>
      _KacheTrace(
        client: this,
        id: _nextEventId(),
        trigger: trigger,
        context: query == null
            ? _KacheEventContext(key: key, namespace: namespace)
            : _KacheEventContext(
                key: query.key,
                debugName: query.debugName,
                metadata: query.metadata,
              ),
      );

  void _dispatchEvent({
    required String traceId,
    required String id,
    required String? parentId,
    required KacheEventKind kind,
    required KacheEventPhase phase,
    required KacheEventTrigger trigger,
    required Duration? duration,
    required _KacheEventContext context,
    required KacheLayer? layer,
    required KacheLookupResult? lookup,
    required KacheNetworkState? networkState,
    required KacheFailure? failure,
    required KacheCancelReason? cancelReason,
    required int? revision,
    required Object? data,
  }) {
    if (_events.isClosed) {
      return;
    }
    final event = KacheEvent._(
      clientId: this.id,
      sequence: ++_eventSequence,
      traceId: traceId,
      id: id,
      parentId: parentId,
      kind: kind,
      phase: phase,
      trigger: trigger,
      occurredAt: _now(),
      duration: duration,
      key: context.key,
      namespace: context.namespace,
      debugName: context.debugName,
      metadata: context.metadata,
      layer: layer,
      lookup: lookup,
      networkState: networkState,
      failure: failure,
      cancelReason: cancelReason,
      revision: revision,
      data: data,
    );
    _eventQueue.addLast(event);
    if (_isDispatchingEvents) {
      return;
    }
    _isDispatchingEvents = true;
    try {
      while (_eventQueue.isNotEmpty && !_events.isClosed) {
        final next = _eventQueue.removeFirst();
        try {
          _observer?.call(next);
        } on Object {
          // Observer failures are isolated from the cache state machine.
        }
        _events.add(next);
      }
    } finally {
      _isDispatchingEvents = false;
    }
  }

  void _ensureOpen() {
    if (_isClosed) {
      throw const KacheLifecycleException(
        'client_closed',
        'The Kache client is closed.',
      );
    }
  }

  void _validatePersistence<T>(KacheQuery<T> query) {
    if (query.storageMode != KacheStorageMode.persisted) {
      return;
    }
    final backend = persistence;
    if (backend == null) {
      throw const KacheConfigurationException(
        'persistence_unavailable',
        'A persisted query requires a client persistence backend.',
      );
    }
    try {
      query.binding!.ensureBackend(backend);
    } on KachePersistenceBindingException {
      throw const KacheConfigurationException(
        'binding_backend_mismatch',
        'The query binding belongs to a different persistence backend.',
      );
    }
  }

  void _validateCompatibility<T>(
    _KacheEntryBase existing,
    KacheQuery<T> query,
  ) {
    if (existing.valueType != T) {
      throw const KacheConfigurationException(
        'key_type_conflict',
        'An active cache key is already registered for another value type.',
      );
    }
    if (existing.storageMode != query.storageMode) {
      throw const KacheConfigurationException(
        'key_storage_conflict',
        'An active cache key is already registered with another storage mode.',
      );
    }
    if (existing.bindingFingerprint != query.binding?.fingerprint) {
      throw const KacheConfigurationException(
        'key_binding_conflict',
        'An active cache key is already registered with another binding.',
      );
    }
  }

  void _rebind<T>(_KacheEntry<T> entry, KacheQuery<T> query) {
    _ensureOpen();
    if (query.key != entry.key) {
      throw const KacheConfigurationException(
        'resource_key_change',
        'A resource can only update a query for its existing cache key.',
      );
    }
    _validatePersistence(query);
    _validateCompatibility<T>(entry, query);
  }

  void _release<T>(KacheResource<T> resource, _KacheEntry<T> entry) {
    _resources.remove(resource);
    entry.removeReference();
  }

  void _tryCollect(_KacheEntryBase entry) {
    final registered = _entries[entry.key.storageKey];
    if (!identical(registered, entry) || !entry.canCollect) {
      return;
    }
    _entries.remove(entry.key.storageKey);
    unawaited(entry.finishClose(waitForBackendRead: false));
  }

  Future<KacheClearResult> _performClear({
    required List<_KacheEntryBase> entries,
    KacheNamespace? namespace,
    required bool refetch,
    required _KacheTrace trace,
    required _KacheEventSpan span,
  }) async {
    await Future.wait<void>(entries.map((entry) => entry.drainWrites()));

    final failures = <KacheFailure>[];
    final backend = persistence;
    if (backend != null) {
      try {
        if (namespace == null) {
          await backend.clear();
        } else {
          await backend.clearNamespace(namespace: namespace);
        }
      } on Object catch (error, stackTrace) {
        final failure = _clearFailure(
          error: error,
          stackTrace: stackTrace,
          namespace: namespace,
        );
        failures.add(failure);
        for (final entry in entries) {
          entry.reportClearFailure(failure);
        }
      }
    }
    if (failures.isEmpty) {
      for (final entry in entries) {
        entry.completeClear();
      }
    }

    if (refetch) {
      final affectedKeys = entries.map((entry) => entry.key).toSet();
      final resources = _resources
          .where((resource) => affectedKeys.contains(resource.key))
          .toList(growable: false);
      await Future.wait<void>(
        resources.map((resource) => resource._revalidateAfterClear(trace)),
      );
    }
    if (failures.isNotEmpty) {
      span.fail(failures.first);
    } else {
      span.succeed();
    }
    return KacheClearResult(failures: failures);
  }

  Future<KacheClearResult> _scheduleClear(
    Future<KacheClearResult> Function() operation,
    _KacheEventSpan span,
  ) {
    final previous = _clearTail;
    final tailCompleter = Completer<void>();
    final result = Completer<KacheClearResult>();
    _clearTail = tailCompleter.future;
    unawaited(() async {
      if (previous != null) {
        await previous;
      }
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        if (!span._ended) {
          span.fail(
            KacheFailure(
              kind: KacheFailureKind.clear,
              namespace: span.trace.context.namespace,
              cause: error,
              stackTrace: stackTrace,
            ),
          );
        }
        result.completeError(error, stackTrace);
      } finally {
        tailCompleter.complete();
      }
    }());
    return result.future;
  }

  KacheFailure _clearFailure({
    required Object error,
    required StackTrace stackTrace,
    required KacheNamespace? namespace,
  }) {
    final details = _normalizePersistenceError(
      error: error,
      stackTrace: stackTrace,
      expectedOperation: namespace == null
          ? KachePersistenceOperation.clear
          : KachePersistenceOperation.clearNamespace,
      fallbackStage: KachePersistenceStage.backend,
    );
    return KacheFailure(
      kind: KacheFailureKind.clear,
      namespace: namespace,
      cause: details.cause,
      stackTrace: details.stackTrace,
      persistenceStage: details.stage,
    );
  }

  Future<void> _performClose({
    required bool drainWrites,
    required _KacheEventSpan span,
  }) async {
    _KacheCloseFailure? firstFailure;
    void recordFailure(Object error, StackTrace stackTrace) {
      firstFailure ??= _KacheCloseFailure(
        failure: KacheFailure(
          kind: KacheFailureKind.lifecycle,
          cause: error,
          stackTrace: stackTrace,
        ),
        cause: error,
        stackTrace: stackTrace,
      );
    }

    Object? networkCancellationError;
    StackTrace? networkCancellationStackTrace;
    var networkCancellationSettled = false;

    try {
      final networkSubscription = _networkSubscription;
      _networkSubscription = null;
      if (networkSubscription != null) {
        try {
          final cancellation = networkSubscription.cancel();
          unawaited(
            cancellation.then<void>(
              (_) => networkCancellationSettled = true,
              onError: (Object error, StackTrace stackTrace) {
                networkCancellationError = error;
                networkCancellationStackTrace = stackTrace;
                networkCancellationSettled = true;
              },
            ),
          );
        } on Object catch (error, stackTrace) {
          networkCancellationError = error;
          networkCancellationStackTrace = stackTrace;
          networkCancellationSettled = true;
        }
      }
      final resources = _resources.toList(growable: false);
      for (final resource in resources) {
        resource.dispose();
      }
      final entries = _entries.values.toList(growable: false);
      _entries.clear();
      if (!drainWrites) {
        _globalEpoch += 1;
      }
      for (final entry in entries) {
        entry.prepareForClientClose(cancelPendingWrites: !drainWrites);
      }
      final clearTail = _clearTail;
      if (clearTail != null) {
        try {
          await clearTail;
        } on Object catch (error, stackTrace) {
          recordFailure(error, stackTrace);
        }
      }
      try {
        await Future.wait<void>(
          entries.map((entry) => entry.drainForClose()),
        );
      } on Object catch (error, stackTrace) {
        recordFailure(error, stackTrace);
      }
      if (drainWrites) {
        _globalEpoch += 1;
      }
      for (final entry in entries) {
        try {
          await entry.finishClose(
            waitForBackendRead:
                persistenceOwnership == KachePersistenceOwnership.owned,
          );
        } on Object catch (error, stackTrace) {
          recordFailure(error, stackTrace);
        }
      }
      try {
        await _closeOwnedDependencies(span.trace);
      } on _KacheCloseFailure catch (error) {
        firstFailure ??= error;
      }
      // A network source owns its cancellation cleanup. Give an already
      // settled cancellation one microtask to report an error, but never let a
      // stalled external onCancel callback block independent client teardown.
      await Future<void>.value();
      final cancellationError = networkCancellationError;
      if (networkCancellationSettled && cancellationError != null) {
        final error = cancellationError;
        final stackTrace = networkCancellationStackTrace!;
        firstFailure ??= _KacheCloseFailure(
          failure: KacheFailure(
            kind: KacheFailureKind.lifecycle,
            cause: error,
            stackTrace: stackTrace,
          ),
          cause: error,
          stackTrace: stackTrace,
        );
      }
      final failure = firstFailure;
      if (failure != null) {
        span.fail(failure.failure);
        Error.throwWithStackTrace(failure.cause, failure.stackTrace);
      }
      span.succeed();
    } finally {
      // The trusted events stream is closed fire-and-forget so an externally
      // paused subscriber can never block teardown. The terminal done event
      // stays pending and is delivered when that subscriber resumes.
      unawaited(_events.close());
    }
  }
}
