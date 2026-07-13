import 'package:flutter/widgets.dart';
import 'package:kache/kache.dart';

import 'controller.dart';
import 'scope.dart';

/// Builds Flutter UI from a cache snapshot and its controller.
typedef KacheWidgetBuilder<T> =
    Widget Function(
      BuildContext context,
      KacheSnapshot<T> snapshot,
      KacheController<T> controller,
    );

/// Owns a [KacheController] for a query and rebuilds on snapshot changes.
class KacheBuilder<T> extends StatefulWidget {
  /// Creates a cache-aware builder.
  const KacheBuilder({
    required this.query,
    required this.builder,
    this.client,
    super.key,
  });

  /// Query bound to the widget lifecycle.
  final KacheQuery<T> query;

  /// Optional client override. Defaults to [KacheScope.of].
  final KacheClient? client;

  /// Builds from the complete cache snapshot.
  final KacheWidgetBuilder<T> builder;

  @override
  State<KacheBuilder<T>> createState() => _KacheBuilderState<T>();
}

final class _KacheBuilderState<T> extends State<KacheBuilder<T>> {
  KacheController<T>? _controller;
  KacheClient? _client;

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
  Widget build(BuildContext context) {
    final controller = _controller!;
    return ValueListenableBuilder<KacheSnapshot<T>>(
      valueListenable: controller,
      builder: (context, snapshot, _) =>
          widget.builder(context, snapshot, controller),
    );
  }

  @override
  void dispose() {
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
    _controller?.dispose();
    _client = client;
    _controller = KacheController<T>(client: client, query: widget.query);
  }
}
