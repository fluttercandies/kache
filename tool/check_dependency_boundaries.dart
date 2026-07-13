import 'dart:io';

import 'src/workspace_checks.dart';

void main() {
  final errors = checkDependencyBoundaries(Directory.current);
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln(error);
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Dependency boundaries are valid.');
}
