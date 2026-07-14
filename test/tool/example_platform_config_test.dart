import 'dart:io';

import 'package:test/test.dart';

void main() {
  const examples = <String>[
    'kache_flutter_example',
    'kache_riverpod_example',
    'kache_bloc_example',
    'kache_provider_example',
  ];

  for (final example in examples) {
    test('$example enables release network access', () {
      final root = 'examples/$example';
      final pubspec = File('$root/pubspec.yaml').readAsStringSync();
      expect(
        pubspec,
        contains('uses-material-design: true'),
        reason: '$example must bundle the Material icon font.',
      );
      final androidManifest = File(
        '$root/android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(
        androidManifest,
        contains('android.permission.INTERNET'),
        reason:
            '$example must access the GitHub API in Android release builds.',
      );

      for (final fileName in const <String>[
        'DebugProfile.entitlements',
        'Release.entitlements',
      ]) {
        final entitlements = File(
          '$root/macos/Runner/$fileName',
        ).readAsStringSync();
        expect(
          entitlements,
          contains('com.apple.security.network.client'),
          reason: '$example must access the GitHub API on macOS.',
        );
      }
    });
  }
}
