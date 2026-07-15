part of 'client.dart';

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
    if (previous == KacheNetworkState.unavailable &&
        state == KacheNetworkState.available) {
      _requestReconnect();
    }
  }

  void _handleNetworkError(Object error, StackTrace stackTrace) {
    if (!_isClosed) {
      _reportConnectivityFailure(error, stackTrace);
    }
  }

  void _handleNetworkDone() {
    if (!_isClosed) {
      _reportConnectivityFailure(
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
    tracked = _performReconnect().whenComplete(() {
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

  Future<void> _performReconnect() async {
    _emitEvent(kind: KacheEventKind.reconnectStarted);
    try {
      await revalidateOnReconnect();
    } on Object catch (error, stackTrace) {
      _reportConnectivityFailure(error, stackTrace);
    } finally {
      _emitEvent(kind: KacheEventKind.reconnectCompleted);
    }
  }

  void _reportConnectivityFailure(Object error, StackTrace stackTrace) {
    _reportFailure(
      KacheFailure(
        kind: KacheFailureKind.connectivity,
        cause: error,
        stackTrace: stackTrace,
      ),
    );
  }

  Future<void> _closeOwnedDependencies() async {
    Object? firstError;
    StackTrace? firstStackTrace;
    if (persistenceOwnership == KachePersistenceOwnership.owned) {
      try {
        await persistence!.close();
      } on Object catch (error, stackTrace) {
        final details = _normalizePersistenceError(
          error: error,
          stackTrace: stackTrace,
          expectedOperation: KachePersistenceOperation.close,
          fallbackStage: KachePersistenceStage.backend,
        );
        firstError = KachePersistenceException(
          operation: KachePersistenceOperation.close,
          stage: details.stage,
          cause: details.cause,
          stackTrace: details.stackTrace,
        );
        firstStackTrace = details.stackTrace;
      }
    }
    if (networkOwnership == KacheNetworkOwnership.owned) {
      try {
        await network!.close();
      } on Object catch (error, stackTrace) {
        _reportConnectivityFailure(error, stackTrace);
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }
}
