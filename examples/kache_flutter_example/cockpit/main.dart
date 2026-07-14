import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';

import 'package:kache_flutter_example/main.dart' as prod;

/// Cockpit development entrypoint.
///
/// `launch-app` auto-detects `cockpit/main.dart` before `lib/main.dart`. This
/// file wraps the production root with [FlutterCockpitApp] so the remote
/// control surface (resolved from the injected dart-defines) attaches without
/// touching production code. The production app owns its own navigator, so we
/// keep route synchronization in the cockpit layer rather than registering
/// navigator observers here.
Future<void> main() async {
  runApp(buildCockpitDevelopmentApp());
}

Widget buildCockpitDevelopmentApp() {
  return FlutterCockpitApp(
    config: FlutterCockpitConfig.production(
      remoteSession: CockpitRemoteSessionConfiguration.resolveFromEnvironment(
        fallback: const CockpitRemoteSessionConfiguration(
          enabled: false,
          host: '127.0.0.1',
          port: 47331,
        ),
      ),
    ),
    child: const prod.KacheFlutterExampleApp(),
  );
}
