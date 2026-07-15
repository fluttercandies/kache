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
