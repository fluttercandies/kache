import 'command.dart';
import 'failure.dart';
import 'policy.dart';

/// The primary lifecycle phase of a cache snapshot.
enum KachePhase {
  /// No load has produced data or a terminal failure.
  idle,

  /// The first value is loading and no data is available yet.
  loading,

  /// Data is available, optionally while refreshing or with a refresh failure.
  ready,

  /// No data is available and an operation failed.
  failure,
}

/// Where the currently visible data originated.
enum KacheDataSource {
  /// An active in-memory cache entry.
  memory,

  /// A persistence backend read.
  persistence,

  /// A query fetcher.
  fetch,

  /// An explicit set or update command.
  manual,
}

/// The current persistence sub-state for a persisted query.
enum KachePersistencePhase {
  /// Persistence has not started.
  idle,

  /// A backend read is in progress.
  reading,

  /// The backend has no value for the key.
  absent,

  /// A write or migration is in progress.
  writing,

  /// The latest visible data is persisted.
  persisted,

  /// Persistence failed while data may remain usable in memory.
  failed,
}

/// Persistence status stored orthogonally to the primary snapshot phase.
final class KachePersistenceState {
  /// Creates an idle persistence state.
  const KachePersistenceState.idle()
    : phase = KachePersistencePhase.idle,
      failure = null;

  /// Creates a reading persistence state.
  const KachePersistenceState.reading()
    : phase = KachePersistencePhase.reading,
      failure = null;

  /// Creates an absent persistence state.
  const KachePersistenceState.absent()
    : phase = KachePersistencePhase.absent,
      failure = null;

  /// Creates a writing persistence state.
  const KachePersistenceState.writing()
    : phase = KachePersistencePhase.writing,
      failure = null;

  /// Creates a successfully persisted state.
  const KachePersistenceState.persisted()
    : phase = KachePersistencePhase.persisted,
      failure = null;

  /// Creates a failed persistence state retaining [failure].
  KachePersistenceState.failed(this.failure)
    : phase = KachePersistencePhase.failed {
    if (failure == null) {
      throw ArgumentError.notNull('failure');
    }
  }

  /// The persistence lifecycle phase.
  final KachePersistencePhase phase;

  /// The persistence failure for [KachePersistencePhase.failed].
  final KacheFailure? failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KachePersistenceState &&
          phase == other.phase &&
          identical(failure, other.failure);

  @override
  int get hashCode => Object.hash(phase, identityHashCode(failure));
}

/// An immutable, internally consistent view of one cached query.
///
/// Data presence is represented separately from the value, so `null` is a
/// valid cached value when `T` is nullable.
final class KacheSnapshot<T> {
  /// Creates an empty idle snapshot.
  factory KacheSnapshot.idle({
    int revision = 0,
    KachePersistenceState? persistence,
  }) => KacheSnapshot<T>._empty(
    phase: KachePhase.idle,
    revision: _validateRevision(revision),
    persistence: persistence,
  );

  /// Creates an empty first-load snapshot.
  factory KacheSnapshot.loading({
    int revision = 0,
    KachePersistenceState? persistence,
  }) => KacheSnapshot<T>._empty(
    phase: KachePhase.loading,
    revision: _validateRevision(revision),
    persistence: persistence,
  );

  /// Creates a snapshot containing visible [data].
  factory KacheSnapshot.ready({
    required T data,
    required KacheFreshness freshness,
    required KacheDataSource source,
    required DateTime fetchedAt,
    bool isRefreshing = false,
    KacheFailure? failure,
    int revision = 0,
    KachePersistenceState? persistence,
  }) => KacheSnapshot<T>._(
    phase: KachePhase.ready,
    hasData: true,
    data: data,
    isRefreshing: isRefreshing,
    freshness: freshness,
    source: source,
    failure: failure,
    fetchedAt: fetchedAt.toUtc(),
    revision: _validateRevision(revision),
    persistence: persistence,
  );

  /// Creates a terminal no-data snapshot retaining [failure].
  factory KacheSnapshot.failed({
    required KacheFailure failure,
    int revision = 0,
    KachePersistenceState? persistence,
  }) => KacheSnapshot<T>._(
    phase: KachePhase.failure,
    hasData: false,
    data: null,
    isRefreshing: false,
    freshness: null,
    source: null,
    failure: failure,
    fetchedAt: null,
    revision: _validateRevision(revision),
    persistence: persistence,
  );

  const KacheSnapshot._({
    required this.phase,
    required this.hasData,
    required Object? data,
    required this.isRefreshing,
    required this.freshness,
    required this.source,
    required this.failure,
    required this.fetchedAt,
    required this.revision,
    required this.persistence,
  }) : _data = data;

  KacheSnapshot._empty({
    required KachePhase phase,
    required int revision,
    required KachePersistenceState? persistence,
  }) : this._(
         phase: phase,
         hasData: false,
         data: null,
         isRefreshing: false,
         freshness: null,
         source: null,
         failure: null,
         fetchedAt: null,
         revision: revision,
         persistence: persistence,
       );

  /// The primary lifecycle phase.
  final KachePhase phase;

  /// Whether this snapshot contains a value, including a nullable `null` value.
  final bool hasData;

  final Object? _data;

  /// The visible value, or `null` when absent or when cached `T` is nullable.
  T? get dataOrNull => hasData ? _data as T : null;

  /// The visible value, throwing [StateError] when [hasData] is false.
  T get requireData {
    if (!hasData) {
      throw StateError('KacheSnapshot has no data.');
    }
    return _data as T;
  }

  /// Whether a fetch is running while old data remains visible.
  final bool isRefreshing;

  /// Freshness of visible data, or `null` without data.
  final KacheFreshness? freshness;

  /// Origin of visible data, or `null` without data.
  final KacheDataSource? source;

  /// The latest relevant operation failure, if any.
  final KacheFailure? failure;

  /// UTC time at which visible data was fetched or manually set.
  final DateTime? fetchedAt;

  /// Monotonically increasing state revision within the shared entry.
  final int revision;

  /// Persistence status for persisted queries, otherwise `null`.
  final KachePersistenceState? persistence;

  /// Throws [KacheCommandException] when this snapshot contains failures.
  void throwIfFailed() {
    final failures = <KacheFailure>[];
    final primary = failure;
    if (primary != null) {
      failures.add(primary);
    }
    final persistenceFailure = persistence?.failure;
    if (persistenceFailure != null && !identical(persistenceFailure, primary)) {
      failures.add(persistenceFailure);
    }
    if (failures.isNotEmpty) {
      throw KacheCommandException(failures);
    }
  }

  @override
  String toString() =>
      'KacheSnapshot<$T>('
      'phase: ${phase.name}, hasData: $hasData, '
      'isRefreshing: $isRefreshing, revision: $revision)';
}

int _validateRevision(int revision) {
  if (revision < 0) {
    throw ArgumentError.value(revision, 'revision', 'Must be non-negative.');
  }
  return revision;
}
