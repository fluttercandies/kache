import 'package:kache_connectivity_plus/kache_connectivity_plus.dart';

void verifyConnectivityPlusTypes({
  required ConnectivityPlusNetwork network,
  required Connectivity connectivity,
  required ConnectivityResult result,
  required KacheNetworkState state,
}) {
  network.states;
  network.close();
}
