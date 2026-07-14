import 'dart:async';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:kache_connectivity_plus/kache_connectivity_plus.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

import 'gateway.dart';
import 'persistence_demo.dart';
import 'repository_profile.dart';

/// Owns the network, Hive CE store, client, and query used by an example app.
final class ExampleRuntime {
  ExampleRuntime._({
    required this.client,
    required this.query,
    required this.cacheFirstQuery,
    required this.cacheOnlyQuery,
    required this.networkOnlyQuery,
    required this.memoryQuery,
    required RepositoryGateway gateway,
    required void Function() closeNetwork,
  }) : _gateway = gateway,
       _closeNetwork = closeNetwork;

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
    KacheObserver? observer,
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
      observer: observer,
    );
    final fetch = gateway.fetch;
    final query = KacheQuery<RepositoryProfile>.persisted(
      key: KacheKey('github-repository', <Object?>['flutter/flutter']),
      binding: binding,
      fetch: fetch,
      policy: KachePolicy.staleWhileRevalidate(
        staleAfter: const Duration(minutes: 5),
        expireAfter: const Duration(days: 7),
        refreshOnLoad: KacheRevalidation.always,
        refreshOnResume: KacheRevalidation.always,
        refreshOnReconnect: KacheRevalidation.always,
      ),
      debugName: 'flutter/flutter repository',
    );
    // Distinct keys per strategy so each gets its own cache entry, letting the
    // Policies playground compare behaviour side-by-side without cross-talk.
    final cacheFirstQuery = KacheQuery<RepositoryProfile>.persisted(
      key: KacheKey('github-repository-cache-first', <Object?>[
        'flutter/flutter',
      ]),
      binding: binding,
      fetch: fetch,
      policy: KachePolicy.cacheFirst(
        freshFor: const Duration(minutes: 1),
        expireAfter: const Duration(days: 7),
      ),
      debugName: 'cache-first repository',
    );
    final cacheOnlyQuery = KacheQuery<RepositoryProfile>.persisted(
      key: KacheKey('github-repository-cache-only', <Object?>[
        'flutter/flutter',
      ]),
      binding: binding,
      fetch: fetch,
      policy: KachePolicy.cacheOnly(),
      debugName: 'cache-only repository',
    );
    final networkOnlyQuery = KacheQuery<RepositoryProfile>.networkOnly(
      key: KacheKey('github-repository-network-only', <Object?>[
        'flutter/flutter',
      ]),
      fetch: fetch,
      refreshInterval: const Duration(seconds: 30),
      debugName: 'network-only repository',
    );
    final memoryQuery = KacheQuery<RepositoryProfile>.memory(
      key: KacheKey('github-repository-memory', <Object?>['flutter/flutter']),
      fetch: fetch,
      debugName: 'memory-only repository',
    );
    return ExampleRuntime._(
      client: client,
      query: query,
      cacheFirstQuery: cacheFirstQuery,
      cacheOnlyQuery: cacheOnlyQuery,
      networkOnlyQuery: networkOnlyQuery,
      memoryQuery: memoryQuery,
      gateway: gateway,
      closeNetwork: closeNetwork ?? _closeNothing,
    );
  }

  /// Cache client owned by this runtime.
  final KacheClient client;

  /// Shared repository query used by every example integration.
  final KacheQuery<RepositoryProfile> query;

  /// Demonstrates [KachePolicy.cacheFirst]: serve fresh data, refresh when stale.
  final KacheQuery<RepositoryProfile> cacheFirstQuery;

  /// Demonstrates [KachePolicy.cacheOnly]: never fetch automatically.
  final KacheQuery<RepositoryProfile> cacheOnlyQuery;

  /// Demonstrates [KacheQuery.networkOnly]: no storage, always fetch + polling.
  final KacheQuery<RepositoryProfile> networkOnlyQuery;

  /// Demonstrates [KacheQuery.memory]: process-memory only, no persistence.
  final KacheQuery<RepositoryProfile> memoryQuery;

  final void Function() _closeNetwork;
  Future<void>? _closeFuture;

  /// Gateway used to build queries; retained so the persistence demo can share
  /// the same fetcher.
  final RepositoryGateway _gateway;

  Future<PersistenceDemo>? _persistenceDemoFuture;

  /// Lazily builds the persistence-API demo (fromBox/ownership, migrator,
  /// encrypted box, MemoryKachePersistence). The result is cached.
  Future<PersistenceDemo> persistenceDemo({required String boxPrefix}) {
    final existing = _persistenceDemoFuture;
    if (existing != null) {
      return existing;
    }
    final future = PersistenceDemo.open(
      gateway: _gateway,
      boxPrefix: boxPrefix,
    );
    _persistenceDemoFuture = future;
    return future;
  }

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
      final demo = _persistenceDemoFuture;
      if (demo != null) {
        try {
          await (await demo).close();
        } on Object {
          // Persistence demo close failures must not mask the main client close.
        }
      }
      await client.close();
    } finally {
      _closeNetwork();
    }
  }
}

void _closeNothing() {}
