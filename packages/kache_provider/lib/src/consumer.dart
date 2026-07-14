import 'package:flutter/widgets.dart';
import 'package:kache_flutter/kache_flutter.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// Builds from a Provider-managed cache snapshot and controller.
final class KacheConsumer<T> extends SingleChildStatelessWidget {
  /// Creates a focused cache consumer.
  const KacheConsumer({required this.builder, super.child, super.key});

  /// Builds from the current snapshot, controller, and optional static child.
  final Widget Function(
    BuildContext context,
    KacheSnapshot<T> snapshot,
    KacheController<T> controller,
    Widget? child,
  )
  builder;

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    final controller = context.watch<KacheController<T>>();
    return builder(context, controller.value, controller, child);
  }
}
