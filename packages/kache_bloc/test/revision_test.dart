import 'package:kache_bloc/kache_bloc.dart';
import 'package:test/test.dart';

void main() {
  test('concurrent command results never roll Cubit state back', () async {
    final backend = MemoryKachePersistence();
    final binding = backend.bind<int>(fingerprint: 'bloc-revision-v1');
    final client = KacheClient(persistence: backend);
    var fetches = 0;
    final cubit = KacheCubit<int>(
      client: client,
      query: KacheQuery<int>.persisted(
        key: KacheKey('bloc-revision'),
        binding: binding,
        fetch: (_) async => ++fetches,
      ),
    );
    final revisions = <int>[];
    final subscription = cubit.stream.listen(
      (snapshot) => revisions.add(snapshot.revision),
    );
    addTearDown(() async {
      await subscription.cancel();
      await cubit.close();
      await client.close();
    });
    await pumpEventQueue();
    revisions.clear();

    await Future.wait<KacheSnapshot<int>>(<Future<KacheSnapshot<int>>>[
      cubit.refresh(),
      cubit.setData(7),
      cubit.refresh(),
    ]);
    await pumpEventQueue();

    expect(revisions, isNotEmpty);
    for (var index = 1; index < revisions.length; index++) {
      expect(
        revisions[index],
        greaterThan(revisions[index - 1]),
        reason: 'revisions $revisions',
      );
    }
    expect(cubit.state, same(cubit.resource.snapshot));
  });

  test('a command result older than the stream state is not emitted', () async {
    final client = KacheClient();
    final cubit = KacheCubit<int>(
      client: client,
      query: KacheQuery<int>.memory(
        key: KacheKey('bloc-stale-result'),
        policy: KachePolicy.cacheOnly(),
      ),
    );
    addTearDown(() async {
      await cubit.close();
      await client.close();
    });
    await pumpEventQueue();

    final first = cubit.setData(1);
    final second = cubit.setData(2);
    final emitted = <int?>[];
    final subscription = cubit.stream.listen(
      (snapshot) => emitted.add(snapshot.dataOrNull),
    );
    final firstResult = await first;
    await second;
    await pumpEventQueue();
    await subscription.cancel();

    expect(firstResult.requireData, 1);
    expect(cubit.state.requireData, 2);
    expect(emitted.last, 2);
  });
}
