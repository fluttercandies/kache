part of 'client.dart';

final class _KacheOperationVersion {
  const _KacheOperationVersion({
    required this.generation,
    required this.globalEpoch,
    required this.namespaceEpoch,
  });

  final int generation;
  final int globalEpoch;
  final int namespaceEpoch;
}

final class _KacheWriteQueue {
  _KacheWriteQueue({required void Function() onSettled})
    : _onSettled = onSettled;

  final void Function() _onSettled;
  Future<void>? _tail;
  int _cancellationEpoch = 0;
  int _taskCount = 0;

  bool get isIdle => _taskCount == 0;

  Future<bool> schedule({
    required Future<void> Function() operation,
    required bool Function() isValid,
  }) {
    final cancellationEpoch = _cancellationEpoch;
    final previous = _tail;
    final tailCompleter = Completer<void>();
    final result = Completer<bool>();
    final tail = tailCompleter.future;
    _tail = tail;
    _taskCount += 1;

    unawaited(() async {
      if (previous != null) {
        await previous;
      }
      try {
        if (cancellationEpoch != _cancellationEpoch || !isValid()) {
          result.complete(false);
          return;
        }
        await operation();
        result.complete(true);
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        _taskCount -= 1;
        tailCompleter.complete();
        if (identical(_tail, tail)) {
          _tail = null;
        }
        _onSettled();
      }
    }());
    return result.future;
  }

  void cancelPending() => _cancellationEpoch += 1;

  Future<void> drain() async {
    final tail = _tail;
    if (tail != null) {
      await tail;
    }
  }
}
