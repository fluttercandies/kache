import 'package:flutter/widgets.dart';
import 'package:kache/kache.dart';

import 'controller.dart';
import 'scope.dart';

/// Builds Flutter UI from a cache snapshot and its controller.
typedef KacheWidgetBuilder<T> = Widget Function(
  BuildContext context,
  KacheSnapshot<T> snapshot,
  KacheController<T> controller,
);

/// Selects which cache transitions should rebuild a [KacheBuilder].
typedef KacheBuildWhen<T> = bool Function(
  KacheSnapshot<T> previous,
  KacheSnapshot<T> current,
);

/// Owns a [KacheController] for a query and rebuilds on snapshot changes.
class KacheBuilder<T> extends StatefulWidget {
  /// Creates a cache-aware builder.
  const KacheBuilder({
    required this.query,
    required this.builder,
    this.client,
    this.buildWhen,
    super.key,
  });

  /// Query bound to the widget lifecycle.
  final KacheQuery<T> query;

  /// Optional client override. Defaults to [KacheScope.of].
  final KacheClient? client;

  /// Builds from the complete cache snapshot.
  final KacheWidgetBuilder<T> builder;

  /// Optional transition predicate that decides whether to rebuild.
  ///
  /// Receives the snapshot of the last build and the new snapshot. Returning
  /// `false` skips the rebuild, for example when only
  /// [KacheSnapshot.persistence] changed. Rebuilds caused by a parent or a
  /// dependency reuse the snapshot of the last accepted build. Replacing the
  /// controller after a client or key change always rebuilds.
  final KacheBuildWhen<T>? buildWhen;

  @override
  State<KacheBuilder<T>> createState() => _KacheBuilderState<T>();
}

final class _KacheBuilderState<T> extends State<KacheBuilder<T>> {
  KacheController<T>? _controller;
  KacheClient? _client;
  late KacheSnapshot<T> _snapshot;
  late KacheResource<T> _resource;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _synchronizeClient();
  }

  @override
  void didUpdateWidget(KacheBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final resolvedClient = widget.client ?? KacheScope.of(context);
    if (!identical(_client, resolvedClient)) {
      _replaceController(resolvedClient);
      return;
    }
    if (!identical(oldWidget.query, widget.query)) {
      _controller!.updateQuery(widget.query);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _snapshot, _controller!);

  @override
  void dispose() {
    _controller?.removeListener(_handleChange);
    _controller?.dispose();
    super.dispose();
  }

  void _synchronizeClient() {
    final resolvedClient = widget.client ?? KacheScope.of(context);
    if (!identical(_client, resolvedClient)) {
      _replaceController(resolvedClient);
    }
  }

  void _replaceController(KacheClient client) {
    final replacement = KacheController<T>(
      client: client,
      query: widget.query,
    )..addListener(_handleChange);
    final previous = _controller;
    _client = client;
    _controller = replacement;
    _resource = replacement.resource;
    _snapshot = replacement.value;
    previous
      ?..removeListener(_handleChange)
      ..dispose();
  }

  void _handleChange() {
    final controller = _controller!;
    final current = controller.value;
    final previous = _snapshot;
    if (identical(previous, current)) {
      return;
    }
    final buildWhen = widget.buildWhen;
    // A new resource means the key changed; never keep the old key's data.
    final rebound = !identical(_resource, controller.resource);
    if (rebound || buildWhen == null || buildWhen(previous, current)) {
      setState(() {
        _resource = controller.resource;
        _snapshot = current;
      });
    }
  }
}
