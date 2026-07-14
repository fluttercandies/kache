import 'dart:async';

import 'package:kache_bloc/kache_bloc.dart';
import 'package:test/test.dart';

void main() {
  test(
    'emits complete snapshots and retains data after refresh failure',
    () async {
      final client = KacheClient();
      final initialFetch = Completer<String>();
      var fetchCount = 0;
      final cubit = KacheCubit<String>(
        client: client,
        query: KacheQuery.memory(
          key: KacheKey('bloc', <Object?>['profile']),
          fetch: (context) {
            fetchCount += 1;
            if (fetchCount == 1) {
              return initialFetch.future;
            }
            return Future<String>.error(StateError('offline'));
          },
        ),
      );
      addTearDown(() async {
        await cubit.close();
        await client.close();
      });

      await pumpEventQueue();
      expect(cubit.state.phase, KachePhase.loading);

      initialFetch.complete('Ada');
      await initialFetch.future;
      await pumpEventQueue();

      expect(cubit.state.phase, KachePhase.ready);
      expect(cubit.state.requireData, 'Ada');

      final refreshed = await cubit.refresh();
      await pumpEventQueue();

      expect(refreshed.phase, KachePhase.ready);
      expect(refreshed.requireData, 'Ada');
      expect(refreshed.failure?.kind, KacheFailureKind.fetch);
      expect(cubit.state, same(refreshed));
    },
  );

  test('proxies all core resource commands', () async {
    final client = KacheClient();
    final cubit = KacheCubit<int>(
      client: client,
      query: KacheQuery.memory(
        key: KacheKey('bloc', <Object?>['counter']),
        policy: KachePolicy.cacheOnly(),
      ),
    );
    addTearDown(() async {
      await cubit.close();
      await client.close();
    });

    expect((await cubit.load()).failure?.kind, KacheFailureKind.cacheMiss);
    expect((await cubit.setData(1)).requireData, 1);
    expect(
      (await cubit.updateData(
        (snapshot) => snapshot.requireData + 1,
      )).requireData,
      2,
    );
    expect(
      (await cubit.invalidate(refetch: false)).freshness,
      KacheFreshness.stale,
    );
    expect((await cubit.remove()).phase, KachePhase.idle);
  });

  test('can be subclassed with domain-specific commands', () async {
    final client = KacheClient();
    final cubit = _ProfileCubit(client);
    addTearDown(() async {
      await cubit.close();
      await client.close();
    });

    expect((await cubit.rename('Grace')).requireData, 'Grace');
    expect(cubit.state.requireData, 'Grace');
  });
}

final class _ProfileCubit extends KacheCubit<String> {
  _ProfileCubit(KacheClient client)
    : super(
        client: client,
        query: KacheQuery.memory(
          key: KacheKey('bloc', <Object?>['subclass']),
          policy: KachePolicy.cacheOnly(),
        ),
      );

  Future<KacheSnapshot<String>> rename(String name) => setData(name);
}
