import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Riverpod example tracks build dependencies explicitly', () {
    final source = File(
      'examples/kache_riverpod_example/lib/main.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('final notifier = ref.read(')));
    expect(
      source,
      isNot(contains('.read(_policyFamilyProvider(name).notifier)')),
    );
    expect(
      RegExp(r'dependencies:\s*\[_runtimeProvider\]').allMatches(source),
      hasLength(4),
    );
    expect(
      source,
      contains('dependencies: const []'),
      reason: 'The overridden runtime provider must opt into scoping.',
    );
  });

  test('Hooks quick start declares its scoped provider dependency', () {
    for (final path in <String>[
      'packages/kache_hooks_riverpod/README.md',
      'packages/kache_hooks_riverpod/README.zh-CN.md',
      'test/readme_examples/kache_hooks_riverpod.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('dependencies: const []'), reason: path);
      expect(source, contains('dependencies: [clientProvider],'), reason: path);
    }
  });
}
