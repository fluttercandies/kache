## 1.2.0

- Added `KacheProvider` and `KacheProviderFamily` aliases while preserving
  native Riverpod provider behavior.
- Locked interoperability for select, observers, scoped dependencies,
  overrides, refresh/invalidate, subscriptions, and provider lifecycle.
- Documented build-time `watch`, event-time `read`, and scoped dependency
  declarations in line with Riverpod 3.3.2 guidance.
- Documented the unsupported `overrideWithBuild` path and the distinct
  Riverpod build-error and Kache fetch-failure channels.
- Removed the misleading synchronous provider retry option after verifying
  that Riverpod 3.3.2 does not invoke it for `NotifierProvider` build errors.

## 1.1.0

- Documented and tested named-record arguments for multi-parameter provider
  families.
- Exposed the new lossless `KacheSnapshot` rendering helpers without adding a
  second `AsyncValue` state source.

## 1.0.1

- Lowered the verified Dart SDK requirement to the Riverpod floor of 3.7.

## 1.0.0

- Initial release of Riverpod provider, family, auto-dispose, keep-alive, and
  notifier command integration for Kache.
- Preserved manual keep-alive intent across dependency-driven rebuilds.
