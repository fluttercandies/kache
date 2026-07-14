import 'dart:async';

import 'cancellation.dart';
import 'clock.dart';
import 'command.dart';
import 'event.dart';
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
part 'resource.dart';

/// Coordinates typed cache resources, persistence, and shared key state.
final class KacheClient {
  /// Creates a cache client with optional [persistence].
  ///
  /// Injected persistence is borrowed by default. Select
  /// [KachePersistenceOwnership.owned] when this client must close it.
  KacheClient({
    this.persistence,
    this.persistenceOwnership = KachePersistenceOwnership.borrowed,
    this.network,
    this.networkOwnership = KacheNetworkOwnership.borrowed,
    KacheClock clock = systemKacheClock,
    KacheScheduler scheduler = systemKacheScheduler,
    KacheObserver? observer,
  }) : _clock = clock,
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

  /// Whether [close] has started.
  bool get isClosed => _isClosed;

  /// Latest state emitted by [network], or `null` before its first state.
  KacheNetworkState? get networkState => _networkState;

  /// Broadcast cache lifecycle events without replaying payload data.
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
    final resources = _resources.toList(growable: false);
    return Future.wait<void>(
      resources.map((resource) => resource.revalidateOnReconnect()),
    );
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
      return await resource.load();
    } finally {
      resource.dispose();
    }
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
    final future = _performClose(drainWrites: drainWrites);
    _closeFuture = future;
    return future;
  }

  /// Clears active memory and persisted entries in [namespace].
  Future<KacheClearResult> clearNamespace(
    KacheNamespace namespace, {
    bool refetch = false,
  }) {
    _ensureOpen();
    _emitEvent(kind: KacheEventKind.clearStarted, namespace: namespace);
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
    return _scheduleClear(
      () => _performClear(
        entries: entries,
        namespace: namespace,
        refetch: refetch,
      ),
    );
  }

  /// Clears every active memory and persisted cache entry.
  Future<KacheClearResult> clear({bool refetch = false}) {
    _ensureOpen();
    _emitEvent(kind: KacheEventKind.clearStarted);
    _globalEpoch += 1;
    final entries = _entries.values.toList(growable: false);
    for (final entry in entries) {
      entry.prepareForClear();
    }
    return _scheduleClear(
      () => _performClear(entries: entries, refetch: refetch),
    );
  }

  DateTime _now() => _clock().toUtc();

  _KacheOperationVersion _captureVersion(KacheKey key, int generation) =>
      _KacheOperationVersion(
        generation: generation,
        globalEpoch: _globalEpoch,
        namespaceEpoch: _namespaceEpochs[key.namespace] ?? 0,
      );

  bool _isEpochCurrent(KacheKey key, _KacheOperationVersion version) =>
      version.globalEpoch == _globalEpoch &&
      version.namespaceEpoch == (_namespaceEpochs[key.namespace] ?? 0);

  void _emitEvent({
    required KacheEventKind kind,
    KacheKey? key,
    KacheNamespace? namespace,
    String? debugName,
    KacheFailure? failure,
    KacheCacheLayer? layer,
  }) {
    if (_events.isClosed) {
      return;
    }
    final event = KacheEvent(
      kind: kind,
      occurredAt: _now(),
      key: key,
      namespace: namespace,
      debugName: debugName,
      failure: failure,
      layer: layer,
    );
    try {
      _observer?.call(event);
    } on Object {
      // Observer failures are isolated from the cache state machine.
    }
    _events.add(event);
  }

  void _reportFailure(KacheFailure failure, {String? debugName}) => _emitEvent(
    kind: KacheEventKind.failure,
    key: failure.key,
    namespace: failure.namespace,
    debugName: debugName,
    failure: failure,
  );

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
    unawaited(entry.finishClose());
  }

  Future<KacheClearResult> _performClear({
    required List<_KacheEntryBase> entries,
    KacheNamespace? namespace,
    required bool refetch,
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
        _reportFailure(failure);
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
        resources.map((resource) => resource.revalidateAfterClear()),
      );
    }
    _emitEvent(kind: KacheEventKind.clearCompleted, namespace: namespace);
    return KacheClearResult(failures: failures);
  }

  Future<KacheClearResult> _scheduleClear(
    Future<KacheClearResult> Function() operation,
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
    final cause = error is KachePersistenceException ? error.cause : error;
    final originalStack = error is KachePersistenceException
        ? error.stackTrace
        : stackTrace;
    final stage = error is KachePersistenceException
        ? error.stage
        : KachePersistenceStage.backend;
    return KacheFailure(
      kind: KacheFailureKind.clear,
      namespace: namespace,
      cause: cause,
      stackTrace: originalStack,
      persistenceStage: stage,
    );
  }

  Future<void> _performClose({required bool drainWrites}) async {
    final networkSubscription = _networkSubscription;
    _networkSubscription = null;
    await networkSubscription?.cancel();
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
      await clearTail;
    }
    await Future.wait<void>(entries.map((entry) => entry.drainForClose()));
    if (drainWrites) {
      _globalEpoch += 1;
    }
    for (final entry in entries) {
      await entry.finishClose();
    }
    try {
      await _closeOwnedDependencies();
    } finally {
      _emitEvent(kind: KacheEventKind.clientClosed);
      await _events.close();
    }
  }
}
