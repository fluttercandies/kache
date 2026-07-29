## 2.0.0

- Exposed key-scoped cancellation through the returned `KacheController`.
- Added cancellation rebuild and late-result isolation coverage.
- Adopted the core 2.0 event and cancellation contracts without adding Hook
  state or resource ownership.

## 1.2.0

- Added `useKache` with `KacheScope` and explicit-client resolution.
- Added automatic controller loading, same-key updates, key/client rebinding,
  snapshot rebuilds, and lifecycle cleanup.
- Added the concise `KacheController.snapshot` alias.
