import 'dart:async';

import 'package:kache/kache.dart';

StreamSubscription<KacheEvent> watchFailures(
  KacheClient client,
  void Function(KacheEvent event) report,
) => client.events
    .where(
      (event) =>
          event.phase == KacheEventPhase.failed ||
          event.phase == KacheEventPhase.cancelled,
    )
    .listen(report);
