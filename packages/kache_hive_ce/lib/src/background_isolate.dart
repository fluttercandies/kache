import 'dart:isolate';

import 'background_failure.dart';

export 'background_failure.dart';

/// Whether this platform can run codec work on a background isolate.
const bool supportsBackgroundWork = true;

/// Runs [work] on a short-lived isolate and returns its result.
///
/// Errors thrown by [work] are rethrown unchanged with their remote stack
/// trace. Any failure of the isolate mechanism itself, including an unsendable
/// closure, result, or error, is reported as [BackgroundWorkUnavailable] so the
/// caller can repeat the work inline instead of failing the operation.
Future<R> runInBackground<R>(R Function() work) async {
  final _Outcome<R> outcome;
  try {
    outcome = await Isolate.run<_Outcome<R>>(() => _capture(work));
  } on Object catch (error, stackTrace) {
    throw BackgroundWorkUnavailable(error, stackTrace);
  }
  return switch (outcome) {
    _Value<R>(:final value) => value,
    _Failure<R>(:final error, :final stackTrace) =>
      Error.throwWithStackTrace(error, stackTrace),
  };
}

_Outcome<R> _capture<R>(R Function() work) {
  try {
    return _Value<R>(work());
  } on Object catch (error, stackTrace) {
    return _Failure<R>(error, stackTrace);
  }
}

sealed class _Outcome<R> {
  const _Outcome();
}

final class _Value<R> extends _Outcome<R> {
  const _Value(this.value);

  final R value;
}

final class _Failure<R> extends _Outcome<R> {
  const _Failure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}
