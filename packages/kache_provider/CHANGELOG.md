## 3.1.0

- Updated the re-exported Kache Flutter dependency to `^3.1.0`, which stops
  provided controllers from replaying stale snapshots on page entry.

## 3.0.0

- Updated the re-exported Kache Flutter dependency to `^3.0.0`; Provider
  controller and consumer behavior is unchanged.

## 2.0.1

- Made client replacement transactional so a failed controller construction
  preserves the active Provider binding.

## 2.0.0

- Exposed key-scoped cancellation through the existing `KacheController`.
- Adopted the core 2.0 event and cancellation contracts without duplicating
  controller or resource state.

## 1.2.0

- Updated the Kache Flutter compatibility range for the coordinated 1.2
  release.

## 1.1.0

- Exposed the new `KacheSnapshot` rendering and data-mapping APIs through
  Provider controllers and consumers.
- Locked controller refresh commands to `Future<KacheSnapshot<T>>`.

## 1.0.1

- Lowered the verified requirements to Dart 3.5 and Flutter 3.24.

## 1.0.0

- Initial release of Provider widgets, consumer, and context helpers backed by
  `KacheController`.
