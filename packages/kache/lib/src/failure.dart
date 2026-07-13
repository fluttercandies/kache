import 'key.dart';
import 'persistence.dart';

/// Stable categories for failures surfaced by Kache operations.
enum KacheFailureKind {
  /// An incompatible query, client, or binding configuration.
  configuration,

  /// No usable cache value exists for a cache-only query.
  cacheMiss,

  /// An explicit refresh was requested without a fetcher.
  fetchUnavailable,

  /// Persistence failed while reading or interpreting a value.
  persistenceRead,

  /// Persistence failed while encoding or writing a value.
  persistenceWrite,

  /// A query fetcher failed.
  fetch,

  /// Deleting one persisted value failed.
  delete,

  /// Clearing a namespace or backend failed.
  clear,

  /// An operation was cancelled or used after lifecycle shutdown.
  lifecycle,
}

/// A classified failure that retains the original exception and stack trace.
///
/// Its string representation is intentionally sanitized and never includes
/// the key, original exception, or payload values.
final class KacheFailure {
  /// Creates a classified failure.
  ///
  /// [persistenceStage] is only meaningful for persistence-related kinds.
  KacheFailure({
    required this.kind,
    required this.key,
    required this.cause,
    required this.stackTrace,
    this.persistenceStage,
  }) {
    final isPersistence =
        kind == KacheFailureKind.persistenceRead ||
        kind == KacheFailureKind.persistenceWrite ||
        kind == KacheFailureKind.delete ||
        kind == KacheFailureKind.clear;
    if (!isPersistence && persistenceStage != null) {
      throw ArgumentError.value(
        persistenceStage,
        'persistenceStage',
        'Only persistence failures may include a persistence stage.',
      );
    }
  }

  /// The stable failure category.
  final KacheFailureKind kind;

  /// The affected cache key. It is never rendered by [toString].
  final KacheKey key;

  /// The original error object.
  final Object cause;

  /// The original stack trace.
  final StackTrace stackTrace;

  /// The backend-defined persistence stage, when applicable.
  final KachePersistenceStage? persistenceStage;

  @override
  String toString() {
    final stage = persistenceStage;
    return stage == null
        ? 'KacheFailure(kind: ${kind.name})'
        : 'KacheFailure(kind: ${kind.name}, stage: ${stage.name})';
  }
}

/// Thrown for invalid cache declarations or incompatible query reuse.
final class KacheConfigurationException implements Exception {
  /// Creates a sanitized configuration exception with a stable [code].
  const KacheConfigurationException(this.code, this.message);

  /// A stable machine-readable reason.
  final String code;

  /// A non-sensitive explanation.
  final String message;

  @override
  String toString() => 'KacheConfigurationException($code): $message';
}

/// Thrown when an operation targets a disposed resource or closed client.
final class KacheLifecycleException implements Exception {
  /// Creates a sanitized lifecycle exception with a stable [code].
  const KacheLifecycleException(this.code, this.message);

  /// A stable machine-readable reason.
  final String code;

  /// A non-sensitive explanation.
  final String message;

  @override
  String toString() => 'KacheLifecycleException($code): $message';
}

/// Cause used by [KacheFailureKind.cacheMiss].
final class KacheCacheMissException implements Exception {
  /// Creates a cache-miss exception.
  const KacheCacheMissException();

  @override
  String toString() => 'KacheCacheMissException: No usable cache data exists.';
}

/// Cause used when an explicit refresh has no configured fetcher.
final class KacheFetchUnavailableException implements Exception {
  /// Creates a fetch-unavailable exception.
  const KacheFetchUnavailableException();

  @override
  String toString() =>
      'KacheFetchUnavailableException: No fetcher is configured.';
}
