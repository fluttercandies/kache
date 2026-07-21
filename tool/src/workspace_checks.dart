import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

const Map<String, Set<String>> allowedRuntimeDependencies = {
  'kache': <String>{},
  'kache_flutter': {'flutter', 'kache'},
  'kache_flutter_hooks': {'flutter', 'flutter_hooks', 'kache_flutter'},
  'kache_hive_ce': {'hive_ce', 'kache'},
  'kache_riverpod': {'riverpod', 'kache'},
  'kache_hooks_riverpod': {
    'flutter',
    'flutter_hooks',
    'hooks_riverpod',
    'kache_riverpod',
  },
  'kache_bloc': {'bloc', 'kache'},
  'kache_connectivity_plus': {'connectivity_plus', 'flutter', 'kache'},
  'kache_provider': {'flutter', 'provider', 'kache_flutter'},
  'kache_flutter_example': {
    'cupertino_icons',
    'flutter',
    'flutter_hooks',
    'kache_example_support',
    'kache_flutter_hooks',
  },
  'kache_riverpod_example': {
    'cupertino_icons',
    'flutter',
    'hooks_riverpod',
    'kache_example_support',
    'kache_hooks_riverpod',
  },
  'kache_bloc_example': {
    'cupertino_icons',
    'flutter',
    'flutter_bloc',
    'kache_bloc',
    'kache_example_support',
  },
  'kache_provider_example': {
    'cupertino_icons',
    'flutter',
    'kache_example_support',
    'kache_provider',
  },
  'kache_example_support': {
    'flutter',
    'hive_ce_flutter',
    'http',
    'kache',
    'kache_flutter',
    'kache_hive_ce',
    'kache_connectivity_plus',
  },
  'kache_contract_tests': {
    'flutter',
    'kache',
    'kache_bloc',
    'kache_flutter',
    'kache_flutter_hooks',
    'kache_hive_ce',
    'kache_hooks_riverpod',
    'kache_connectivity_plus',
    'kache_provider',
    'kache_riverpod',
    'riverpod',
    'test',
  },
};

const Set<String> publishedPackages = {
  'kache',
  'kache_flutter',
  'kache_flutter_hooks',
  'kache_hive_ce',
  'kache_hooks_riverpod',
  'kache_connectivity_plus',
  'kache_riverpod',
  'kache_bloc',
  'kache_provider',
};

const Set<String> _sourceFileNames = {'CMakeLists.txt'};
const Set<String> _sourceExtensions = {
  '.c',
  '.cc',
  '.cmake',
  '.cpp',
  '.css',
  '.dart',
  '.entitlements',
  '.gradle',
  '.h',
  '.html',
  '.java',
  '.js',
  '.json',
  '.kt',
  '.kts',
  '.m',
  '.mm',
  '.plist',
  '.properties',
  '.storyboard',
  '.swift',
  '.xib',
  '.xml',
  '.yaml',
  '.yml',
};
const Set<String> _excludedSourceSegments = {
  '.dart_tool',
  '.idea',
  '.plugin_symlinks',
  '.symlinks',
  'Pods',
  'build',
  'doc',
  'ephemeral',
  'fixtures',
  'test',
};

List<String> checkSourceMarkers(
  Directory root, {
  Iterable<String> sourceRoots = const <String>[
    'packages',
    'examples',
    'tool',
    'benchmark',
  ],
}) {
  final errors = <String>[];
  final markerNames = <String>[
    'TO'
        'DO',
    'FIX'
        'ME',
  ];
  final marker = RegExp('\\b(${markerNames.join('|')})\\b');
  for (final sourceRoot in sourceRoots) {
    final directory = Directory('${root.path}/$sourceRoot');
    if (!directory.existsSync()) {
      continue;
    }
    final files =
        directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => _isProductionSource(root, file))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final file in files) {
      final relativePath = _relativePath(root, file);
      final lines = const LineSplitter().convert(file.readAsStringSync());
      for (var index = 0; index < lines.length; index++) {
        final match = marker.firstMatch(lines[index]);
        if (match != null) {
          errors.add('$relativePath:${index + 1} contains ${match.group(1)}.');
        }
      }
    }
  }
  return errors;
}

