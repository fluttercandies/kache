import 'dart:async';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:kache_connectivity_plus/kache_connectivity_plus.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

import 'gateway.dart';
import 'repository_profile.dart';

/// Owns the network, Hive CE store, client, and query used by an example app.
final class ExampleRuntime {
  ExampleRuntime._({
    required this.client,
    required this.query,
    required void Function() closeNetwork,
  }) : _closeNetwork = closeNetwork;

  static Future<void>? _hiveInitialization;

  /// Opens a disk-backed runtime using Flutter's application documents path.
  static Future<ExampleRuntime> open({required String boxName}) async {
    await _initializeHive();
    final networkClient = http.Client();
    HiveCeKacheStore? store;
    try {
      store = await HiveCeKacheStore.open(boxName: boxName);
      return ExampleRuntime.fromDependencies(
        store: store,
        gateway: GitHubRepositoryGateway(client: networkClient),
        closeNetwork: networkClient.close,
        network: ConnectivityPlusNetwork(),
      );
    } on Object {
      await store?.close();
      networkClient.close();
      rethrow;
    }
  }

  /// Creates a runtime from explicit dependencies for deterministic tests.
  factory ExampleRuntime.fromDependencies({
    required HiveCeKacheStore store,
    required RepositoryGateway gateway,
    KacheNetwork? network,
    void Function()? closeNetwork,
  }) {
    final binding = store.bind<RepositoryProfile>(
      codecId: 'github-repository-profile-json',
      schema: 1,
      codec: repositoryProfileCodec,
    );
    final client = KacheClient(
      persistence: store,
      persistenceOwnership: KachePersistenceOwnership.owned,
      network: network,
      networkOwnership: network == null
          ? KacheNetworkOwnership.borrowed
          : KacheNetworkOwnership.owned,
    );
    final query = KacheQuery<RepositoryProfile>.persisted(
      key: KacheKey('github-repository', <Object?>['flutter/flutter']),
      binding: binding,
      fetch: gateway.fetch,
      policy: KachePolicy.staleWhileRevalidate(
        staleAfter: const Duration(minutes: 5),
        expireAfter: const Duration(days: 7),
        refreshOnLoad: KacheRevalidation.always,
        refreshOnResume: KacheRevalidation.always,
        refreshOnReconnect: KacheRevalidation.always,
      ),
      debugName: 'flutter/flutter repository',
    );
    return ExampleRuntime._(
      client: client,
      query: query,
      closeNetwork: closeNetwork ?? _closeNothing,
    );
  }

  /// Cache client owned by this runtime.
  final KacheClient client;

  /// Shared repository query used by every example integration.
  final KacheQuery<RepositoryProfile> query;

  final void Function() _closeNetwork;
  Future<void>? _closeFuture;

  /// Closes the client, owned Hive store, and network client exactly once.
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    final future = _performClose();
    _closeFuture = future;
    return future;
  }

  static Future<void> _initializeHive() {
    final existing = _hiveInitialization;
    if (existing != null) {
      return existing;
    }
    final future = Hive.initFlutter('kache_examples');
    _hiveInitialization = future;
    return future;
  }

  Future<void> _performClose() async {
    try {
      await client.close();
    } finally {
      _closeNetwork();
    }
  }
}

void _closeNothing() {}
