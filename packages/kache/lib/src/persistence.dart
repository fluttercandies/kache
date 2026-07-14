import 'dart:async';

import 'key.dart';

/// A storage backend that persists typed cache entries.
///
/// Implementations own serialization, migrations, and physical storage. The
/// core library passes typed values and an opaque [KachePersistenceBinding]
/// without prescribing a record format.
///
/// Implementations must wrap backend-defined failures in
/// [KachePersistenceException] using the operation being performed and one of
/// the stages allowed by that exception's constructor.
abstract interface class KachePersistenceBackend {
  /// Reads the entry for [key], or returns `null` when no entry exists.
  ///
  /// The [binding] describes backend-specific handling for `T`. Implementations
  /// should call [KachePersistenceBinding.ensureBackend] before using it.
  /// Storage access failures use [KachePersistenceStage.backend], initial value
  /// interpretation failures use [KachePersistenceStage.decode], and deferred
  /// maintenance failures use [KachePersistenceStage.migration].
  Future<KachePersistenceRead<T>?> read<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
  });

  /// Writes a typed [entry] for [key] using [binding].
  ///
  /// Implementations should call [KachePersistenceBinding.ensureBackend]
  /// before using the binding. Value conversion failures use
  /// [KachePersistenceStage.encode], while storage access failures use
  /// [KachePersistenceStage.backend].
  Future<void> write<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
    required KachePersistedEntry<T> entry,
  });

  /// Deletes the persisted entry for [key] when present.
  ///
  /// Failures must use [KachePersistenceOperation.delete] with
  /// [KachePersistenceStage.backend].
  Future<void> delete({required KacheKey key});

  /// Deletes every entry in [namespace].
  ///
  /// Failures must use [KachePersistenceOperation.clearNamespace] with
  /// [KachePersistenceStage.backend].
  Future<void> clearNamespace({required KacheNamespace namespace});

  /// Deletes every entry managed by this backend.
  ///
  /// Failures must use [KachePersistenceOperation.clear] with
  /// [KachePersistenceStage.backend].
  Future<void> clear();

  /// Releases resources owned by this backend.
  ///
  /// Client code only calls this for a backend configured with
  /// [KachePersistenceOwnership.owned]. This operation must be idempotent. When
  /// its future completes, owned resources must be safely released. Subsequent
  /// operations other than [close] must fail with a [KachePersistenceException]
  /// for the attempted operation at [KachePersistenceStage.backend]. A close
  /// failure uses [KachePersistenceOperation.close] at that same stage.
  Future<void> close();
}

/// Opaque, backend-specific configuration for persisting values of type `T`.
///
/// External storage packages extend this class to attach their own mapping or
/// migration configuration. Core code only uses [backend] and [fingerprint].
abstract class KachePersistenceBinding<T> {
  /// Creates a binding owned by [backend] with a stable [fingerprint].
  ///
  /// The fingerprint must contain at least one non-whitespace character. It
  /// must deterministically and uniquely identify the complete storage
  /// interpretation represented by this binding. Equal fingerprints must mean
  /// that every persisted value is interpreted identically; any change to an
  /// interpretation rule requires a different fingerprint.
  ///
  /// Throws [KachePersistenceBindingException] for an invalid fingerprint.
  KachePersistenceBinding({required this.backend, required String fingerprint})
      : fingerprint = _validateFingerprint(fingerprint);

  /// The only backend instance that may use this binding.
  final KachePersistenceBackend backend;

  /// A deterministic, unique identity for the complete storage interpretation.
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
  }) =>
      KachePersistedMetadata._(fetchedAt.toUtc(), isInvalidated);

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

/// Lazily performs backend-defined persistence maintenance.
typedef KachePersistenceMaintenance = FutureOr<void> Function();

/// A successful persistence read and optional lazy maintenance work.
final class KachePersistenceRead<T> {
  /// Creates a read result containing [entry].
  ///
  /// [maintenance] is not invoked by construction. Core code may read [entry]
  /// immediately and later call [runMaintenance] to observe migration or
  /// rewrite completion.
  KachePersistenceRead({
    required this.entry,
    KachePersistenceMaintenance? maintenance,
  }) : _maintenance = maintenance;

  /// The typed entry available to the cache immediately.
  final KachePersistedEntry<T> entry;

  final KachePersistenceMaintenance? _maintenance;
  Future<void>? _maintenanceFuture;

  /// Whether this read includes deferred migration or rewrite work.
  bool get hasMaintenance => _maintenance != null;

  /// Starts maintenance once and returns its shared result future.
  ///
  /// The first call invokes the callback through [Future.sync], so synchronous
  /// throws become asynchronous errors. Later calls return the identical future
  /// and never execute the callback again. When [hasMaintenance] is `false`,
  /// the shared future completes successfully without performing work.
  Future<void> runMaintenance() {
    final existing = _maintenanceFuture;
    if (existing != null) {
      return existing;
    }

    final completer = Completer<void>();
    final shared = completer.future;
    _maintenanceFuture = shared;

    final maintenance = _maintenance;
    if (maintenance == null) {
      completer.complete();
    } else {
      unawaited(
        Future<void>.sync(maintenance).then<void>(
          (_) => completer.complete(),
          onError: (Object error, StackTrace stackTrace) {
            completer.completeError(error, stackTrace);
          },
        ),
      );
    }
    return shared;
  }
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
  ///
  /// Valid stages are backend, decode, and migration for read; backend and
  /// encode for write; and backend only for delete, namespace clear, clear, and
  /// close. Throws [ArgumentError] without rendering [cause] when the operation
  /// and stage combination is invalid.
  factory KachePersistenceException({
    required KachePersistenceOperation operation,
    required KachePersistenceStage stage,
    required Object cause,
    required StackTrace stackTrace,
  }) {
    if (!_isValidPersistenceStage(operation, stage)) {
      throw ArgumentError(
        'Persistence stage ${stage.name} is not valid for '
        'operation ${operation.name}.',
      );
    }
    return KachePersistenceException._(
      operation: operation,
      stage: stage,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  const KachePersistenceException._({
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
  String toString() => 'KachePersistenceException('
      'operation: ${operation.name}, stage: ${stage.name})';
}

String _validateFingerprint(String fingerprint) {
  if (fingerprint.trim().isEmpty) {
    throw const KachePersistenceBindingException._emptyFingerprint();
  }
  return fingerprint;
}

bool _isValidPersistenceStage(
  KachePersistenceOperation operation,
  KachePersistenceStage stage,
) =>
    switch (operation) {
      KachePersistenceOperation.read =>
        stage == KachePersistenceStage.backend ||
            stage == KachePersistenceStage.decode ||
            stage == KachePersistenceStage.migration,
      KachePersistenceOperation.write =>
        stage == KachePersistenceStage.backend ||
            stage == KachePersistenceStage.encode,
      KachePersistenceOperation.delete ||
      KachePersistenceOperation.clearNamespace ||
      KachePersistenceOperation.clear ||
      KachePersistenceOperation.close =>
        stage == KachePersistenceStage.backend,
    };
