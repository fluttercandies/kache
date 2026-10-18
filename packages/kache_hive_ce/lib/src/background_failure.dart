/// The isolate mechanism could not run a piece of codec work.
///
/// This never wraps an error thrown by the codec itself.
final class BackgroundWorkUnavailable implements Exception {
  /// Creates a failure caused by [cause].
  const BackgroundWorkUnavailable(this.cause, this.stackTrace);

  /// The original isolate failure.
  final Object cause;

  /// The stack trace associated with [cause].
  final StackTrace stackTrace;

  @override
  String toString() => 'BackgroundWorkUnavailable';
}
