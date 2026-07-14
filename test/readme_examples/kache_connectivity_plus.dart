import 'package:kache_connectivity_plus/kache_connectivity_plus.dart';

KacheClient createClient() {
  final network = ConnectivityPlusNetwork();
  return KacheClient(
    network: network,
    networkOwnership: KacheNetworkOwnership.owned,
  );
}
