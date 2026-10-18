import 'background_failure.dart';

export 'background_failure.dart';

/// Whether this platform can run codec work on a background isolate.
///
/// Web compilers do not provide `dart:isolate`, so codec work always runs
/// inline there.
const bool supportsBackgroundWork = false;

/// Reports that background isolates are unavailable on this platform.
///
/// Callers check [supportsBackgroundWork] first; this keeps the contract
/// explicit if that check is ever bypassed.
Future<R> runInBackground<R>(R Function() work) => Future<R>.error(
      BackgroundWorkUnavailable(
        UnsupportedError('Background isolates are unavailable.'),
        StackTrace.current,
      ),
    );
