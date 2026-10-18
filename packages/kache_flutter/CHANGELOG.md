## 3.1.1

- Published READMEs now load the Kache logo from an absolute URL, because
  pub.dev does not render relative README images, and add pub, CI, and license
  badges.

## 3.1.0

- Fixed `KacheController` rolling back to stale snapshots. Subscription
  replay and late command results with an older revision are now ignored,
  which removes a redundant rebuild on page entry and stops `KacheListener`
  from reporting false `ready -> idle -> loading` transitions.
- Added optional `KacheBuilder.buildWhen` (mirroring `KacheListener.listenWhen`)
  to skip rebuilds such as persistence-only changes. A client or key change
  always rebuilds.
- Updated the re-exported Kache dependency to `^3.1.0`.

## 3.0.0

- Updated the re-exported Kache dependency to `^3.0.0` for the persistence
  contract cutover; Flutter controller and widget behavior is unchanged.

## 2.0.1

- Made different-key query and client replacements transactional, preserving
  the active controller when replacement validation fails.

## 2.0.0

- Added `KacheController.cancel()` for the current key's shared fetch.
- Adopted the core 2.0 trace/span event and reasoned cancellation contracts.
- Preserved controller key-generation isolation and Flutter lifecycle behavior.

## 1.2.0

- Added the supported foundation for `kache_flutter_hooks` while preserving
  the existing controller and widget APIs.

## 1.1.0

- Exposed the new `KacheSnapshot.when`, `maybeWhen`, and `mapData` APIs through
  the Flutter integration.
- Updated the Flutter rendering contract for explicit idle and retained-data
  refresh error states.

## 1.0.1

- Lowered the verified requirements to Dart 3.5 and Flutter 3.24.

## 1.0.0

- Initial release of Flutter scope, controller, builder, listener, and app
  lifecycle integration for Kache.
- Added automatic polling pause and resume across Flutter app lifecycle states.
- Added reconnect pause and resume across Flutter app lifecycle states.
- Prevented pending commands from an old key from updating a rebound
  controller.
