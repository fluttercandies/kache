import 'package:flutter/widgets.dart';
import 'package:kache_flutter/kache_flutter.dart';

void verifyFlutterTypes({
  required KacheScope scope,
  required KacheScopeOwnership ownership,
  required KacheController<int> controller,
  required KacheBuilder<int> builder,
  required KacheListener<int> listener,
}) {}

KacheScopeErrorHandler verifyScopeErrorHandler(
  KacheScopeErrorHandler handler,
) => handler;

KacheWidgetBuilder<int> verifyWidgetBuilder(KacheWidgetBuilder<int> builder) =>
    builder;

KacheSnapshotListener<int> verifySnapshotListener(
  KacheSnapshotListener<int> listener,
) => listener;

KacheListenWhen<int> verifyListenWhen(KacheListenWhen<int> listenWhen) =>
    listenWhen;

KacheClient? verifyScopeLookup(BuildContext context) =>
    KacheScope.maybeOf(context);

Future<KacheSnapshot<int>> verifyControllerRefresh(
  KacheController<int> controller,
) => controller.refresh();
