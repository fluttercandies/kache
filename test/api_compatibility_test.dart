import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the documented public API surface remains source compatible', () async {
    final result = await Process.run('flutter', <String>[
      'analyze',
      'test/api_surface',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('adapter entrypoints re-export their intended upstream API', () {
    final expectedExports = <String, String>{
      'packages/kache_flutter/lib/kache_flutter.dart':
          "export 'package:kache/kache.dart';",
      'packages/kache_flutter_hooks/lib/kache_flutter_hooks.dart':
          "export 'package:kache_flutter/kache_flutter.dart';",
      'packages/kache_riverpod/lib/kache_riverpod.dart':
          "export 'package:kache/kache.dart';",
      'packages/kache_hooks_riverpod/lib/kache_hooks_riverpod.dart':
          "export 'package:kache_riverpod/kache_riverpod.dart';",
      'packages/kache_bloc/lib/kache_bloc.dart':
          "export 'package:kache/kache.dart';",
      'packages/kache_connectivity_plus/lib/kache_connectivity_plus.dart':
          "export 'package:kache/kache.dart';",
      'packages/kache_provider/lib/kache_provider.dart':
          "export 'package:kache_flutter/kache_flutter.dart';",
    };
    for (final entry in expectedExports.entries) {
      expect(File(entry.key).readAsStringSync(), contains(entry.value));
    }
  });
}
