import 'dart:io';

import 'package:test/test.dart';

const _documents = <String, String>{
  '.': 'test/readme_examples/kache_flutter.dart',
  'packages/kache': 'test/readme_examples/kache.dart',
  'packages/kache_flutter': 'test/readme_examples/kache_flutter.dart',
  'packages/kache_hive_ce': 'test/readme_examples/kache_hive_ce.dart',
  'packages/kache_riverpod': 'test/readme_examples/kache_riverpod.dart',
  'packages/kache_bloc': 'test/readme_examples/kache_bloc.dart',
  'packages/kache_connectivity_plus':
      'test/readme_examples/kache_connectivity_plus.dart',
  'packages/kache_provider': 'test/readme_examples/kache_provider.dart',
};

void main() {
  test('every published surface has synchronized bilingual documentation', () {
    for (final entry in _documents.entries) {
      final english = File('${entry.key}/README.md').readAsStringSync();
      final chinese = File('${entry.key}/README.zh-CN.md').readAsStringSync();
      final example = File(entry.value).readAsStringSync().trim();
      final fencedExample = '```dart\n$example\n```';

      expect(english, contains('[简体中文](README.zh-CN.md)'));
      expect(chinese, contains('[English](README.md)'));
      expect(english, contains(fencedExample));
      expect(chinese, contains(fencedExample));
      expect(english, contains('## Compatibility'));
      expect(chinese, contains('## 兼容性'));
    }
  });

  test('root documentation covers production decisions', () {
    final english = File('README.md').readAsStringSync();
    final chinese = File('README.zh-CN.md').readAsStringSync();
    for (final document in <String>[english, chinese]) {
      expect(document, contains('flutter pub add kache_flutter'));
      expect(document, contains('KacheQuery<Profile>.memory'));
      expect(document, contains('KacheScopeOwnership.owned'));
      expect(document, contains('snapshot.isRefreshing'));
      expect(document, contains('snapshot.hasFailure'));
      expect(document, isNot(contains('resource.stream.listen')));
    }
    expect(english, contains('## Dart-only'));
    expect(chinese, contains('## 纯 Dart 使用'));
    for (final heading in const <String>[
      '## Packages',
      '## Quick start',
      '## Policy guide',
      '## Custom persistence',
      '## Error handling',
      '## Lifecycle',
      '## Compatibility',
    ]) {
      expect(english, contains(heading));
    }
    for (final heading in const <String>[
      '## 包结构',
      '## 快速开始',
      '## 策略选择',
      '## 自定义持久层',
      '## 错误处理',
      '## 生命周期',
      '## 兼容性',
    ]) {
      expect(chinese, contains(heading));
    }
  });

  test('documented examples analyze as real workspace clients', () async {
    final result = await Process.run('flutter', <String>[
      'analyze',
      'test/readme_examples',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
