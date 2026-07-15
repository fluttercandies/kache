import 'package:kache_bloc/kache_bloc.dart';

void verifyBlocTypes({
  required KacheCubit<int> cubit,
  required KacheBlocBinding<int> binding,
}) {}

KacheBlocSnapshotListener<int> verifyBlocListener(
  KacheBlocSnapshotListener<int> listener,
) => listener;

Future<KacheSnapshot<int>> verifyCubitRefresh(KacheCubit<int> cubit) =>
    cubit.refresh();

Future<KacheSnapshot<int>> verifyBindingRefresh(
  KacheBlocBinding<int> binding,
) => binding.refresh();
