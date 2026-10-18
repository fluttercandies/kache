import 'package:flutter/widgets.dart';
import 'package:kache_connectivity_plus/kache_connectivity_plus.dart';

void verifyConnectivityPlusTypes({
  required ConnectivityPlusNetwork network,
  required Connectivity connectivity,
  required ConnectivityResult result,
  required KacheNetworkState state,
  required WidgetsBinding binding,
}) {
  ConnectivityPlusNetwork(connectivity: connectivity, binding: binding);
  network.states;
  network.close();
}
