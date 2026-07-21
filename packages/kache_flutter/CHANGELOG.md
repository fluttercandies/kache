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
