import 'dart:async';

import 'package:kache/kache.dart';
import 'package:kache_contract_tests/persistence_contract.dart';

void main() {
  runPersistenceContract(
    backendName: 'MemoryKachePersistence',
    createHarness: _MemoryPersistenceHarness.new,
  );
}

final class _MemoryPersistenceHarness implements PersistenceContractHarness {
  @override
  final MemoryKachePersistence backend = MemoryKachePersistence();

  @override
  KachePersistenceBinding<T> bind<T>({required String fingerprint}) =>
      backend.bind<T>(fingerprint: fingerprint);

  @override
  FutureOr<void> dispose() => backend.close();
}
