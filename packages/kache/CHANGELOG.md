## 3.1.0

- Documented the persistence backend synchronous-prefix contract: work that
  runs before `read` or `write` first yields must not scale with payload size,
  because the core may call them inside a listener's synchronous stack such as
  a widget build.

## 3.0.0

- Changed persistence reads to return `KachePersistenceRead<T>`, which exposes
  typed data immediately while backend-defined maintenance runs lazily.
- Added explicit persistence migration failure classification and made writes
  under a new binding fingerprint authoritatively replace older entries.

## 2.0.1

- Prevented late persistence reads and freshness reclassification from
  overwriting newer fetch state.
- Made close continue independent cleanup after failures and return without
  waiting on paused event listeners or stalled network cancellation callbacks.
- Kept close idempotent during synchronous event callbacks and preserved the
  first observed cleanup failure during error aggregation.

## 2.0.0

- Replaced the legacy event enum with paired `kind`, `phase`, and `trigger`
  operation events, trace/span correlation, timing, query context, revisions,
  lookup/network details, and complete close failure reporting.
- Made successful event data available to trusted in-process subscribers while
  keeping event, failure, and cancellation string output sanitized.
- Added `KacheResource.cancel`, `KacheClient.cancel`, and `cancelAll` with
  reasoned cooperative cancellation, immediate logical completion, snapshot
  restoration, and permanent isolation of late non-cooperative results.
- Preserved deterministic single-flight, generation, clear, write-drain, and
  owned dependency lifecycle semantics under cancellation and event reentry.

## 1.2.0

- Aligned the core release with the new Flutter Hooks integration packages.
- Kept the core API and zero-third-party runtime dependency unchanged.

## 1.1.0

- Added exhaustive `when`, partial `maybeWhen`, and metadata-preserving
  `mapData` APIs to `KacheSnapshot`.
- Added a dedicated retained-data refresh error branch so rendering helpers
  cannot silently hide failed refreshes.
- Hardened persistence error normalization against backend operation contract
  mismatches while preserving original errors and stack traces.

## 1.0.1

- Lowered the verified Dart SDK requirement from 3.9 to 3.5.

## 1.0.0

- Initial release of the type-safe stale-while-revalidate core.
- Added deterministic concurrency, cache commands, events, lifecycle control,
  memory persistence, and the custom persistence protocol.
- Added active-resource polling, cache-layer lookup events, and concise
  snapshot state getters.
- Added pluggable network recovery, reconnect policies, lifecycle events, and
  observable connectivity failures.
- Fixed concurrent load policy and overlapping clear revalidation races.
