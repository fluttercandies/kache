import 'dart:async';

/// Why an in-flight cache operation was cancelled.
enum KacheCancelReason {
  /// Explicit cancellation through a resource or client command.
  manual,

  /// New data replaced the in-flight result.
  dataSet,

  /// The key was invalidated before the operation completed.
  invalidate,

  /// The key was removed before the operation completed.
  remove,

  /// The key's namespace or the complete cache was cleared.
  clear,

  /// The owning client was closed.
  close,
}

/// A cooperative cancellation token passed to query fetchers.
final class KacheCancellationToken {
  const KacheCancellationToken._(this._state);

  /// A token that never becomes cancelled.
  static const KacheCancellationToken none = KacheCancellationToken._(null);

  final _KacheCancellationState? _state;

  /// Whether cancellation has been requested.
  bool get isCancelled => _state?.isCancelled ?? false;

  /// The cancellation reason, or `null` while this token remains active.
  KacheCancelReason? get reason => _state?.reason;

  /// Completes with the reason when cancellation is requested.
  ///
  /// The future never completes for [none].
  Future<KacheCancelReason> get whenCancelled =>
      _state?.whenCancelled ?? _neverCancelled;

  /// Throws [KacheCancelledException] when cancellation was requested.
  void throwIfCancelled() {
    if (reason case final reason?) {
      throw KacheCancelledException(reason);
    }
  }
}

/// Owns and idempotently cancels a [KacheCancellationToken].
final class KacheCancellationController {
  final _KacheCancellationState _state = _KacheCancellationState();

  /// The read-only token passed to a fetch operation.
  KacheCancellationToken get token => KacheCancellationToken._(_state);

  /// Requests cancellation and reports whether this call won the race.
  ///
  /// Repeated calls preserve the first [reason] and return `false`.
  bool cancel([KacheCancelReason reason = KacheCancelReason.manual]) =>
      _state.cancel(reason);
}

/// Signals cooperative cancellation without exposing cache data.
final class KacheCancelledException implements Exception {
  /// Creates a cancellation exception.
  const KacheCancelledException(this.reason);

  /// Why the operation was cancelled.
  final KacheCancelReason reason;

  @override
  String toString() => 'KacheCancelledException(reason: ${reason.name})';
}

final class _KacheCancellationState {
  final Completer<KacheCancelReason> _completer =
      Completer<KacheCancelReason>();

  bool get isCancelled => _completer.isCompleted;

  KacheCancelReason? get reason => isCancelled ? _completedReason : null;

  Future<KacheCancelReason> get whenCancelled => _completer.future;

  KacheCancelReason? _completedReason;

  bool cancel(KacheCancelReason reason) {
    if (isCancelled) {
      return false;
    }
    _completedReason = reason;
    _completer.complete(reason);
    return true;
  }
}

final Future<KacheCancelReason> _neverCancelled =
    Completer<KacheCancelReason>().future;