bool _isProductionSource(Directory root, File file) {
  final relativePath = _relativePath(root, file);
  final segments = relativePath.split('/');
  if (segments.any(_excludedSourceSegments.contains)) {
    return false;
  }
  final name = segments.last;
  if (_sourceFileNames.contains(name)) {
    return true;
  }
  final dot = name.lastIndexOf('.');
  return dot >= 0 && _sourceExtensions.contains(name.substring(dot));
}

String _relativePath(Directory root, File file) {
  final rootPath = root.absolute.path.replaceAll('\\', '/');
  final filePath = file.absolute.path.replaceAll('\\', '/');
  return filePath.substring(rootPath.length + 1);
}

List<String> checkDependencyBoundaries(
  Directory root, {
  Set<String>? requiredPackages,
}) {
  final errors = <String>[];
  final rootPubspec = _readYamlMap(File('${root.path}/pubspec.yaml'), errors);
  if (rootPubspec == null) {
    return errors;
  }

  final workspacePaths = _readStringList(
    rootPubspec['workspace'],
    source: '${root.path}/pubspec.yaml: workspace',
    errors: errors,
  );
  final packages = <String, _PackageManifest>{};

  for (final workspacePath in workspacePaths) {
    final pubspecFile = File('${root.path}/$workspacePath/pubspec.yaml');
    final pubspec = _readYamlMap(pubspecFile, errors);
    if (pubspec == null) {
      continue;
    }
    final name = pubspec['name'];
    if (name is! String || name.isEmpty) {
      errors.add('${pubspecFile.path}: name must be a non-empty string.');
      continue;
    }
    if (packages.containsKey(name)) {
      errors.add('Workspace package name "$name" is declared more than once.');
      continue;
    }
    packages[name] = _PackageManifest(pubspec);
  }

  final expectedPackages =
      requiredPackages ?? allowedRuntimeDependencies.keys.toSet();
  for (final name in expectedPackages) {
    if (!packages.containsKey(name)) {
      errors.add('Required workspace package "$name" is missing.');
    }
  }

  for (final entry in packages.entries) {
    final packageName = entry.key;
    final manifest = entry.value;
    final allowed = allowedRuntimeDependencies[packageName];
    if (allowed == null) {
      errors.add('Workspace package "$packageName" has no dependency rule.');
      continue;
    }

    final dependencies = _readDependencyMap(
      manifest.yaml['dependencies'],
      packageName: packageName,
      section: 'dependencies',
      errors: errors,
    );
    for (final dependency in dependencies.keys) {
      if (!allowed.contains(dependency)) {
        errors.add(
          '$packageName has forbidden dependency "$dependency" '
          'in dependencies.',
        );
      }
    }
    for (final dependency in allowed) {
      if (!dependencies.containsKey(dependency)) {
        errors.add(
          '$packageName is missing required dependency "$dependency" '
          'in dependencies.',
        );
      }
    }

    final publishTo = manifest.yaml['publish_to'];
    if (publishedPackages.contains(packageName) && publishTo == 'none') {
      errors.add('$packageName must remain publishable.');
    }
    if (!publishedPackages.contains(packageName) && publishTo != 'none') {
      errors.add('$packageName must set publish_to: none.');
    }
  }

  _checkWorkspaceGraph(packages, errors);
  return errors;
}

