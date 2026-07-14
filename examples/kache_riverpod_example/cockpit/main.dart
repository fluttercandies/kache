import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';

import 'package:kache_riverpod_example/main.dart' as prod;

/// Cockpit development entrypoint.
///
/// Wraps the production root (which owns its own ProviderScope + MaterialApp)
/// with [FlutterCockpitApp]. The remote control surface is resolved from the
/// dart-defines injected by `launch-app`; production code is untouched.
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
    child: const prod.KacheRiverpodExampleApp(),
  );
}
