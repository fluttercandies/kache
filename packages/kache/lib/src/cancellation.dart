import 'dart:async';

/// A cooperative cancellation token passed to query fetchers.
final class KacheCancellationToken {
  const KacheCancellationToken._(this._state);

  /// A token that never becomes cancelled.
  static const KacheCancellationToken none = KacheCancellationToken._(null);

  final _KacheCancellationState? _state;

  /// Whether cancellation has been requested.
  bool get isCancelled => _state?.isCancelled ?? false;

  /// Completes when cancellation is requested, or never for [none].
  Future<void> get whenCancelled => _state?.whenCancelled ?? _neverCancelled;

  /// Throws [KacheCancelledException] when cancellation was requested.
  void throwIfCancelled() {
    if (isCancelled) {
      throw const KacheCancelledException();
    }
  }
}

/// Owns and idempotently cancels a [KacheCancellationToken].
final class KacheCancellationController {
  final _KacheCancellationState _state = _KacheCancellationState();

  /// The read-only token passed to a fetch operation.
  KacheCancellationToken get token => KacheCancellationToken._(_state);

  /// Requests cancellation. Repeated calls have no effect.
  void cancel() => _state.cancel();
}

/// Signals cooperative cancellation without exposing cache data.
final class KacheCancelledException implements Exception {
  /// Creates a cancellation exception.
  const KacheCancelledException();

  @override
  String toString() => 'KacheCancelledException: Operation was cancelled.';
}

final class _KacheCancellationState {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!isCancelled) {
      _completer.complete();
    }
  }
}

final Future<void> _neverCancelled = Completer<void>().future;
