import 'package:kache_flutter_hooks/kache_flutter_hooks.dart';

KacheController<int> verifyUseKache(
  KacheQuery<int> query, {
  KacheClient? client,
}) => useKache(query, client: client);

KacheSnapshot<int> verifyHookSnapshot(KacheController<int> controller) =>
    controller.snapshot;
