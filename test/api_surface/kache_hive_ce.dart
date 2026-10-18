import 'package:kache_hive_ce/kache_hive_ce.dart';

void verifyHiveCeTypes({
  required HiveCeKacheStore store,
  required HiveCeBoxOwnership ownership,
  required HiveCeBinding<int> binding,
  required HiveCeAdapterBinding<int> adapterBinding,
  required HiveCeCodec<int> codec,
}) {}

HiveCeMigrator<int> verifyMigrator(HiveCeMigrator<int> migrator) => migrator;

Future<HiveCeKacheStore> verifyIsolateThreshold() =>
    HiveCeKacheStore.open(boxName: 'api_surface', isolateThreshold: 64 * 1024);

int? verifyStoreThreshold(HiveCeKacheStore store) => store.isolateThreshold;
