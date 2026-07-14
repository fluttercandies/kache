import 'package:flutter/widgets.dart';
import 'package:kache_flutter/kache_flutter.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// Provides one [KacheController] using Provider's ChangeNotifier integration.
///
/// The widget owns and disposes the controller but always borrows its client.
/// When [client] is omitted, the nearest [KacheScope] supplies it.
class KacheProvider<T> extends SingleChildStatefulWidget {
  /// Creates a Provider-compatible cache binding.
  const KacheProvider({
    required this.query,
    this.client,
    super.child,
    super.key,
  });

  /// Optional client override. The nearest [KacheScope] is used when absent.
  final KacheClient? client;

  /// The query managed by the provided controller.
  final KacheQuery<T> query;

  @override
  State<KacheProvider<T>> createState() => _KacheProviderState<T>();
}

final class _KacheProviderState<T> extends SingleChildState<KacheProvider<T>> {
  KacheClient? _scopeClient;
  KacheClient? _boundClient;
  KacheController<T>? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scopeClient = KacheScope.maybeOf(context);
    _synchronize();
  }

  @override
  void didUpdateWidget(KacheProvider<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _synchronize();
  }

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    final controller = _controller;
    if (controller == null) {
      throw StateError('KacheProvider did not initialize its controller.');
    }
    return ChangeNotifierProvider<KacheController<T>>.value(
      value: controller,
      child: child,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _synchronize() {
    final client = widget.client ?? _scopeClient;
    if (client == null) {
      throw FlutterError(
        'KacheProvider requires either an explicit client or a KacheScope.',
      );
    }
    final controller = _controller;
    if (controller == null || !identical(_boundClient, client)) {
      controller?.dispose();
      _boundClient = client;
      _controller = KacheController<T>(client: client, query: widget.query);
      return;
    }
    controller.updateQuery(widget.query);
  }
}
