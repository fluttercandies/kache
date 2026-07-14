import 'package:flutter/material.dart';
import 'package:kache_example_support/kache_example_support.dart';
import 'package:kache_provider/kache_provider.dart';

void main() {
  runApp(const KacheProviderExampleApp());
}

class KacheProviderExampleApp extends StatelessWidget {
  const KacheProviderExampleApp({
    this.runtimeFactory,
    this.showNetworkImage = true,
    super.key,
  });

  final ExampleRuntimeFactory? runtimeFactory;
  final bool showNetworkImage;

  @override
  Widget build(BuildContext context) => KacheExampleApp(
    adapterName: 'Provider',
    boxName: 'kache_provider_example_repository_v1',
    runtimeFactory: runtimeFactory,
    builder: (context, runtime) => KacheProvider<RepositoryProfile>(
      query: runtime.query,
      child: KacheConsumer<RepositoryProfile>(
        builder: (context, snapshot, controller, child) => RepositoryDashboard(
          adapterName: 'Provider',
          snapshot: snapshot,
          onRefresh: controller.refresh,
          onClear: controller.remove,
          showNetworkImage: showNetworkImage,
        ),
      ),
    ),
  );
}
