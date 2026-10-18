import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kache/kache.dart';

/// Adapts [Connectivity] changes to Kache's two-state network contract.
///
/// A reported interface does not guarantee Internet access. Kache uses this
/// source only as a signal to retry active queries after connectivity returns.
///
/// Connectivity is checked again whenever the app resumes, because platforms
/// may drop change events in the background (connectivity_plus skips them on
/// iOS while the app is backgrounded).
final class ConnectivityPlusNetwork implements KacheNetwork {
  /// Creates an adapter backed by the connectivity_plus singleton.
  ///
  /// Pass [connectivity] to replace the platform dependency in tests or hosts
  /// that already manage a compatible [Connectivity] implementation.
  ///
  /// [binding] supplies app lifecycle events for resume checks. It defaults to
  /// [WidgetsBinding.instance] for the platform [Connectivity]. With an
  /// injected [connectivity], resume checks run only when [binding] is passed.
  ConnectivityPlusNetwork({
    Connectivity? connectivity,
    WidgetsBinding? binding,
  })  : _connectivity = connectivity ?? Connectivity(),
        _usesPlatform = connectivity == null,
        _explicitBinding = binding;

  final Connectivity _connectivity;
  final bool _usesPlatform;
  final WidgetsBinding? _explicitBinding;
  final StreamController<_StateRevision> _updates =
      StreamController<_StateRevision>.broadcast();
  late final _ResumeObserver _resumeObserver = _ResumeObserver(_recheck);

  StreamSubscription<List<ConnectivityResult>>? _sourceSubscription;
  WidgetsBinding? _binding;
  Future<void>? _pendingCheck;
  Future<void>? _closeFuture;
  Future<void>? _updatesCloseFuture;
  _StateRevision? _latest;
  int _revision = 0;
  int _sourceRevision = 0;
  bool _started = false;
  bool _sourceEnded = false;
  bool _updatesClosed = false;
  bool _closed = false;

  @override
  Stream<KacheNetworkState> get states =>
      Stream<KacheNetworkState>.multi((controller) {
        if (_closed) {
          controller.addErrorSync(
            StateError('ConnectivityPlusNetwork is closed.'),
          );
          controller.closeSync();
          return;
        }
        var deliveredRevision = -1;
        KacheNetworkState? deliveredState;
        _StateRevision? held;
        void deliver(_StateRevision update) {
          if (update.revision <= deliveredRevision) {
            return;
          }
          // A paused subscriber needs only the newest state on resume.
          if (controller.isPaused) {
            held = update;
            return;
          }
          deliveredRevision = update.revision;
          if (update.state == deliveredState) {
            return;
          }
          deliveredState = update.state;
          controller.addSync(update.state);
        }

        final subscription = _updates.stream.listen(
          deliver,
          onError: controller.addErrorSync,
          onDone: controller.closeSync,
        );
        controller
          ..onResume = () {
            final update = held;
            held = null;
            if (update != null) {
              deliver(update);
            }
          }
          ..onCancel = subscription.cancel;
        final latest = _latest;
        if (latest != null) {
          deliver(latest);
        }
        if (!_started) {
          _start();
        } else if (latest == null && _pendingCheck == null) {
          // A failed check left no current state; retry for this subscriber.
          _check();
        }
      }, isBroadcast: true);

  @override
  Future<void> close() => _closeFuture ??= _performClose();

  void _start() {
    _started = true;
    try {
      _sourceSubscription = _connectivity.onConnectivityChanged.listen(
        _handleChange,
        onError: _addError,
        onDone: _handleDone,
      );
    } on Object catch (error, stackTrace) {
      _addError(error, stackTrace);
      _sourceEnded = true;
    }
    _check();
    if (!_sourceEnded) {
      _attachLifecycle();
    }
  }

  void _attachLifecycle() {
    WidgetsBinding? binding = _explicitBinding;
    // Background isolates have no app lifecycle; the plugin itself uses the
    // background messenger there.
    if (binding == null &&
        _usesPlatform &&
        (kIsWeb || ServicesBinding.rootIsolateToken != null)) {
      try {
        binding = WidgetsBinding.instance;
      } on Object catch (error, stackTrace) {
        _addError(error, stackTrace);
      }
    }
    binding?.addObserver(_resumeObserver);
    _binding = binding;
  }

  /// Starts a check whose result applies only when no newer check or change
  /// event arrives before it completes.
  void _check() {
    if (_closed || _updatesClosed) {
      return;
    }
    final check = _runCheck(++_sourceRevision);
    _pendingCheck = check;
    unawaited(
      check.whenComplete(() {
        if (identical(_pendingCheck, check)) {
          _pendingCheck = null;
        }
        if (_sourceEnded && _pendingCheck == null) {
          unawaited(_closeUpdates());
        }
      }),
    );
  }

  Future<void> _runCheck(int revision) async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (revision == _sourceRevision) {
        _publish(_normalize(results));
      }
    } on Object catch (error, stackTrace) {
      _addError(error, stackTrace);
    }
  }

  void _recheck() {
    if (!_sourceEnded) {
      _check();
    }
  }

  void _handleChange(List<ConnectivityResult> results) {
    if (_closed) {
      return;
    }
    _sourceRevision += 1;
    try {
      _publish(_normalize(results));
    } on Object catch (error, stackTrace) {
      _addError(error, stackTrace);
    }
  }

  void _handleDone() {
    _sourceEnded = true;
    _detachLifecycle();
    if (_pendingCheck == null) {
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

  void _detachLifecycle() {
    _binding?.removeObserver(_resumeObserver);
    _binding = null;
  }

  Future<void> _performClose() async {
    _closed = true;
    _detachLifecycle();
    Object? cancellationError;
    StackTrace? cancellationStackTrace;
    var cancellationSettled = false;
    try {
      final cancellation = _sourceSubscription?.cancel();
      if (cancellation != null) {
        unawaited(
          cancellation.then<void>(
            (_) => cancellationSettled = true,
            onError: (Object error, StackTrace stackTrace) {
              cancellationError = error;
              cancellationStackTrace = stackTrace;
              cancellationSettled = true;
            },
          ),
        );
      }
    } on Object catch (error, stackTrace) {
      cancellationError = error;
      cancellationStackTrace = stackTrace;
      cancellationSettled = true;
    }
    unawaited(_closeUpdates());
    await Future<void>.value();
    final error = cancellationError;
    if (cancellationSettled && error != null) {
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
    return results.every((result) => result == ConnectivityResult.none)
        ? KacheNetworkState.unavailable
        : KacheNetworkState.available;
  }
}

final class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this._onResume);

  final void Function() _onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResume();
    }
  }
}

final class _StateRevision {
  const _StateRevision(this.revision, this.state);

  final int revision;
  final KacheNetworkState state;
}
