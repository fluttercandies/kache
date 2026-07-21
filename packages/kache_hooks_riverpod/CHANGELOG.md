## 1.2.0

- Added `useKacheProvider` for consuming existing Kache providers from
  `HookConsumerWidget`.
- Added `KacheProviderBinding` with snapshot, notifier, resource, lifecycle,
  and cache command access without duplicate resource ownership.
- Watches both provider state and notifier identity as widget build
  dependencies, following Riverpod's `read`/`watch` guidance.
- Preserved native Riverpod family, override, auto-dispose, and keep-alive
  behavior.
