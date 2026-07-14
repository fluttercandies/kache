/// Whether an automatic lifecycle action should revalidate cached data.
enum KacheRevalidation {
  /// Never revalidate for this lifecycle action.
  never,

  /// Revalidate only when cached data is stale or absent.
  ifStale,

  /// Revalidate whenever the lifecycle action occurs.
  always,
}

/// The freshness of a cache value that has not reached hard expiry.
enum KacheFreshness {
  /// The value is younger than the policy's stale threshold.
  fresh,

  /// The value is invalidated or has reached the stale threshold.
  stale,
}

/// Immutable rules for freshness, revalidation, retention, and memory GC.
final class KachePolicy {
  /// Creates a custom cache policy.
  factory KachePolicy({
    required Duration staleAfter,
    Duration? expireAfter,
    required KacheRevalidation refreshOnLoad,
    required KacheRevalidation refreshOnResume,
    required KacheRevalidation refreshOnReconnect,
    Duration? refreshInterval,
    bool retainDataOnError = true,
    Duration gcAfter = const Duration(minutes: 5),
  }) =>
      KachePolicy._validated(
        staleAfter: staleAfter,
        expireAfter: expireAfter,
        refreshOnLoad: refreshOnLoad,
        refreshOnResume: refreshOnResume,
        refreshOnReconnect: refreshOnReconnect,
        refreshInterval: refreshInterval,
        retainDataOnError: retainDataOnError,
        gcAfter: gcAfter,
        isCacheOnly: false,
      );

  /// Creates the default stale-while-revalidate policy.
  factory KachePolicy.staleWhileRevalidate({
    Duration staleAfter = Duration.zero,
    Duration? expireAfter,
    KacheRevalidation refreshOnLoad = KacheRevalidation.always,
    KacheRevalidation refreshOnResume = KacheRevalidation.always,
    KacheRevalidation refreshOnReconnect = KacheRevalidation.always,
    Duration? refreshInterval,
    bool retainDataOnError = true,
    Duration gcAfter = const Duration(minutes: 5),
  }) =>
      KachePolicy._validated(
        staleAfter: staleAfter,
        expireAfter: expireAfter,
        refreshOnLoad: refreshOnLoad,
        refreshOnResume: refreshOnResume,
        refreshOnReconnect: refreshOnReconnect,
        refreshInterval: refreshInterval,
        retainDataOnError: retainDataOnError,
        gcAfter: gcAfter,
        isCacheOnly: false,
      );

  /// Creates a cache-first policy with [freshFor] as its fresh window.
  factory KachePolicy.cacheFirst({
    required Duration freshFor,
    Duration? expireAfter,
    KacheRevalidation refreshOnLoad = KacheRevalidation.ifStale,
    KacheRevalidation refreshOnResume = KacheRevalidation.ifStale,
    KacheRevalidation refreshOnReconnect = KacheRevalidation.ifStale,
    Duration? refreshInterval,
    bool retainDataOnError = true,
    Duration gcAfter = const Duration(minutes: 5),
  }) =>
      KachePolicy._validated(
        staleAfter: freshFor,
        expireAfter: expireAfter,
        refreshOnLoad: refreshOnLoad,
        refreshOnResume: refreshOnResume,
        refreshOnReconnect: refreshOnReconnect,
        refreshInterval: refreshInterval,
        retainDataOnError: retainDataOnError,
        gcAfter: gcAfter,
        isCacheOnly: false,
      );

  /// Creates a policy that never fetches automatically.
  ///
  /// A query using this policy may still provide a fetcher for explicit
  /// refresh calls.
  factory KachePolicy.cacheOnly({
    Duration staleAfter = Duration.zero,
    Duration? expireAfter,
    bool retainDataOnError = true,
    Duration gcAfter = const Duration(minutes: 5),
  }) =>
      KachePolicy._validated(
        staleAfter: staleAfter,
        expireAfter: expireAfter,
        refreshOnLoad: KacheRevalidation.never,
        refreshOnResume: KacheRevalidation.never,
        refreshOnReconnect: KacheRevalidation.never,
        refreshInterval: null,
        retainDataOnError: retainDataOnError,
        gcAfter: gcAfter,
        isCacheOnly: true,
      );

