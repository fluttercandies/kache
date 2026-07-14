import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:kache/kache.dart';

/// Adapts [Connectivity] changes to Kache's two-state network contract.
///
/// A reported interface does not guarantee Internet access. Kache uses this
/// source only as a signal to retry active queries after connectivity returns.
final class ConnectivityPlusNetwork implements KacheNetwork {
  /// Creates an adapter backed by the connectivity_plus singleton.
  ///
  /// Pass [connectivity] to replace the platform dependency in tests or hosts
  /// that already manage a compatible [Connectivity] implementation.
  ConnectivityPlusNetwork({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final StreamController<_StateRevision> _updates =
      StreamController<_StateRevision>.broadcast(sync: true);

  StreamSubscription<List<ConnectivityResult>>? _sourceSubscription;
  Future<void>? _closeFuture;
  Future<void>? _updatesCloseFuture;
  _StateRevision? _latest;
  int _revision = 0;
  int _changeRevision = 0;
  bool _started = false;
  bool _initialComplete = false;
  bool _sourceEnded = false;
  bool _updatesClosed = false;
  bool _closed = false;

  @override
  Stream<KacheNetworkState> get states {
    if (_closed) {
      return Stream<KacheNetworkState>.error(
        StateError('ConnectivityPlusNetwork is closed.'),
      );
    }
    return Stream<KacheNetworkState>.multi((controller) {
      if (_closed) {
        controller.addErrorSync(
          StateError('ConnectivityPlusNetwork is closed.'),
        );
        controller.closeSync();
        return;
      }
      var deliveredRevision = -1;
      void deliver(_StateRevision update) {
        if (update.revision <= deliveredRevision) {
          return;
        }
        deliveredRevision = update.revision;
        controller.addSync(update.state);
      }

      final subscription = _updates.stream.listen(
        deliver,
        onError: controller.addErrorSync,
        onDone: controller.closeSync,
      );
      final latest = _latest;
      if (latest != null) {
        deliver(latest);
      }
      controller.onCancel = subscription.cancel;
      _start();
    }, isBroadcast: true);
  }

  @override
  Future<void> close() => _closeFuture ??= _performClose();

  void _start() {
    if (_started || _closed) {
      return;
    }
    _started = true;
    final initialChangeRevision = _changeRevision;
    try {
      _sourceSubscription = _connectivity.onConnectivityChanged.listen(
        _handleChange,
        onError: _handleError,
        onDone: _handleDone,
      );
    } on Object catch (error, stackTrace) {
      _addError(error, stackTrace);
      _sourceEnded = true;
    }
    unawaited(_checkInitial(initialChangeRevision));
  }

  Future<void> _checkInitial(int initialChangeRevision) async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (!_closed && _changeRevision == initialChangeRevision) {
        _publish(_normalize(results));
      }
    } on Object catch (error, stackTrace) {
      _addError(error, stackTrace);
    } finally {
      _initialComplete = true;
      if (_sourceEnded) {
        unawaited(_closeUpdates());
      }
    }
  }

  void _handleChange(List<ConnectivityResult> results) {
    if (_closed) {
      return;
    }
    _changeRevision += 1;
    try {
      _publish(_normalize(results));
    } on Object catch (error, stackTrace) {
      _addError(error, stackTrace);
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    _addError(error, stackTrace);
  }

  void _handleDone() {
    _sourceEnded = true;
    if (_initialComplete) {
      unawaited(_closeUpdates());
    }
  }

  void _publish(KacheNetworkState state) {
    if (_closed || _updatesClosed || _latest?.state == state) {
      return;
    }
    final update = _StateRevision(++_revision, state);
    _latest = update;
    _updates.add(update);
  }

  void _addError(Object error, StackTrace stackTrace) {
    if (!_closed && !_updatesClosed) {
      _updates.addError(error, stackTrace);
    }
  }

  Future<void> _performClose() async {
    _closed = true;
    Object? cancellationError;
    StackTrace? cancellationStackTrace;
    try {
      await _sourceSubscription?.cancel();
    } on Object catch (error, stackTrace) {
      cancellationError = error;
      cancellationStackTrace = stackTrace;
    } finally {
      await _closeUpdates();
    }
    if (cancellationError case final error?) {
      Error.throwWithStackTrace(error, cancellationStackTrace!);
    }
  }

  Future<void> _closeUpdates() {
    final existing = _updatesCloseFuture;
    if (existing != null) {
      return existing;
    }
    _updatesClosed = true;
    final close = _updates.close();
    _updatesCloseFuture = close;
    return close;
  }

  static KacheNetworkState _normalize(List<ConnectivityResult> results) {
    if (results.isEmpty) {
      throw StateError('connectivity_plus returned an empty result list.');
    }
    return results.contains(ConnectivityResult.none)
        ? KacheNetworkState.unavailable
        : KacheNetworkState.available;
  }
}

final class _StateRevision {
  const _StateRevision(this.revision, this.state);

  final int revision;
  final KacheNetworkState state;
}
