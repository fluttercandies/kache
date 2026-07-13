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
  });
}
