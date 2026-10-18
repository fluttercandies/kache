## 3.1.1

- Published READMEs now load the Kache logo from an absolute URL, because
  pub.dev does not render relative README images, and add pub, CI, and license
  badges.

## 3.1.0

- Updated the re-exported Kache Riverpod dependency to `^3.1.0`; Hooks
  Riverpod lifecycle behavior is unchanged.

## 3.0.0

- Updated the re-exported Kache Riverpod dependency to `^3.0.0`; Hooks
  Riverpod lifecycle behavior is unchanged.

## 2.0.0

- Added `KacheProviderBinding.cancel()` without creating a second resource or
  cancellation state.
- Verified HookConsumerWidget lifecycle and provider rebuild behavior with
  Hooks Riverpod 3.4.2.
- Adopted the core 2.0 event and cancellation contracts.

## 1.2.0

- Added `useKacheProvider` for consuming existing Kache providers from
  `HookConsumerWidget`.
- Added `KacheProviderBinding` with snapshot, notifier, resource, lifecycle,
  and cache command access without duplicate resource ownership.
- Watches both provider state and notifier identity as widget build
  dependencies, following Riverpod's `read`/`watch` guidance.
- Preserved native Riverpod family, override, auto-dispose, and keep-alive
  behavior.
