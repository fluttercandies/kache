import 'dart:io';

import 'src/workspace_checks.dart';

void main() {
  final errors = checkMelosScriptManifest(
    melosFile: File('melos.yaml'),
    manifestFile: File('tool/required_melos_scripts.yaml'),
    workspacePubspecFile: File('pubspec.yaml'),
  );
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln(error);
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Melos scripts match the required manifest.');
}
