import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kache_bloc/kache_bloc.dart';
import 'package:kache_example_support/kache_example_support.dart';

void main() {
  runApp(const KacheBlocExampleApp());
}

class KacheBlocExampleApp extends StatelessWidget {
  const KacheBlocExampleApp({
    this.runtimeFactory,
    this.showNetworkImage = true,
    super.key,
  });

  final ExampleRuntimeFactory? runtimeFactory;
  final bool showNetworkImage;

  @override
  Widget build(BuildContext context) => KacheExampleApp(
    adapterName: 'Bloc/Cubit',
    boxName: 'kache_bloc_example_repository_v1',
    runtimeFactory: runtimeFactory,
    builder: (context, runtime) => BlocProvider<KacheCubit<RepositoryProfile>>(
      lazy: false,
      create: (context) => KacheCubit<RepositoryProfile>(
        client: runtime.client,
        query: runtime.query,
      ),
      child:
          BlocBuilder<
            KacheCubit<RepositoryProfile>,
            KacheSnapshot<RepositoryProfile>
          >(
            builder: (context, snapshot) {
              final cubit = context.read<KacheCubit<RepositoryProfile>>();
              return RepositoryDashboard(
                adapterName: 'Bloc/Cubit',
                snapshot: snapshot,
                onRefresh: cubit.refresh,
                onClear: cubit.remove,
                showNetworkImage: showNetworkImage,
              );
            },
          ),
    ),
  );
}
