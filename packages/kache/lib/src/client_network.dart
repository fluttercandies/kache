part of 'client.dart';

final class _KacheCloseFailure implements Exception {
  const _KacheCloseFailure({
    required this.failure,
    required this.cause,
    required this.stackTrace,
  });

  final KacheFailure failure;
  final Object cause;
  final StackTrace stackTrace;
}

extension _KacheClientNetwork on KacheClient {
  void _startNetwork() {
    final source = network;
    if (source == null) {
      return;
    }
    _networkSubscription = source.states.listen(
      _handleNetworkState,
      onError: _handleNetworkError,
      onDone: _handleNetworkDone,
    );
  }

  void _handleNetworkState(KacheNetworkState state) {
    if (_isClosed) {
      return;
    }
    final previous = _networkState;
    _networkState = state;
    _trace(KacheEventTrigger.network)
        .span(KacheEventKind.network, layer: KacheLayer.network)
        .succeed(networkState: state);
    if (previous == KacheNetworkState.unavailable &&
        state == KacheNetworkState.available) {
      _requestReconnect();
    }
  }

  void _handleNetworkError(Object error, StackTrace stackTrace) {
    if (!_isClosed) {
      _emitNetworkFailure(error, stackTrace);
    }
  }

  void _handleNetworkDone() {
    if (!_isClosed) {
      _emitNetworkFailure(
        StateError('The network state stream ended unexpectedly.'),
        StackTrace.current,
      );
    }
  }

  void _requestReconnect() {
    if (_isClosed) {
      return;
    }
    if (_isReconnectPaused || _reconnectFuture != null) {
      _reconnectQueued = true;
      return;
    }
    late final Future<void> tracked;
    tracked = _runReconnect().whenComplete(() {
      if (identical(_reconnectFuture, tracked)) {
        _reconnectFuture = null;
      }
      if (_isClosed || _isReconnectPaused || !_reconnectQueued) {
        return;
      }
      _reconnectQueued = false;
      scheduleMicrotask(_requestReconnect);
    });
    _reconnectFuture = tracked;
    unawaited(tracked);
  }

  Future<void> _runReconnect() async {
    final trace = _trace(KacheEventTrigger.reconnect);
    final span = trace.span(KacheEventKind.reconnect)..start();
    try {
      final resources = _resources.toList(growable: false);
      await Future.wait<void>(
        resources.map((resource) => resource._revalidateOnReconnect(trace)),
      );
      span.succeed();
    } on Object catch (error, stackTrace) {
      final failure = KacheFailure(
        kind: KacheFailureKind.connectivity,
        cause: error,
        stackTrace: stackTrace,
      );
      span.fail(failure);
    }
  }

  void _emitNetworkFailure(Object error, StackTrace stackTrace) {
    final failure = KacheFailure(
      kind: KacheFailureKind.connectivity,
      cause: error,
      stackTrace: stackTrace,
    );
    _trace(KacheEventTrigger.network)
        .span(KacheEventKind.network, layer: KacheLayer.network)
        .fail(failure);
  }

  Future<void> _closeOwnedDependencies(_KacheTrace trace) async {
    _KacheCloseFailure? firstFailure;
    if (persistenceOwnership == KachePersistenceOwnership.owned) {
      final span = trace.span(
        KacheEventKind.close,
        layer: KacheLayer.persistence,
      )..start();
      try {
        await persistence!.close();
        span.succeed();
      } on Object catch (error, stackTrace) {
        final details = _normalizePersistenceError(
          error: error,
          stackTrace: stackTrace,
          expectedOperation: KachePersistenceOperation.close,
          fallbackStage: KachePersistenceStage.backend,
        );
        final cause = KachePersistenceException(
          operation: KachePersistenceOperation.close,
          stage: details.stage,
          cause: details.cause,
          stackTrace: details.stackTrace,
        );
        final failure = KacheFailure(
          kind: KacheFailureKind.persistenceClose,
          cause: details.cause,
          stackTrace: details.stackTrace,
          persistenceStage: details.stage,
        );
        span.fail(failure);
        firstFailure = _KacheCloseFailure(
          failure: failure,
          cause: cause,
          stackTrace: details.stackTrace,
        );
      }
    }
    if (networkOwnership == KacheNetworkOwnership.owned) {
      final span = trace.span(
        KacheEventKind.close,
        layer: KacheLayer.network,
      )..start();
      try {
        await network!.close();
        span.succeed();
      } on Object catch (error, stackTrace) {
        final failure = KacheFailure(
          kind: KacheFailureKind.connectivity,
          cause: error,
          stackTrace: stackTrace,
        );
        span.fail(failure);
        firstFailure ??= _KacheCloseFailure(
          failure: failure,
          cause: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (firstFailure case final failure?) {
      Error.throwWithStackTrace(failure, failure.stackTrace);
    }
  }
}
