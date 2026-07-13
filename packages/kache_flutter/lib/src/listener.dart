import 'package:flutter/widgets.dart';
import 'package:kache/kache.dart';

import 'controller.dart';

/// Receives a cache snapshot transition for side effects.
typedef KacheSnapshotListener<T> =
    void Function(
      BuildContext context,
      KacheSnapshot<T> previous,
      KacheSnapshot<T> current,
    );

/// Selects which cache transitions should invoke a listener.
typedef KacheListenWhen<T> =
    bool Function(KacheSnapshot<T> previous, KacheSnapshot<T> current);

/// Observes controller transitions without rebuilding [child].
class KacheListener<T> extends StatefulWidget {
  /// Creates a transition listener for an existing [controller].
  const KacheListener({
    required this.controller,
    required this.listener,
    required this.child,
    this.listenWhen,
    super.key,
  });

  /// Controller whose transitions are observed.
  final KacheController<T> controller;

  /// Side-effect callback invoked for selected transitions.
  final KacheSnapshotListener<T> listener;

  /// Optional transition predicate.
  final KacheListenWhen<T>? listenWhen;

  /// Subtree returned without cache-driven rebuilds.
  final Widget child;

  @override
  State<KacheListener<T>> createState() => _KacheListenerState<T>();
}

final class _KacheListenerState<T> extends State<KacheListener<T>> {
  late KacheSnapshot<T> _previous;

  @override
  void initState() {
    super.initState();
    _bind(widget.controller);
  }

  @override
  void didUpdateWidget(KacheListener<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleChange);
      _bind(widget.controller);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    widget.controller.removeListener(_handleChange);
    super.dispose();
  }

  void _bind(KacheController<T> controller) {
    _previous = controller.value;
    controller.addListener(_handleChange);
  }

  void _handleChange() {
    if (!mounted) {
      return;
    }
    final current = widget.controller.value;
    final previous = _previous;
    _previous = current;
    if (widget.listenWhen?.call(previous, current) ?? true) {
      widget.listener(context, previous, current);
    }
  }
}