List<String> checkMelosScriptManifest({
  required File melosFile,
  required File manifestFile,
  File? workspacePubspecFile,
}) {
  final errors = <String>[];
  final melos = _readYamlMap(melosFile, errors);
  final manifest = _readYamlMap(manifestFile, errors);
  if (melos == null || manifest == null) {
    return errors;
  }

  final scripts = _readStringKeyMap(
    melos['scripts'],
    source: '${melosFile.path}: scripts',
    errors: errors,
  );
  final scriptRuns = _readScriptRuns(
    scripts,
    source: melosFile.uri.pathSegments.last,
    errors: errors,
  );
  final requiredScripts = _readStringList(
    manifest['scripts'],
    source: '${manifestFile.path}: scripts',
    errors: errors,
  );
  final requiredSet = requiredScripts.toSet();

  if (requiredSet.length != requiredScripts.length) {
    errors.add('${manifestFile.path}: scripts contains duplicate entries.');
  }
  for (final script in requiredSet) {
    if (!scripts.containsKey(script)) {
      errors.add('Required Melos script "$script" is missing.');
    }
  }
  for (final script in scripts.keys) {
    if (!requiredSet.contains(script)) {
      errors.add('Melos script "$script" is not declared in the manifest.');
    }
  }

  if (workspacePubspecFile != null) {
    final pubspec = _readYamlMap(workspacePubspecFile, errors);
    if (pubspec != null) {
      final melosConfig = _readStringKeyMap(
        pubspec['melos'],
        source: '${workspacePubspecFile.path}: melos',
        errors: errors,
      );
      final workspaceScripts = _readStringKeyMap(
        melosConfig['scripts'],
        source: '${workspacePubspecFile.path}: melos.scripts',
        errors: errors,
      );
      final workspaceScriptRuns = _readScriptRuns(
        workspaceScripts,
        source: workspacePubspecFile.uri.pathSegments.last,
        errors: errors,
      );
      for (final script in requiredSet) {
        if (!workspaceScripts.containsKey(script)) {
          errors.add(
            'Required Melos script "$script" is missing from '
            '${workspacePubspecFile.path}.',
          );
        }
      }
      for (final script in workspaceScripts.keys) {
        if (!requiredSet.contains(script)) {
          errors.add(
            'Workspace Melos script "$script" is not declared in the '
            'manifest.',
          );
        }
      }
      for (final script in requiredSet) {
        final mirrorRun = scriptRuns[script];
        final workspaceRun = workspaceScriptRuns[script];
        if (mirrorRun != null &&
            workspaceRun != null &&
            mirrorRun != workspaceRun) {
          errors.add(
            'Melos script "$script" has different run commands in '
            '${melosFile.uri.pathSegments.last} and '
            '${workspacePubspecFile.uri.pathSegments.last}.',
          );
        }
      }

      final mirroredPackages = _readStringList(
        melos['packages'],
        source: '${melosFile.path}: packages',
        errors: errors,
      ).toSet();
      final workspacePackages = _readStringList(
        pubspec['workspace'],
        source: '${workspacePubspecFile.path}: workspace',
        errors: errors,
      ).toSet();
      for (final package in workspacePackages.difference(mirroredPackages)) {
        errors.add(
          'Melos package mirror is missing workspace member "$package".',
        );
      }
      for (final package in mirroredPackages.difference(workspacePackages)) {
        errors.add(
          'Melos package mirror declares non-workspace member "$package".',
        );
      }
    }
  }
  return errors;
}

