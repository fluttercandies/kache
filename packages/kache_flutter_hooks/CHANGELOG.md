## 3.1.1

- Published READMEs now load the Kache logo from an absolute URL, because
  pub.dev does not render relative README images, and add pub, CI, and license
  badges.

## 3.1.0

- Updated the re-exported Kache Flutter dependency to `^3.1.0`, which stops
  `useKache` controllers from replaying stale snapshots on page entry.

## 3.0.0

- Updated the re-exported Kache Flutter dependency to `^3.0.0`; Hook lifecycle
  and resource ownership behavior is unchanged.

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
