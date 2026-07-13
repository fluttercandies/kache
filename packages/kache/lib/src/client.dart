import 'dart:async';

import 'cancellation.dart';
import 'clock.dart';
import 'failure.dart';
import 'key.dart';
import 'persistence.dart';
import 'policy.dart';
import 'query.dart';
import 'snapshot.dart';

part 'entry.dart';
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
    KacheClock clock = systemKacheClock,
  }) : _clock = clock {
    if (persistence == null &&
        persistenceOwnership == KachePersistenceOwnership.owned) {
      throw const KacheConfigurationException(
        'owned_persistence_missing',
        'Owned persistence requires a configured backend.',
      );
    }
  }

  /// The optional persistence backend used by persisted queries.
  final KachePersistenceBackend? persistence;

  /// Whether this client closes [persistence].
  final KachePersistenceOwnership persistenceOwnership;

  final KacheClock _clock;
  final Map<String, _KacheEntryBase> _entries = <String, _KacheEntryBase>{};
  final Set<_KacheResourceBase> _resources = <_KacheResourceBase>{};
  bool _isClosed = false;
  Future<void>? _closeFuture;

  /// Whether [close] has started.
  bool get isClosed => _isClosed;

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

  /// Closes resources and, when owned, the configured persistence backend.
  ///
  /// Repeated calls return the same completion future.
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    _isClosed = true;
    final future = _performClose();
    _closeFuture = future;
    return future;
  }

  DateTime _now() => _clock().toUtc();

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

  void _release<T>(KacheResource<T> resource, _KacheEntry<T> entry) {
    _resources.remove(resource);
    entry.removeReference();
  }

  Future<void> _performClose() async {
    final resources = _resources.toList(growable: false);
    for (final resource in resources) {
      resource.dispose();
    }
    final entries = _entries.values.toList(growable: false);
    _entries.clear();
    for (final entry in entries) {
      await entry.close();
    }
    if (persistenceOwnership == KachePersistenceOwnership.owned) {
      await persistence!.close();
    }
  }
}
