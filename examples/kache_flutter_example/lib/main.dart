import 'package:flutter/material.dart';
import 'package:kache_example_support/kache_example_support.dart';
import 'package:kache_flutter/kache_flutter.dart';

void main() {
  runApp(const KacheFlutterExampleApp());
}

class KacheFlutterExampleApp extends StatelessWidget {
  const KacheFlutterExampleApp({
    this.runtimeFactory,
    this.showNetworkImage = true,
    super.key,
  });

  final ExampleRuntimeFactory? runtimeFactory;
  final bool showNetworkImage;

  @override
  Widget build(BuildContext context) => KacheExampleApp(
    adapterName: 'Flutter',
    boxName: 'kache_flutter_example_repository_v1',
    runtimeFactory: runtimeFactory,
    builder: (context, runtime) => KacheBuilder<RepositoryProfile>(
      query: runtime.query,
      builder: (context, snapshot, controller) => RepositoryDashboard(
        adapterName: 'Flutter',
        snapshot: snapshot,
        onRefresh: controller.refresh,
        onClear: controller.remove,
        showNetworkImage: showNetworkImage,
      ),
    ),
  );
}