void _checkWorkspaceGraph(
  Map<String, _PackageManifest> packages,
  List<String> errors,
) {
  final graph = <String, Set<String>>{};
  for (final entry in packages.entries) {
    final dependencies = <String>{};
    for (final section in const [
      'dependencies',
      'dev_dependencies',
      'dependency_overrides',
    ]) {
      final dependencyMap = _readDependencyMap(
        entry.value.yaml[section],
        packageName: entry.key,
        section: section,
        errors: errors,
      );
      for (final dependency in dependencyMap.entries) {
        final targetPackage = packages[dependency.key];
        if (targetPackage == null) {
          continue;
        }
        dependencies.add(dependency.key);
        final specification = dependency.value;
        if (specification is! String || specification.trim().isEmpty) {
          errors.add(
            '${entry.key} workspace dependency "${dependency.key}" must use '
            'a non-empty string version constraint.',
          );
          continue;
        }

        final targetVersionText = targetPackage.yaml['version'];
        if (targetVersionText is! String || targetVersionText.isEmpty) {
          errors.add(
            'Workspace package "${dependency.key}" must declare a semantic '
            'version before other workspace packages can depend on it.',
          );
          continue;
        }

        try {
          final constraint = VersionConstraint.parse(specification);
          final targetVersion = Version.parse(targetVersionText);
          if (!constraint.allows(targetVersion)) {
            errors.add(
              '${entry.key} dependency "${dependency.key}" constraint '
              '"$specification" does not allow workspace version '
              '$targetVersionText.',
            );
          }
        } on FormatException catch (error) {
          errors.add(
            '${entry.key} dependency "${dependency.key}" has invalid '
            'version metadata: ${error.message}.',
          );
        }
      }
    }
    graph[entry.key] = dependencies;
  }

  final visiting = <String>{};
  final visited = <String>{};
  final path = <String>[];

  bool visit(String packageName) {
    if (visiting.contains(packageName)) {
      final cycleStart = path.indexOf(packageName);
      final cycle = [...path.sublist(cycleStart), packageName];
      errors.add('Workspace dependency cycle: ${cycle.join(' -> ')}.');
      return true;
    }
    if (visited.contains(packageName)) {
      return false;
    }
    visiting.add(packageName);
    path.add(packageName);
    for (final dependency in graph[packageName] ?? const <String>{}) {
      if (visit(dependency)) {
        return true;
      }
    }
    path.removeLast();
    visiting.remove(packageName);
    visited.add(packageName);
    return false;
  }

  for (final packageName in graph.keys) {
    if (visit(packageName)) {
      break;
    }
  }
}

Map<Object?, Object?>? _readYamlMap(File file, List<String> errors) {
  if (!file.existsSync()) {
    errors.add('${file.path}: file does not exist.');
    return null;
  }
  try {
    final Object? document = loadYaml(file.readAsStringSync()) as Object?;
    if (document is Map<Object?, Object?>) {
      return document;
    }
    errors.add('${file.path}: root YAML value must be a map.');
  } on YamlException catch (error) {
    errors.add('${file.path}: invalid YAML: ${error.message}.');
  }
  return null;
}

List<String> _readStringList(
  Object? value, {
  required String source,
  required List<String> errors,
}) {
  if (value is! List<Object?>) {
    errors.add('$source must be a list.');
    return const [];
  }
  final result = <String>[];
  for (final item in value) {
    if (item is String && item.isNotEmpty) {
      result.add(item);
    } else {
      errors.add('$source entries must be non-empty strings.');
    }
  }
  return result;
}

Map<String, Object?> _readStringKeyMap(
  Object? value, {
  required String source,
  required List<String> errors,
}) {
  if (value is! Map<Object?, Object?>) {
    errors.add('$source must be a map.');
    return const {};
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String && key.isNotEmpty) {
      result[key] = entry.value;
    } else {
      errors.add('$source keys must be non-empty strings.');
    }
  }
  return result;
}

Map<String, String> _readScriptRuns(
  Map<String, Object?> scripts, {
  required String source,
  required List<String> errors,
}) {
  final result = <String, String>{};
  for (final entry in scripts.entries) {
    final value = entry.value;
    final Object? run = value is Map<Object?, Object?> ? value['run'] : value;
    if (run is String && run.trim().isNotEmpty) {
      result[entry.key] = run.trim();
    } else {
      errors.add(
        '$source script "${entry.key}" must define a non-empty run command.',
      );
    }
  }
  return result;
}

Map<String, Object?> _readDependencyMap(
  Object? value, {
  required String packageName,
  required String section,
  required List<String> errors,
}) {
  if (value == null) {
    return const {};
  }
  return _readStringKeyMap(
    value,
    source: '$packageName: $section',
    errors: errors,
  );
}

final class _PackageManifest {
  const _PackageManifest(this.yaml);

  final Map<Object?, Object?> yaml;
}
