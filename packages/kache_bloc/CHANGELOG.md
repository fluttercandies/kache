## 3.1.1

- Fixed `KacheCubit` emitting older snapshots when concurrent commands resolved
  after newer resource updates; state revisions are now strictly increasing.

## 3.1.0

- Updated the re-exported Kache dependency to `^3.1.0`; Bloc and Cubit state
  ownership behavior is unchanged.

## 3.0.0

- Updated the re-exported Kache dependency to `^3.0.0`; Bloc and Cubit state
  ownership behavior is unchanged.

## 2.0.1

- Made Cubit close idempotent during synchronous Bloc observer callbacks.

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
