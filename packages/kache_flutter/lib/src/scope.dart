import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kache/kache.dart';

/// Determines whether a [KacheScope] closes its client.
enum KacheScopeOwnership {
  /// The client lifecycle is managed outside the widget tree.
  borrowed,

  /// The scope closes the client when replaced or disposed.
  owned,
}

/// Reports asynchronous scope lifecycle failures.
typedef KacheScopeErrorHandler = void Function(
    Object error, StackTrace stackTrace);

/// Provides a [KacheClient] and bridges Flutter application lifecycle events.
class KacheScope extends StatefulWidget {
  /// Creates a client scope.
  const KacheScope({
    required this.client,
    required this.child,
    this.ownership = KacheScopeOwnership.borrowed,
    this.onError,
    super.key,
  });

  /// The client exposed to descendants.
  final KacheClient client;

  /// Whether this scope closes [client].
  final KacheScopeOwnership ownership;

  /// Optional asynchronous lifecycle failure handler.
  final KacheScopeErrorHandler? onError;

  /// The subtree receiving the client.
  final Widget child;

  /// Returns the nearest client and subscribes to scope replacement.
  static KacheClient of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_KacheInheritedScope>();
    assert(scope != null, 'No KacheScope found in this BuildContext.');
    if (scope == null) {
      throw FlutterError('No KacheScope found in this BuildContext.');
    }
    return scope.client;
  }

  /// Returns the nearest client, or `null` outside a scope.
  static KacheClient? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_KacheInheritedScope>()
      ?.client;

  /// Explicitly refreshes every active resource after host connectivity returns.
  static Future<void> refreshActive(BuildContext context) =>
      of(context).refreshActive();

  @override
  State<KacheScope> createState() => _KacheScopeState();
}

final class _KacheScopeState extends State<KacheScope>
    with WidgetsBindingObserver {
  AppLifecycleState? _lifecycleState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    _syncAutoRefresh(widget.client);
  }

  @override
  void didUpdateWidget(KacheScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client)) {
      _syncAutoRefresh(widget.client);
      if (oldWidget.ownership == KacheScopeOwnership.owned) {
        _closeClient(oldWidget.client, oldWidget.onError);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncAutoRefresh(widget.client);
    if (state == AppLifecycleState.resumed && !widget.client.isClosed) {
      _observe(widget.client.revalidateOnResume());
    }
  }

  @override
  Widget build(BuildContext context) =>
      _KacheInheritedScope(client: widget.client, child: widget.child);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.ownership == KacheScopeOwnership.owned) {
      _closeClient(widget.client, widget.onError);
    }
    super.dispose();
  }

  void _observe(Future<void> future) {
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _report(error, stackTrace, widget.onError);
        },
      ),
    );
  }

  void _syncAutoRefresh(KacheClient client) {
    if (client.isClosed) {
      return;
    }
    if (_lifecycleState == AppLifecycleState.resumed) {
      client.resumePolling();
      client.resumeReconnect();
    } else if (_lifecycleState != null) {
      client.pausePolling();
      client.pauseReconnect();
    }
  }

  void _closeClient(KacheClient client, KacheScopeErrorHandler? errorHandler) {
    unawaited(
      client.close().then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _report(error, stackTrace, errorHandler);
        },
      ),
    );
  }

  void _report(
    Object error,
    StackTrace stackTrace,
    KacheScopeErrorHandler? errorHandler,
  ) {
    if (errorHandler != null) {
      errorHandler(error, stackTrace);
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'kache_flutter',
        context: ErrorDescription('while handling Kache scope lifecycle'),
      ),
    );
  }
}

final class _KacheInheritedScope extends InheritedWidget {
  const _KacheInheritedScope({required this.client, required super.child});

  final KacheClient client;

  @override
  bool updateShouldNotify(_KacheInheritedScope oldWidget) =>
      !identical(client, oldWidget.client);
}
