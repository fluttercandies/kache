## 3.1.1

- Checks connectivity again whenever the app resumes, so a recovery missed
  while platforms drop background events (connectivity_plus on iOS) still
  produces the `unavailable -> available` transition. A change event that
  arrives during the check wins over its result.
- Added the optional `binding` constructor parameter to enable resume checks
  with an injected `Connectivity`.
- Only a result made entirely of `ConnectivityResult.none` maps to
  `unavailable`; mixed results now map to `available`.
- A subscriber that arrives after a failed check with no known state triggers
  a new check instead of receiving nothing.
- Paused subscribers resume with only the newest state instead of replaying
  buffered history, and streams returned after `close()` are broadcast like
  live streams.

## 3.1.0

- Updated the re-exported Kache dependency to `^3.1.0`; connectivity recovery
  and lifecycle behavior is unchanged.

## 3.0.0

- Updated the re-exported Kache dependency to `^3.0.0`; connectivity recovery
  and lifecycle behavior is unchanged.

## 2.0.1

- Made close independent of paused or reentrant state subscribers and stalled
  platform cancellation while retaining immediately reported errors.

## 2.0.0

- Verified connectivity_plus 7.3.1 while retaining the compatible 7.3.0 floor.
- Updated the Kache core range for typed network events, reconnect traces, and
  paired owned-network close events.

## 1.2.0

- Updated connectivity_plus to 7.3.0.
- Updated the Kache core compatibility range for the coordinated 1.2 release.

## 1.1.0

- Updated the core dependency for the new snapshot rendering and hardened
  persistence contracts.
- Kept reconnect state mapping and ownership behavior unchanged.

## 1.0.1

- Updated connectivity_plus to 7.2.0.
- Lowered the verified requirements to Dart 3.5 and Flutter 3.24, while
  documenting the plugin's current native platform toolchain requirements.

## 1.0.0

- Initial release of the official connectivity_plus network recovery adapter.
- Added replayed availability state, initial-check race protection, duplicate
  suppression, observable platform errors, and idempotent close semantics.
