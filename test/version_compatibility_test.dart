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

const _publishedSdkConstraints = <String, String>{
  'packages/kache': '>=3.5.0 <4.0.0',
  'packages/kache_flutter': '>=3.5.0 <4.0.0',
  'packages/kache_hive_ce': '>=3.5.0 <4.0.0',
  'packages/kache_riverpod': '>=3.7.0 <4.0.0',
  'packages/kache_bloc': '>=3.5.0 <4.0.0',
  'packages/kache_connectivity_plus': '>=3.5.0 <4.0.0',
  'packages/kache_provider': '>=3.5.0 <4.0.0',
};

const _publishedFlutterConstraints = <String, String>{
  'packages/kache_flutter': '>=3.24.0',
  'packages/kache_connectivity_plus': '>=3.24.0',
  'packages/kache_provider': '>=3.24.0',
};

void main() {
  test('workspace package versions are aligned for the patch release', () {
    for (final path in _workspacePackagePaths) {
      final pubspec = _pubspec(path);
      expect(pubspec['version'], '1.0.1', reason: path);
    }
  });

  test(
    'published packages declare their independently verified SDK floors',
    () {
      for (final entry in _publishedSdkConstraints.entries) {
        expect(
          (_pubspec(entry.key)['environment'] as YamlMap)['sdk'],
          entry.value,
          reason: entry.key,
        );
      }
      for (final entry in _publishedFlutterConstraints.entries) {
        expect(
          (_pubspec(entry.key)['environment'] as YamlMap)['flutter'],
          entry.value,
          reason: entry.key,
        );
      }

      expect(
        (_pubspec('.')['environment'] as YamlMap)['sdk'],
        '>=3.11.0 <4.0.0',
      );
      for (final path
          in _workspacePackagePaths
              .skip(1)
              .toSet()
              .difference(_packagePaths.toSet())) {
        expect(
          (_pubspec(path)['environment'] as YamlMap)['sdk'],
          '^3.9.0',
          reason: path,
        );
      }
    },
  );

  test('Melos 8 manages the complete Dart Pub Workspace', () {
    expect(
      ((_pubspec('.')['workspace'] as YamlList).cast<String>()).toList(),
      _workspacePackagePaths.skip(1).toList(),
    );
    for (final path in _workspacePackagePaths.skip(1)) {
      expect(_pubspec(path)['resolution'], 'workspace', reason: path);
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
      '^7.2.0',
    );
    _expectDependency('packages/kache_provider', 'provider', '^6.1.5+1');

    _expectDependency('.', 'lints', '^6.1.0', dev: true);
    _expectDependency('.', 'melos', '8.2.2', dev: true);
    _expectDependency('.', 'xml', '^7.0.1', dev: true);

    for (final dependency in const <String>[
      'kache',
      'kache_bloc',
      'kache_connectivity_plus',
      'kache_flutter',
      'kache_hive_ce',
      'kache_provider',
      'kache_riverpod',
    ]) {
      _expectDependency('.', dependency, '^1.0.1', dev: true);
    }
  });

  test('every internal published dependency accepts the patch release', () {
    for (final entry in const <(String, String)>[
      ('packages/kache_flutter', 'kache'),
      ('packages/kache_hive_ce', 'kache'),
      ('packages/kache_riverpod', 'kache'),
      ('packages/kache_bloc', 'kache'),
      ('packages/kache_connectivity_plus', 'kache'),
      ('packages/kache_provider', 'kache_flutter'),
    ]) {
      _expectDependency(entry.$1, entry.$2, '^1.0.1');
    }
  });

  test('package READMEs publish their exact compatibility facts', () {
    for (final entry in _publishedSdkConstraints.entries) {
      for (final name in const <String>['README.md', 'README.zh-CN.md']) {
        final document = File('${entry.key}/$name').readAsStringSync();
        expect(document, contains('Dart ${entry.value}'), reason: entry.key);
        final flutter = _publishedFlutterConstraints[entry.key];
        if (flutter != null) {
          expect(document, contains('Flutter $flutter'), reason: entry.key);
        }
      }
    }

    for (final name in const <String>['README.md', 'README.zh-CN.md']) {
      final root = File(name).readAsStringSync();
      for (final entry in _publishedSdkConstraints.entries) {
        final package = entry.key.split('/').last;
        expect(root, contains('| `$package` | ${entry.value} |'));
      }
    }

    for (final name in const <String>[
      'packages/kache_connectivity_plus/README.md',
      'packages/kache_connectivity_plus/README.zh-CN.md',
    ]) {
      final document = File(name).readAsStringSync();
      for (final requirement in const <String>[
        'Java 17',
        'AGP >=8.12.1',
        'Gradle >=8.13',
        'Kotlin 2.2.0',
        'iOS >=12.0',
        'macOS >=10.14',
        'Xcode >=26.1.1',
      ]) {
        expect(document, contains(requirement), reason: name);
      }
    }
  });

  test('every published changelog starts with the patch release', () {
    for (final path in _packagePaths) {
      expect(
        File('$path/CHANGELOG.md').readAsStringSync(),
        startsWith('## 1.0.1\n'),
        reason: path,
      );
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

void _expectDependency(
  String path,
  String name,
  String expected, {
  bool dev = false,
}) {
  final key = dev ? 'dev_dependencies' : 'dependencies';
  final dependencies = _pubspec(path)[key] as YamlMap;
  expect(dependencies[name], expected);
}
