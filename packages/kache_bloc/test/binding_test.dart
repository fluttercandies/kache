import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:kache_bloc/kache_bloc.dart';
import 'package:test/test.dart';

void main() {
  test(
    'binding composes cache snapshots into an existing Cubit state',
    () async {
      final client = KacheClient();
      final fetch = Completer<int>();
      final binding = KacheBlocBinding<int>(
        client: client,
        query: KacheQuery.memory(
          key: KacheKey('bloc-binding', <Object?>['value']),
          fetch: (context) => fetch.future,
        ),
      );
      final cubit = _HostCubit(binding);
      addTearDown(() async {
        await cubit.close();
        await client.close();
      });

      await pumpEventQueue();
      expect(cubit.state.cache.phase, KachePhase.loading);

      fetch.complete(7);
      await fetch.future;
      await pumpEventQueue();

      expect(cubit.state.cache.requireData, 7);
      expect(cubit.state.changes, greaterThan(0));
      expect((await binding.setData(8)).requireData, 8);
      expect(cubit.state.cache.requireData, 8);
    },
  );

  test('binding rejects a second managed listener', () async {
    final client = KacheClient();
    final binding = KacheBlocBinding<int>(
      client: client,
      query: KacheQuery.memory(
        key: KacheKey('bloc-binding', <Object?>['single-listener']),
        policy: KachePolicy.cacheOnly(),
      ),
    );
    addTearDown(() async {
      await binding.close();
      await client.close();
    });

    binding.attach((snapshot) {});

    expect(
      () => binding.attach((snapshot) {}),
      throwsA(
        isA<KacheConfigurationException>().having(
          (error) => error.code,
          'code',
          'bloc_binding_already_attached',
        ),
      ),
    );
  });
}

typedef _HostState = ({KacheSnapshot<int> cache, int changes});

final class _HostCubit extends Cubit<_HostState> {
  _HostCubit(this.binding) : super((cache: binding.snapshot, changes: 0)) {
    binding.attach((snapshot) {
      if (!isClosed) {
        emit((cache: snapshot, changes: state.changes + 1));
      }
    });
  }

  final KacheBlocBinding<int> binding;

  @override
  Future<void> close() async {
    await binding.close();
    await super.close();
  }
}
