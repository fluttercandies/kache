import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _packagePaths = <String>[
  'packages/kache',
  'packages/kache_flutter',
  'packages/kache_hive_ce',
  'packages/kache_riverpod',
  'packages/kache_bloc',
  'packages/kache_provider',
];

void main() {
  test('published package versions and SDK floors are aligned', () {
    for (final path in _packagePaths) {
      final pubspec = _pubspec(path);
      expect(pubspec['version'], '0.1.0');
      expect((pubspec['environment'] as YamlMap)['sdk'], '^3.9.0');
    }
  });

  test('framework and persistence constraints match the supported matrix', () {
    _expectDependency('packages/kache_hive_ce', 'hive_ce', '^2.19.3');
    _expectDependency('packages/kache_riverpod', 'riverpod', '^3.3.2');
    _expectDependency('packages/kache_bloc', 'bloc', '^9.2.1');
    _expectDependency('packages/kache_provider', 'provider', '^6.1.5+1');
    for (final path in const <String>[
      'packages/kache_flutter',
      'packages/kache_provider',
    ]) {
      expect(
        VersionConstraint.parse(
          ((_pubspec(path)['environment'] as YamlMap)['flutter'] as String),
        ).allows(Version(3, 35, 0)),
        isTrue,
      );
    }
  });

  test('all package READMEs publish the same compatibility facts', () {
    for (final path in _packagePaths) {
      final english = File('$path/README.md').readAsStringSync();
      final chinese = File('$path/README.zh-CN.md').readAsStringSync();
      expect(english, contains('Dart >=3.9.0 <4.0.0'));
      expect(chinese, contains('Dart >=3.9.0 <4.0.0'));
    }
  });
}

YamlMap _pubspec(String path) =>
    loadYaml(File('$path/pubspec.yaml').readAsStringSync()) as YamlMap;

void _expectDependency(String path, String name, String expected) {
  final dependencies = _pubspec(path)['dependencies'] as YamlMap;
  expect(dependencies[name], expected);
}
