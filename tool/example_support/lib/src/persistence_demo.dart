import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kache/kache.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

import 'gateway.dart';
import 'repository_profile.dart';

/// Demonstrates persistence-layer API surfaces that complement the main
/// `HiveCeKacheStore.open` + `bind` path shown by [ExampleRuntime].
///
/// Each field corresponds to one capability users learn from this demo:
///
/// * [borrowedStore]: [HiveCeKacheStore.fromBox] with borrowed ownership.
/// * [migratorBinding]: [HiveCeKacheStore.bind] with a [HiveCeMigrator].
/// * [encryptedStore]: an encrypted box opened via `encryptionCipher`.
/// * [memoryClient] / [memoryQuery]: a custom [KachePersistenceBackend] built
///   from the SDK-only [MemoryKachePersistence].
final class PersistenceDemo {
  PersistenceDemo._({
    required this.borrowedStore,
    required this.borrowedBox,
    required this.migratorBinding,
    required this.encryptedStore,
    required this.memoryBackend,
    required this.memoryClient,
    required this.memoryQuery,
    required this.memorySnapshot,
  });

  /// Builds a persistence demo sharing the main runtime's gateway fetcher.
  ///
  /// [boxPrefix] namespaces the demo boxes so they never collide with the main
  /// runtime's repository box.
  static Future<PersistenceDemo> open({
    required RepositoryGateway gateway,
    required String boxPrefix,
  }) async {
    // 1) HiveCeKacheStore.fromBox + HiveCeBoxOwnership.borrowed.
    //    The caller opens the raw Hive box; Kache wraps it but does NOT close
    //    it (borrowed). This is the pattern for sharing a box across clients.
    final borrowedBoxName = '${boxPrefix}_borrowed';
    final borrowedBox = await Hive.openBox<Object?>(
      borrowedBoxName,
      crashRecovery: true,
    );
    final borrowedStore = HiveCeKacheStore.fromBox(
      borrowedBox,
      ownership: HiveCeBoxOwnership.borrowed,
    );

    // 2) bind() with a HiveCeMigrator that upgrades a legacy schema-0 payload.
    //    The migrator runs automatically when an older record is read.
    final migratorBinding = borrowedStore.bind<RepositoryProfile>(
      codecId: 'github-repository-profile-json',
      schema: 1,
      codec: repositoryProfileCodec,
      migrate: _migrateFromLegacy,
    );

    // 3) An encrypted box opened with a HiveCipher. Kache never holds or logs
    //    the key; the cipher is owned by the caller.
    final cipher = HiveAesCipher(_demoEncryptionKey);
    final encryptedStore = await HiveCeKacheStore.open(
      boxName: '${boxPrefix}_encrypted',
      encryptionCipher: cipher,
    );

    // 4) MemoryKachePersistence: a custom KachePersistenceBackend implemented
    //    entirely in the core SDK (no Hive, no Flutter). Useful for tests and
    //    for callers who want process-local typed persistence without a binary
    //    format. We back a real client with it so the demo query round-trips.
    final memoryBackend = MemoryKachePersistence();
    final memoryBinding = memoryBackend.bind<RepositoryProfile>(
      fingerprint: 'example-memory:v1',
    );
    final memoryClient = KacheClient(
      persistence: memoryBackend,
      persistenceOwnership: KachePersistenceOwnership.owned,
    );
    final memoryQuery = KacheQuery<RepositoryProfile>.persisted(
      key: KacheKey('persistence-demo-memory', <Object?>['borrowed-box']),
      binding: memoryBinding,
      fetch: gateway.fetch,
      policy: KachePolicy.cacheFirst(
        freshFor: const Duration(minutes: 5),
        expireAfter: const Duration(days: 1),
      ),
      debugName: 'persistence-demo memory backend',
    );
    final memorySnapshot = await memoryClient.prefetch(memoryQuery);

    return PersistenceDemo._(
      borrowedStore: borrowedStore,
      borrowedBox: borrowedBox,
      migratorBinding: migratorBinding,
      encryptedStore: encryptedStore,
      memoryBackend: memoryBackend,
      memoryClient: memoryClient,
      memoryQuery: memoryQuery,
      memorySnapshot: memorySnapshot,
    );
  }

  /// Store built from [HiveCeKacheStore.fromBox] with borrowed ownership.
  final HiveCeKacheStore borrowedStore;

  /// The raw Hive box that [borrowedStore] wraps; owned by this demo.
  final Box<Object?> borrowedBox;

  /// Binding that carries a [HiveCeMigrator] for legacy schema upgrades.
  final HiveCeBinding<RepositoryProfile> migratorBinding;

  /// Store backed by an encrypted Hive box (cipher owned by the caller).
  final HiveCeKacheStore encryptedStore;

  /// SDK-only in-memory backend used to demonstrate a custom persistence layer.
  final MemoryKachePersistence memoryBackend;

  /// Client backed by [memoryBackend].
  final KacheClient memoryClient;

  /// Query round-tripping through [memoryBackend].
  final KacheQuery<RepositoryProfile> memoryQuery;

  /// Result of the real write/read path executed when the demo opens.
  final KacheSnapshot<RepositoryProfile> memorySnapshot;

  /// Closes every backend owned by this demo exactly once.
  Future<void> close() => _performClose();

  Future<void>? _closeFuture;
  bool _closed = false;

  Future<void> _performClose() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    _closed = true;
    final future = _doClose();
    _closeFuture = future;
    return future;
  }

  Future<void> _doClose() async {
    // Close the memory-backed client (owns its backend).
    await memoryClient.close();
    // Close the encrypted store (opened by Kache → owned lease).
    await encryptedStore.close();
    // Borrowed store must NOT close the box; we own the raw box here, so close
    // it after the borrowed store is done.
    await borrowedBox.close();
  }

  /// Whether [close] has run.
  bool get isClosed => _closed;
}

/// A fixed demo encryption key. In a real app the caller owns the key; Kache
/// never records it. Derived deterministically so the encrypted box is stable
/// across restarts within this demo.
final List<int> _demoEncryptionKey = _deriveDemoKey('kache-example-encryption');

List<int> _deriveDemoKey(String seed) {
  final bytes = utf8.encode(seed);
  final key = Uint8List(32);
  for (var i = 0; i < bytes.length; i++) {
    key[i % 32] ^= bytes[i];
  }
  return key.toList();
}

/// Migrates a legacy schema-0 payload (snake_case GitHub JSON) into the current
/// [repositoryProfileCodec] shape. This is the callback passed to `bind()`.
RepositoryProfile _migrateFromLegacy(Uint8List payload, int fromSchema) {
  // schema 0 stored raw GitHub JSON (snake_case); the current codec stores the
  // camelCase persisted shape. We parse the legacy payload via the GitHub
  // parser and re-encode so subsequent reads use the current schema.
  if (fromSchema == 0) {
    final decoded = jsonDecode(utf8.decode(payload));
    if (decoded is Map<String, Object?>) {
      return RepositoryProfile.fromGitHubJson(decoded);
    }
  }
  // Fallback: attempt current-schema decode.
  return repositoryProfileCodec.decode(payload);
}
