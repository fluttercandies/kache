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
  'packages/kache_connectivity_plus',
  'packages/kache_provider',
];

const _workspacePackagePaths = <String>[
  '.',
  ..._packagePaths,
  'examples/kache_flutter_example',
  'examples/kache_riverpod_example',
  'examples/kache_bloc_example',
  'examples/kache_provider_example',
  'tool/contract_tests',
  'tool/example_support',
];

void main() {
  test('workspace package versions and SDK floors are aligned', () {
    for (final path in _workspacePackagePaths) {
      final pubspec = _pubspec(path);
      expect(pubspec['version'], '1.0.0', reason: path);
      expect(
        (pubspec['environment'] as YamlMap)['sdk'],
        '^3.9.0',
        reason: path,
      );
    }
  });

  test('published package repository metadata points to its source', () {
    const repository = 'https://github.com/fluttercandies/kache';

    for (final path in _packagePaths) {
      final pubspec = _pubspec(path);
      expect(pubspec['homepage'], repository, reason: path);
      expect(
        pubspec['repository'],
        '$repository/tree/main/$path',
        reason: path,
      );
      expect(pubspec['issue_tracker'], '$repository/issues', reason: path);
    }
  });

  test('framework and persistence constraints match the supported matrix', () {
    _expectDependency('packages/kache_hive_ce', 'hive_ce', '^2.19.3');
    _expectDependency('packages/kache_riverpod', 'riverpod', '^3.3.2');
    _expectDependency('packages/kache_bloc', 'bloc', '^9.2.1');
    _expectDependency(
      'packages/kache_connectivity_plus',
      'connectivity_plus',
      '^6.1.5',
    );
    _expectDependency('packages/kache_provider', 'provider', '^6.1.5+1');
    for (final path in const <String>[
      'packages/kache_flutter',
      'packages/kache_connectivity_plus',
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

  test('test dependency range follows compatible Flutter SDK pins', () {
    for (final path in const <String>[
      '.',
      'packages/kache',
      'packages/kache_hive_ce',
      'packages/kache_riverpod',
      'packages/kache_bloc',
      'tool/contract_tests',
    ]) {
      final pubspec = _pubspec(path);
      final dependencies = pubspec['dependencies'] as YamlMap?;
      final devDependencies = pubspec['dev_dependencies'] as YamlMap?;
      final constraint = VersionConstraint.parse(
        (devDependencies?['test'] ?? dependencies?['test']) as String,
      );

      expect(constraint.allows(Version(1, 26, 2)), isTrue, reason: path);
      expect(constraint.allows(Version(1, 30, 0)), isTrue, reason: path);
      expect(constraint.allows(Version(1, 31, 0)), isTrue, reason: path);
      expect(constraint.allows(Version(1, 32, 0)), isFalse, reason: path);
    }
  });
}

YamlMap _pubspec(String path) =>
    loadYaml(File('$path/pubspec.yaml').readAsStringSync()) as YamlMap;

void _expectDependency(String path, String name, String expected) {
  final dependencies = _pubspec(path)['dependencies'] as YamlMap;
  expect(dependencies[name], expected);
}
