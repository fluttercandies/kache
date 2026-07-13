import 'failure.dart';
import 'key.dart';

/// Stable kinds emitted by [KacheClient.events].
enum KacheEventKind {
  /// A persistence read started.
  persistenceReadStarted,

  /// A persistence read produced a hit or miss without failure.
  persistenceReadSucceeded,

  /// A persistence write or maintenance operation started.
  persistenceWriteStarted,

  /// A persistence write or maintenance operation completed.
  persistenceWriteSucceeded,

  /// A fetcher invocation started.
  fetchStarted,

  /// A fetcher produced data accepted by the cache.
  fetchSucceeded,

  /// Data was set or atomically updated by a command.
  dataSet,

  /// A key was explicitly invalidated.
  invalidated,

  /// A key was explicitly removed.
  removed,

  /// A namespace or global clear started.
  clearStarted,

  /// A namespace or global clear completed.
  clearCompleted,

  /// An operation produced a classified failure.
  failure,

  /// The client finished closing.
  clientClosed,
}

/// A non-payload cache lifecycle event.
final class KacheEvent {
  /// Creates an event for a key, namespace, or global operation.
  KacheEvent({
    required this.kind,
    required DateTime occurredAt,
    this.key,
    this.namespace,
    this.debugName,
    this.failure,
  }) : occurredAt = occurredAt.toUtc() {
    if (key != null && namespace != null) {
      throw ArgumentError('An event cannot target both key and namespace.');
    }
  }

  /// The stable event kind.
  final KacheEventKind kind;

  /// UTC time at which the event was emitted.
  final DateTime occurredAt;

  /// Affected key for key-scoped events.
  final KacheKey? key;

  /// Affected namespace for namespace-scoped events.
  final KacheNamespace? namespace;

  /// Optional caller-supplied non-sensitive label.
  final String? debugName;

  /// Classified failure for [KacheEventKind.failure].
  final KacheFailure? failure;

  /// The non-sensitive operation scope.
  KacheFailureScope get scope => key != null
      ? KacheFailureScope.key
      : namespace != null
      ? KacheFailureScope.namespace
      : KacheFailureScope.global;

  @override
  String toString() =>
      'KacheEvent(kind: ${kind.name}, scope: ${scope.name}, '
      'hasFailure: ${failure != null})';
}

/// Receives cache events synchronously after state is committed.
typedef KacheObserver = void Function(KacheEvent event);
