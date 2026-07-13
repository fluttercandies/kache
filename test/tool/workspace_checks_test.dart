import 'dart:io';

import 'package:test/test.dart';

import '../../tool/src/workspace_checks.dart';

void main() {
  group('dependency boundaries', () {
    test('reports a forbidden runtime dependency', () {
      final errors = checkDependencyBoundaries(
        Directory('test/tool/fixtures/invalid_dependency'),
        requiredPackages: const {'kache'},
      );

      expect(
        errors,
        contains('kache has forbidden dependency "flutter" in dependencies.'),
      );
    });

    test('reports a workspace dependency cycle', () {
      final errors = checkDependencyBoundaries(
        Directory('test/tool/fixtures/dependency_cycle'),
        requiredPackages: const {'kache', 'kache_flutter'},
      );

      expect(
        errors,
        contains(
          'Workspace dependency cycle: kache -> kache_flutter -> kache.',
        ),
      );
    });

    test('accepts the repository workspace', () {
      expect(checkDependencyBoundaries(Directory.current), isEmpty);
    });

    test('rejects non-string sources for workspace dependencies', () {
      final errors = checkDependencyBoundaries(
        Directory('test/tool/fixtures/invalid_internal_sources'),
        requiredPackages: const {
          'kache',
          'kache_bloc',
          'kache_flutter',
          'kache_hive_ce',
          'kache_riverpod',
        },
      );

      for (final package in const [
        'kache_flutter',
        'kache_hive_ce',
        'kache_riverpod',
      ]) {
        expect(
          errors,
          contains(
            '$package workspace dependency "kache" must use a non-empty '
            'string version constraint.',
          ),
        );
      }
      expect(
        errors,
        contains(
          'kache_bloc workspace dependency "kache" must use a non-empty '
          'string version constraint.',
        ),
      );
    });

    test('rejects a constraint that excludes the workspace version', () {
      final errors = checkDependencyBoundaries(
        Directory('test/tool/fixtures/incompatible_workspace_version'),
        requiredPackages: const {'kache', 'kache_flutter'},
      );

      expect(
        errors,
        contains(
          'kache_flutter dependency "kache" constraint "^0.1.0" does not '
          'allow workspace version 0.2.0.',
        ),
      );
    });
  });

  group('Melos script manifest', () {
    test(
      'reports a script required by the manifest but missing from Melos',
      () {
        final fixture = Directory('test/tool/fixtures/missing_script');
        final errors = checkMelosScriptManifest(
          melosFile: File('${fixture.path}/melos.yaml'),
          manifestFile: File('${fixture.path}/required_melos_scripts.yaml'),
        );

        expect(
          errors,
          contains('Required Melos script "dependency-boundaries" is missing.'),
        );
      },
    );

    test('accepts the repository script manifest', () {
      expect(
        checkMelosScriptManifest(
          melosFile: File('melos.yaml'),
          manifestFile: File('tool/required_melos_scripts.yaml'),
          workspacePubspecFile: File('pubspec.yaml'),
        ),
        isEmpty,
      );
    });

    test('reports a run command that differs between Melos configs', () {
      final fixture = Directory('test/tool/fixtures/script_command_mismatch');
      final errors = checkMelosScriptManifest(
        melosFile: File('${fixture.path}/melos.yaml'),
        manifestFile: File('${fixture.path}/required_melos_scripts.yaml'),
        workspacePubspecFile: File('${fixture.path}/pubspec.yaml'),
      );

      expect(
        errors,
        contains(
          'Melos script "test" has different run commands in melos.yaml '
          'and pubspec.yaml.',
        ),
      );
    });

    test('reports missing and unexpected mirrored workspace packages', () {
      final fixture = Directory(
        'test/tool/fixtures/workspace_package_mismatch',
      );
      final errors = checkMelosScriptManifest(
        melosFile: File('${fixture.path}/melos.yaml'),
        manifestFile: File('${fixture.path}/required_melos_scripts.yaml'),
        workspacePubspecFile: File('${fixture.path}/pubspec.yaml'),
      );

      expect(
        errors,
        contains(
          'Melos package mirror is missing workspace member '
          '"packages/kache_flutter".',
        ),
      );
      expect(
        errors,
        contains(
          'Melos package mirror declares non-workspace member '
          '"packages/extra".',
        ),
      );
    });
  });
}
