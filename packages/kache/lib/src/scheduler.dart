import 'dart:async';

/// A cancellable delayed callback used for deterministic cache GC.
abstract interface class KacheScheduledTask {
  /// Whether [cancel] has been called.
  bool get isCancelled;

  /// Prevents the callback from running. Repeated calls are harmless.
  void cancel();
}

/// Schedules [callback] after [delay].
typedef KacheScheduler =
    KacheScheduledTask Function(Duration delay, void Function() callback);

/// Schedules cache lifecycle work using a Dart [Timer].
KacheScheduledTask systemKacheScheduler(
  Duration delay,
  void Function() callback,
) => _TimerScheduledTask(delay, callback);

final class _TimerScheduledTask implements KacheScheduledTask {
  _TimerScheduledTask(Duration delay, void Function() callback)
    : _timer = Timer(delay, callback);

  final Timer _timer;
  bool _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _timer.cancel();
  }
}
