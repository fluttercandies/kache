import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kache/kache.dart';
import 'package:kache_example_support/kache_example_support.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

void main() {
  test('owns an injected reconnect source', () async {
    final store = await HiveCeKacheStore.open(
      boxName: 'example_runtime_network',
      bytes: Uint8List(0),
    );
    final network = _TrackedNetwork();
    final runtime = ExampleRuntime.fromDependencies(
      store: store,
      gateway: _FakeRepositoryGateway(_profile()),
      network: network,
    );

    expect(runtime.client.network, same(network));
    expect(runtime.query.policy.refreshOnReconnect, KacheRevalidation.always);
    await runtime.close();
    await runtime.close();

    expect(network.closeCount, 1);
  });

  test(
    'fetches through the gateway and persists the repository profile',
    () async {
      final store = await HiveCeKacheStore.open(
        boxName: 'example_runtime_fetch',
        bytes: Uint8List(0),
      );
      final gateway = _FakeRepositoryGateway(_profile());
      final runtime = ExampleRuntime.fromDependencies(
        store: store,
        gateway: gateway,
      );

      final snapshot = await runtime.client.prefetch(runtime.query);
      final persisted = await store.read<RepositoryProfile>(
        key: runtime.query.key,
        binding: runtime.query.binding!,
      );

      expect(snapshot.requireData, _profile());
      expect(gateway.fetchCount, 1);
      expect(persisted?.entry.data, _profile());

      final closing = runtime.close();
      expect(runtime.close(), same(closing));
      await closing;
      expect(runtime.client.isClosed, isTrue);
      expect(store.box.isOpen, isFalse);
    },
  );

  test(
    'uses stale-while-revalidate with an always-refresh load policy',
    () async {
      final store = await HiveCeKacheStore.open(
        boxName: 'example_runtime_policy',
        bytes: Uint8List(0),
      );
      final runtime = ExampleRuntime.fromDependencies(
        store: store,
        gateway: _FakeRepositoryGateway(_profile()),
      );

      expect(runtime.query.policy.refreshOnLoad, KacheRevalidation.always);
      expect(runtime.query.policy.retainDataOnError, isTrue);

      await runtime.close();
    },
  );
}

final class _TrackedNetwork implements KacheNetwork {
  int closeCount = 0;

  @override
  Stream<KacheNetworkState> get states => const Stream.empty();

  @override
  Future<void> close() async {
    closeCount += 1;
  }
}

final class _FakeRepositoryGateway implements RepositoryGateway {
  _FakeRepositoryGateway(this.profile);

  final RepositoryProfile profile;
  int fetchCount = 0;

  @override
  Future<RepositoryProfile> fetch(KacheFetchContext context) async {
    fetchCount += 1;
    context.throwIfCancelled();
    return profile;
  }
}

RepositoryProfile _profile() => RepositoryProfile(
  fullName: 'flutter/flutter',
  description: 'Flutter makes it easy to build beautiful apps.',
  htmlUrl: 'https://github.com/flutter/flutter',
  ownerAvatarUrl: 'https://avatars.example/flutter.png',
  stars: 170000,
  forks: 29000,
  openIssues: 12000,
  language: 'Dart',
  updatedAt: DateTime.utc(2026, 7, 14, 8, 30),
);
