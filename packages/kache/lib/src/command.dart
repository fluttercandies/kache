import 'dart:collection';

import 'failure.dart';

/// Result of a namespace or global cache clear operation.
final class KacheClearResult {
  /// Creates a result containing every failure observed by the clear.
  KacheClearResult({Iterable<KacheFailure> failures = const <KacheFailure>[]})
      : failures = UnmodifiableListView<KacheFailure>(
          List<KacheFailure>.of(failures),
        );

  /// Failures observed while clearing memory or persistence.
  final List<KacheFailure> failures;

  /// Whether every clear operation succeeded.
  bool get isSuccess => failures.isEmpty;

  /// Throws [KacheCommandException] when [failures] is not empty.
  void throwIfFailed() {
    if (!isSuccess) {
      throw KacheCommandException(failures);
    }
  }
}

/// Aggregates command failures without rendering keys or causes.
final class KacheCommandException implements Exception {
  /// Creates an exception containing an immutable copy of [failures].
  KacheCommandException(Iterable<KacheFailure> failures)
      : failures = UnmodifiableListView<KacheFailure>(
          List<KacheFailure>.of(failures),
        );

  /// Failures produced by the command.
  final List<KacheFailure> failures;

  @override
  String toString() =>
      'KacheCommandException: ${failures.length} operation(s) failed.';
}
