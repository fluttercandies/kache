## 2.0.0

- Added key-scoped `cancel()` to `KacheBlocBinding` and `KacheCubit`.
- Adopted the core 2.0 trace/span event and reasoned cancellation contracts.

## 1.2.0

- Updated the Kache core compatibility range for the coordinated 1.2 release.

## 1.1.0

- Exposed the new `KacheSnapshot` rendering and data-mapping APIs through Bloc
  and Cubit state.
- Locked command return types to `Future<KacheSnapshot<T>>` across bindings and
  cubits.

## 1.0.1

- Lowered the verified Dart SDK requirement from 3.9 to 3.5.

## 1.0.0

- Initial release of `KacheCubit` and the composable `KacheBlocBinding` for
  pure Dart Bloc applications.