  factory KachePolicy._validated({
    required Duration staleAfter,
    required Duration? expireAfter,
    required KacheRevalidation refreshOnLoad,
    required KacheRevalidation refreshOnResume,
    required KacheRevalidation refreshOnReconnect,
    required Duration? refreshInterval,
    required bool retainDataOnError,
    required Duration gcAfter,
    required bool isCacheOnly,
  }) {
    if (staleAfter.isNegative) {
      throw ArgumentError.value(
        staleAfter,
        'staleAfter',
        'Must be non-negative.',
      );
    }
    if (expireAfter case final expiry?) {
      if (expiry.isNegative) {
        throw ArgumentError.value(
          expiry,
          'expireAfter',
          'Must be non-negative.',
        );
      }
      if (expiry < staleAfter) {
        throw ArgumentError.value(
          expiry,
          'expireAfter',
          'Must be greater than or equal to staleAfter.',
        );
      }
    }
    if (gcAfter.isNegative) {
      throw ArgumentError.value(gcAfter, 'gcAfter', 'Must be non-negative.');
    }
    if (refreshInterval != null && refreshInterval <= Duration.zero) {
      throw ArgumentError.value(
        refreshInterval,
        'refreshInterval',
        'Must be greater than zero.',
      );
    }
    return KachePolicy._(
      staleAfter: staleAfter,
      expireAfter: expireAfter,
      refreshOnLoad: refreshOnLoad,
      refreshOnResume: refreshOnResume,
      refreshOnReconnect: refreshOnReconnect,
      refreshInterval: refreshInterval,
      retainDataOnError: retainDataOnError,
      gcAfter: gcAfter,
      isCacheOnly: isCacheOnly,
    );
  }

  const KachePolicy._({
    required this.staleAfter,
    required this.expireAfter,
    required this.refreshOnLoad,
    required this.refreshOnResume,
    required this.refreshOnReconnect,
    required this.refreshInterval,
    required this.retainDataOnError,
    required this.gcAfter,
    required this.isCacheOnly,
  });

  /// Age after which data is stale.
  final Duration staleAfter;

  /// Optional age at which data must no longer be emitted.
  final Duration? expireAfter;

  /// Automatic revalidation behavior when a query loads.
  final KacheRevalidation refreshOnLoad;

  /// Automatic revalidation behavior when its host application resumes.
  final KacheRevalidation refreshOnResume;

  /// Automatic revalidation behavior after network availability returns.
  final KacheRevalidation refreshOnReconnect;

  /// Optional interval between automatic refresh attempts while active.
  final Duration? refreshInterval;

  /// Whether a failed fetch keeps previously available data.
  final bool retainDataOnError;

  /// How long an unreferenced in-memory entry remains eligible for reuse.
  final Duration gcAfter;

  /// Whether automatic and missing-data fetches are disabled.
  final bool isCacheOnly;

  /// Classifies data at [now], returning `null` after hard expiry.
  KacheFreshness? freshnessAt({
    required DateTime fetchedAt,
    required DateTime now,
    bool isInvalidated = false,
  }) {
    final age = now.toUtc().difference(fetchedAt.toUtc());
    final normalizedAge = age.isNegative ? Duration.zero : age;
    final expiry = expireAfter;
    if (expiry != null && normalizedAge >= expiry) {
      return null;
    }
    if (isInvalidated || normalizedAge >= staleAfter) {
      return KacheFreshness.stale;
    }
    return KacheFreshness.fresh;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KachePolicy &&
          staleAfter == other.staleAfter &&
          expireAfter == other.expireAfter &&
          refreshOnLoad == other.refreshOnLoad &&
          refreshOnResume == other.refreshOnResume &&
          refreshOnReconnect == other.refreshOnReconnect &&
          refreshInterval == other.refreshInterval &&
          retainDataOnError == other.retainDataOnError &&
          gcAfter == other.gcAfter &&
          isCacheOnly == other.isCacheOnly;

  @override
  int get hashCode => Object.hash(
        staleAfter,
        expireAfter,
        refreshOnLoad,
        refreshOnResume,
        refreshOnReconnect,
        refreshInterval,
        retainDataOnError,
        gcAfter,
        isCacheOnly,
      );
}
