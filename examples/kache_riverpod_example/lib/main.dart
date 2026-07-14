import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kache_example_support/kache_example_support.dart';
import 'package:kache_riverpod/kache_riverpod.dart';

void main() {
  runApp(const KacheRiverpodExampleApp());
}

final _runtimeProvider = Provider<ExampleRuntime>((ref) {
  throw StateError('ExampleRuntime must be overridden by the application.');
});

final _repositoryProvider = kacheProvider<RepositoryProfile>(
  client: (ref) => ref.watch(_runtimeProvider).client,
  query: (ref) => ref.watch(_runtimeProvider).query,
);

class KacheRiverpodExampleApp extends StatelessWidget {
  const KacheRiverpodExampleApp({
    this.runtimeFactory,
    this.showNetworkImage = true,
    super.key,
  });

  final ExampleRuntimeFactory? runtimeFactory;
  final bool showNetworkImage;

  @override
  Widget build(BuildContext context) => KacheExampleApp(
    adapterName: 'Riverpod',
    boxName: 'kache_riverpod_example_repository_v1',
    runtimeFactory: runtimeFactory,
    builder: (context, runtime) => ProviderScope(
      overrides: [_runtimeProvider.overrideWithValue(runtime)],
      child: Consumer(
        builder: (context, ref, child) {
          final snapshot = ref.watch(_repositoryProvider);
          final notifier = ref.read(_repositoryProvider.notifier);
          return RepositoryDashboard(
            adapterName: 'Riverpod',
            snapshot: snapshot,
            onRefresh: notifier.refresh,
            onClear: notifier.remove,
            showNetworkImage: showNetworkImage,
          );
        },
      ),
    ),
  );
}
