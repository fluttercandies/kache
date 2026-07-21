import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:kache_flutter/kache_flutter.dart';

/// Binds a Kache query to the current [HookWidget] lifecycle.
///
/// The returned controller is listened to by this hook, so its current value
/// represents the snapshot that triggered the current build. When [client] is
/// omitted, the nearest [KacheScope] supplies it.
KacheController<T> useKache<T>(KacheQuery<T> query, {KacheClient? client}) {
  final context = useContext();
  final resolvedClient = client ?? KacheScope.of(context);
  final controller = useMemoized(
    () => KacheController<T>(client: resolvedClient, query: query),
    <Object?>[resolvedClient, query.key],
  );

  useEffect(() {
    if (!identical(controller.query, query)) {
      controller.updateQuery(query);
    }
    return null;
  }, <Object?>[controller, query]);

  useEffect(() => controller.dispose, <Object?>[controller]);
  useValueListenable(controller);
  return controller;
}

/// Snapshot-oriented naming for controllers returned by [useKache].
extension KacheHookControllerX<T> on KacheController<T> {
  /// The snapshot that triggered the current hook build.
  KacheSnapshot<T> get snapshot => value;
}
