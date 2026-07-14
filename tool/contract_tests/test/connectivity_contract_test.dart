import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kache_connectivity_plus/kache_connectivity_plus.dart';

void main() {
  test('connectivity_plus recovery drives core reconnect policy', () async {
    final connectivity = _FakeConnectivity();
    final network = ConnectivityPlusNetwork(connectivity: connectivity);
    final client = KacheClient(
      network: network,
      networkOwnership: KacheNetworkOwnership.owned,
    );
    var fetches = 0;
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('connectivity-contract'),
        policy: KachePolicy.staleWhileRevalidate(
          refreshOnLoad: KacheRevalidation.never,
          refreshOnReconnect: KacheRevalidation.always,
        ),
        fetch: (_) async => ++fetches,
      ),
    );
    await resource.setData(0);
    await pumpEventQueue();
    expect(client.networkState, KacheNetworkState.unavailable);

    final completed = client.events.firstWhere(
      (event) => event.kind == KacheEventKind.reconnectCompleted,
    );
    connectivity.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
    await completed;

    expect(fetches, 1);
    expect(resource.snapshot.requireData, 1);
    resource.dispose();
    await client.close();
    await connectivity.close();
  });
}

final class _FakeConnectivity implements Connectivity {
  final StreamController<List<ConnectivityResult>> _changes =
      StreamController<List<ConnectivityResult>>.broadcast(sync: true);

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      <ConnectivityResult>[ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;

  void emit(List<ConnectivityResult> results) => _changes.add(results);

  Future<void> close() => _changes.close();
}
