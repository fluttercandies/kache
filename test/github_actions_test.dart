import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _workflowPath = '.github/workflows/ci.yaml';
const _checkoutAction =
    'actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5';
const _flutterAction =
    'subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2';

void main() {
  test('CI targets main with bounded least-privilege execution', () {
    final workflow = _workflow();
    final triggers = workflow['on'] as YamlMap;

    expect(_branches(triggers, 'push'), <String>['main']);
    expect(_branches(triggers, 'pull_request'), <String>['main']);
    expect(triggers, contains('workflow_dispatch'));
    expect(workflow['permissions'], <String, Object?>{'contents': 'read'});

    final concurrency = workflow['concurrency'] as YamlMap;
    expect(concurrency['group'], r'${{ github.workflow }}-${{ github.ref }}');
    expect(concurrency['cancel-in-progress'], isTrue);

    final job = _qualityJob(workflow);
    expect(job['runs-on'], 'ubuntu-latest');
    expect(job['timeout-minutes'], 45);
  });

  test('CI pins actions and the supported Flutter and Melos toolchain', () {
    final workflow = _workflow();
    final steps = _allSteps(workflow);
    final actionSteps = steps
        .where((step) => step.containsKey('uses'))
        .toList();

    expect(
      actionSteps.where((step) => step['uses'] == _checkoutAction),
      hasLength(2),
    );
    expect(
      actionSteps.where((step) => step['uses'] == _flutterAction),
      hasLength(2),
    );
    for (final step in actionSteps) {
      expect(
        step['uses'],
        matches(RegExp(r'^[^@]+@[0-9a-f]{40}$')),
        reason: 'Every external action must be pinned to a commit SHA.',
      );
    }

    final stableFlutter = _steps(
      workflow,
    ).singleWhere((step) => step['uses'] == _flutterAction);
    expect(stableFlutter['with'], <String, Object?>{
      'channel': 'stable',
      'cache': true,
    });
    final minimumFlutter = _jobSteps(
      workflow,
      'minimum',
    ).singleWhere((step) => step['uses'] == _flutterAction);
    expect(minimumFlutter['with'], <String, Object?>{
      'flutter-version': '3.35.0',
      'cache': true,
    });
    expect(_commands(steps), contains('dart pub global activate melos 7.8.0'));
  });

  test('CI verifies the declared minimum Flutter version', () {
    final workflow = _workflow();
    final job = _job(workflow, 'minimum');
    expect(job['runs-on'], 'ubuntu-latest');
    expect(job['timeout-minutes'], 30);

    final commands = _commands(_jobSteps(workflow, 'minimum')).join('\n');
    for (final command in const <String>[
      'melos bootstrap',
      'dart analyze',
      'melos run test',
      'melos run test:integration',
      'melos run test:connectivity',
      'melos run analyze:examples',
      'melos run build:web',
      'melos run api-check',
    ]) {
      expect(
        commands,
        contains(command),
        reason: 'Missing Flutter 3.35 gate: $command',
      );
    }
  });

  test('CI runs every release gate and cross-platform key contract', () {
    final commands = _commands(_steps(_workflow())).join('\n');

    for (final command in const <String>[
      'melos bootstrap',
      'dart fix --apply',
      'dart format .',
      'git diff --exit-code',
      'dart analyze',
      'melos exec --scope=kache -- dart test test/key_test.dart',
      'melos exec --scope=kache -- dart test -p chrome test/key_test.dart',
      'melos run test',
      'melos run test:integration',
      'melos run test:persistence-contracts',
      'melos run test:hive',
      'melos run test:connectivity',
      'melos run test:riverpod',
      'melos run test:bloc',
      'melos run test:core-failure-injection',
      'melos run test:core-lifecycle',
      'melos run test:adapter-contracts',
      'melos run test:examples',
      'melos run test:failure-injection',
      'melos run test:lifecycle',
      'melos run analyze:examples',
      'melos run build:web',
      'melos run docs',
      'melos run test:readme',
      'melos run api-check',
      'melos run compatibility-check',
      'melos run benchmark',
      'melos run dependency-boundaries',
      'melos run verify:script-manifest',
      'melos run source-marker-check',
      'melos run publish-dry-run',
    ]) {
      expect(commands, contains(command), reason: 'Missing CI gate: $command');
    }
  });
}

YamlMap _workflow() {
  final file = File(_workflowPath);
  expect(
    file.existsSync(),
    isTrue,
    reason: 'The repository must define $_workflowPath.',
  );
  return loadYaml(file.readAsStringSync(), sourceUrl: file.uri) as YamlMap;
}

List<String> _branches(YamlMap triggers, String name) {
  final trigger = triggers[name] as YamlMap;
  return ((trigger['branches'] as YamlList).cast<String>()).toList();
}

YamlMap _qualityJob(YamlMap workflow) => _job(workflow, 'quality');

YamlMap _job(YamlMap workflow, String name) =>
    (workflow['jobs'] as YamlMap)[name] as YamlMap;

List<YamlMap> _steps(YamlMap workflow) =>
    ((_qualityJob(workflow)['steps'] as YamlList).cast<YamlMap>()).toList();

List<YamlMap> _jobSteps(YamlMap workflow, String name) =>
    (((_job(workflow, name))['steps'] as YamlList).cast<YamlMap>()).toList();

List<YamlMap> _allSteps(YamlMap workflow) => (workflow['jobs'] as YamlMap)
    .values
    .cast<YamlMap>()
    .expand((job) => (job['steps'] as YamlList).cast<YamlMap>())
    .toList();

List<String> _commands(List<YamlMap> steps) => steps
    .where((step) => step.containsKey('run'))
    .map((step) => step['run'] as String)
    .toList();
