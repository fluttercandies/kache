import 'dart:collection';

import 'cancellation.dart';
import 'failure.dart';
import 'key.dart';
import 'persistence.dart';
import 'policy.dart';

/// Context supplied to every query fetch operation.
final class KacheFetchContext {
  /// Creates a fetch context with optional cooperative [cancellation].
  const KacheFetchContext({this.cancellation = KacheCancellationToken.none});

  /// Cooperative cancellation requested by cache lifecycle operations.
  final KacheCancellationToken cancellation;

  /// Whether cancellation has been requested.
  bool get isCancelled => cancellation.isCancelled;

  /// Throws [KacheCancelledException] after cancellation is requested.
  void throwIfCancelled() => cancellation.throwIfCancelled();
}

/// Fetches a typed value for a cache query.
typedef KacheFetcher<T> = Future<T> Function(KacheFetchContext context);

/// Controls where a query stores values during its lifecycle.
enum KacheStorageMode {
  /// Store only in the active client's in-memory registry.
  memory,

  /// Store in memory and in the configured persistence backend.
  persisted,

  /// Retain state only while a resource handle is active.
  none,
}

/// An immutable declaration of how to obtain and cache one typed value.
final class KacheQuery<T> {
  /// Creates a process-memory query.
  factory KacheQuery.memory({
    required KacheKey key,
    KacheFetcher<T>? fetch,
    KachePolicy? policy,
    String? debugName,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => KacheQuery<T>._create(
    key: key,
    fetch: fetch,
    binding: null,
    storageMode: KacheStorageMode.memory,
    policy: policy ?? KachePolicy.staleWhileRevalidate(),
    debugName: debugName,
    metadata: metadata,
  );

  /// Creates a query backed by an opaque persistence [binding].
  factory KacheQuery.persisted({
    required KacheKey key,
    KacheFetcher<T>? fetch,
    required KachePersistenceBinding<T> binding,
    KachePolicy? policy,
    String? debugName,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => KacheQuery<T>._create(
    key: key,
    fetch: fetch,
    binding: binding,
    storageMode: KacheStorageMode.persisted,
    policy: policy ?? KachePolicy.staleWhileRevalidate(),
    debugName: debugName,
    metadata: metadata,
  );

  /// Creates a query that always fetches and never reads or writes cache data.
  ///
  /// [refreshInterval] enables active polling without enabling storage.
  factory KacheQuery.networkOnly({
    required KacheKey key,
    required KacheFetcher<T> fetch,
    Duration? refreshInterval,
    String? debugName,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => KacheQuery<T>._create(
    key: key,
    fetch: fetch,
    binding: null,
    storageMode: KacheStorageMode.none,
    policy: KachePolicy.staleWhileRevalidate(refreshInterval: refreshInterval),
    debugName: debugName,
    metadata: metadata,
  );

  factory KacheQuery._create({
    required KacheKey key,
    required KacheFetcher<T>? fetch,
    required KachePersistenceBinding<T>? binding,
    required KacheStorageMode storageMode,
    required KachePolicy policy,
    required String? debugName,
    required Map<String, Object?> metadata,
  }) {
    if (fetch == null && !policy.isCacheOnly) {
      throw const KacheConfigurationException(
        'fetch_required',
        'A fetcher is required unless the query policy is cache-only.',
      );
    }
    if (debugName != null && debugName.trim().isEmpty) {
      throw const KacheConfigurationException(
        'invalid_debug_name',
        'A debug name must contain at least one non-whitespace character.',
      );
    }
    return KacheQuery<T>._(
      key: key,
      fetch: fetch,
      binding: binding,
      storageMode: storageMode,
      policy: policy,
      debugName: debugName,
      metadata: UnmodifiableMapView<String, Object?>(
        Map<String, Object?>.of(metadata),
      ),
    );
  }

  const KacheQuery._({
    required this.key,
    required this.fetch,
    required this.binding,
    required this.storageMode,
    required this.policy,
    required this.debugName,
    required this.metadata,
  });

  /// Stable cache identity shared by compatible handles.
  final KacheKey key;

  /// The optional network or service fetch operation.
  final KacheFetcher<T>? fetch;

  /// Opaque backend-specific binding for persisted queries.
  final KachePersistenceBinding<T>? binding;

  /// Where this query stores data.
  final KacheStorageMode storageMode;

  /// Freshness and lifecycle revalidation rules.
  final KachePolicy policy;

  /// Optional caller-supplied non-sensitive observer label.
  final String? debugName;

  /// Immutable caller-supplied non-sensitive observer metadata.
  final Map<String, Object?> metadata;

  /// The reified Dart value type used for shared-key compatibility checks.
  Type get valueType => T;
}
