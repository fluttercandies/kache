import 'dart:io';

import 'package:yaml/yaml.dart';

const Map<String, Set<String>> allowedRuntimeDependencies = {
  'kache': <String>{},
  'kache_flutter': {'flutter', 'kache'},
  'kache_hive_ce': {'hive_ce', 'kache'},
  'kache_riverpod': {'riverpod', 'kache'},
  'kache_bloc': {'bloc', 'kache'},
  'kache_provider': {'provider', 'kache_flutter'},
  'kache_flutter_example': {'flutter', 'kache_flutter'},
  'kache_riverpod_example': {'flutter', 'kache_riverpod'},
  'kache_bloc_example': {'flutter', 'kache_bloc'},
  'kache_provider_example': {'flutter', 'kache_provider'},
  'kache_contract_tests': {
    'flutter',
    'kache',
    'kache_bloc',
    'kache_flutter',
    'kache_hive_ce',
    'kache_provider',
    'kache_riverpod',
  },
};

const Set<String> publishedPackages = {
  'kache',
  'kache_flutter',
  'kache_hive_ce',
  'kache_riverpod',
  'kache_bloc',
  'kache_provider',
};

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
        if (!packages.containsKey(dependency.key)) {
          continue;
        }
        dependencies.add(dependency.key);
        final specification = dependency.value;
        if (specification is Map<Object?, Object?> &&
            specification.containsKey('path')) {
          errors.add(
            '${entry.key} must use a version constraint for workspace '
            'dependency "${dependency.key}", not a path dependency.',
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
