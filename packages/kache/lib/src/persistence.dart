import 'key.dart';

/// A storage backend that persists typed cache entries.
///
/// Implementations own serialization, migrations, and physical storage. The
/// core library passes typed values and an opaque [KachePersistenceBinding]
/// without prescribing a record format.
abstract interface class KachePersistenceBackend {
  /// Reads the entry for [key], or returns `null` when no entry exists.
  ///
  /// The [binding] describes backend-specific handling for `T`. Implementations
  /// should call [KachePersistenceBinding.ensureBackend] before using it.
  Future<KachePersistenceRead<T>?> read<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
  });

  /// Writes a typed [entry] for [key] using [binding].
  ///
  /// Implementations should call [KachePersistenceBinding.ensureBackend]
  /// before using the binding.
  Future<void> write<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
    required KachePersistedEntry<T> entry,
  });

  /// Deletes the persisted entry for [key] when present.
  Future<void> delete({required KacheKey key});

  /// Deletes entries whose canonical storage keys start with [namespacePrefix].
  Future<void> clearNamespace({required String namespacePrefix});

  /// Deletes every entry managed by this backend.
  Future<void> clear();

  /// Releases resources owned by this backend.
  ///
  /// Client code only calls this for a backend configured with
  /// [KachePersistenceOwnership.owned].
  Future<void> close();
}

/// Opaque, backend-specific configuration for persisting values of type `T`.
///
/// External storage packages extend this class to attach their own mapping or
/// migration configuration. Core code only uses [backend] and [fingerprint].
abstract class KachePersistenceBinding<T> {
  /// Creates a binding owned by [backend] with a stable [fingerprint].
  ///
  /// The fingerprint must contain at least one non-whitespace character and
  /// should change whenever the binding's storage interpretation changes.
  /// Throws [KachePersistenceBindingException] for an invalid fingerprint.
  KachePersistenceBinding({required this.backend, required String fingerprint})
    : fingerprint = _validateFingerprint(fingerprint);

  /// The only backend instance that may use this binding.
  final KachePersistenceBackend backend;

  /// An opaque, stable identity for this binding's storage interpretation.
  final String fingerprint;

  /// Verifies that [candidate] is the backend instance that owns this binding.
  ///
  /// Throws [KachePersistenceBindingException] immediately when the instances
  /// are not identical. The exception does not expose the fingerprint.
  void ensureBackend(KachePersistenceBackend candidate) {
    if (!identical(backend, candidate)) {
      throw const KachePersistenceBindingException._backendMismatch();
    }
  }
}

/// Reports invalid persistence binding configuration without rendering it.
final class KachePersistenceBindingException implements Exception {
  const KachePersistenceBindingException._emptyFingerprint()
    : _message = 'Persistence binding fingerprint must not be empty.';

  const KachePersistenceBindingException._backendMismatch()
    : _message = 'Persistence binding belongs to a different backend.';

  final String _message;

  @override
  String toString() => 'KachePersistenceBindingException: $_message';
}

/// Metadata stored alongside a typed cache value.
final class KachePersistedMetadata {
  /// Creates metadata for a value fetched at [fetchedAt].
  ///
  /// [fetchedAt] is normalized to UTC. [isInvalidated] defaults to `false`.
  factory KachePersistedMetadata({
    required DateTime fetchedAt,
    bool isInvalidated = false,
  }) => KachePersistedMetadata._(fetchedAt.toUtc(), isInvalidated);

  const KachePersistedMetadata._(this.fetchedAt, this.isInvalidated);

  /// The UTC instant at which the value was fetched.
  final DateTime fetchedAt;

  /// Whether the value was explicitly invalidated after it was fetched.
  final bool isInvalidated;

  /// Returns metadata with the supplied fields replaced.
  KachePersistedMetadata copyWith({DateTime? fetchedAt, bool? isInvalidated}) =>
      KachePersistedMetadata(
        fetchedAt: fetchedAt ?? this.fetchedAt,
        isInvalidated: isInvalidated ?? this.isInvalidated,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KachePersistedMetadata &&
          fetchedAt == other.fetchedAt &&
          isInvalidated == other.isInvalidated;

  @override
  int get hashCode => Object.hash(fetchedAt, isInvalidated);
}

/// A typed value and the metadata persisted with it.
final class KachePersistedEntry<T> {
  /// Creates a persisted entry containing [data] and [metadata].
  ///
  /// [data] may be `null` when `T` is nullable.
  const KachePersistedEntry({required this.data, required this.metadata});

  /// The typed persisted value.
  final T data;

  /// Metadata describing the persisted value.
  final KachePersistedMetadata metadata;
}

/// A successful persistence read and optional asynchronous maintenance work.
final class KachePersistenceRead<T> {
  /// Creates a read result containing [entry].
  ///
  /// [maintenance] may report migration or rewrite completion after the entry
  /// has already been returned. Awaiting the entry never awaits maintenance.
  const KachePersistenceRead({required this.entry, this.maintenance});

  /// The typed entry available to the cache immediately.
  final KachePersistedEntry<T> entry;

  /// Optional migration or rewrite work that completes independently.
  final Future<void>? maintenance;
}

/// Determines whether a client may close its persistence backend.
enum KachePersistenceOwnership {
  /// The backend is managed externally and must not be closed by the client.
  borrowed,

  /// The client owns the backend and closes it with the client lifecycle.
  owned,
}

/// Operations that can fail while interacting with persistence.
enum KachePersistenceOperation {
  /// Reading a persisted entry.
  read,

  /// Writing a persisted entry.
  write,

  /// Deleting a persisted entry.
  delete,

  /// Clearing entries in one namespace.
  clearNamespace,

  /// Clearing every persisted entry.
  clear,

  /// Closing the persistence backend.
  close,
}

/// Stages at which a persistence operation can fail.
enum KachePersistenceStage {
  /// Backend access or lifecycle handling.
  backend,

  /// Encoding a typed value for storage.
  encode,

  /// Decoding a stored value into a typed value.
  decode,

  /// Migrating a stored value between backend-defined versions.
  migration,
}

/// A persistence failure with its operation, stage, cause, and stack trace.
///
/// [toString] is intentionally sanitized: it does not render [cause] and this
/// exception does not contain cache keys or payloads.
final class KachePersistenceException implements Exception {
  /// Creates a persistence exception without transforming the original error.
  const KachePersistenceException({
    required this.operation,
    required this.stage,
    required this.cause,
    required this.stackTrace,
  });

  /// The persistence operation that failed.
  final KachePersistenceOperation operation;

  /// The stage within [operation] that failed.
  final KachePersistenceStage stage;

  /// The original failure object.
  final Object cause;

  /// The original stack trace associated with [cause].
  final StackTrace stackTrace;

  @override
  String toString() =>
      'KachePersistenceException('
      'operation: ${operation.name}, stage: ${stage.name})';
}

String _validateFingerprint(String fingerprint) {
  if (fingerprint.trim().isEmpty) {
    throw const KachePersistenceBindingException._emptyFingerprint();
  }
  return fingerprint;
}
