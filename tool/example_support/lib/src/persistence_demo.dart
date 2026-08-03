import 'dart:async';
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
    required this.migratedProfile,
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
    Box<Object?>? borrowedBox;
    HiveCeKacheStore? borrowedStore;
    HiveCeKacheStore? encryptedStore;
    MemoryKachePersistence? memoryBackend;
    KacheClient? memoryClient;
    try {
      // 1) HiveCeKacheStore.fromBox + HiveCeBoxOwnership.borrowed.
      //    The caller opens the raw Hive box; Kache wraps it but does NOT close
      //    it (borrowed). This is the pattern for sharing a box across clients.
      final borrowedBoxName = '${boxPrefix}_borrowed';
      borrowedBox = await Hive.openBox<Object?>(
        borrowedBoxName,
        crashRecovery: true,
      );
      borrowedStore = HiveCeKacheStore.fromBox(
        borrowedBox,
        ownership: HiveCeBoxOwnership.borrowed,
      );

      // 2) bind() with a HiveCeMigrator that upgrades an older codec payload.
      //    The migrator runs automatically when the codec identifier changes.
      final migratorBinding = borrowedStore.bind<RepositoryProfile>(
        codecId: 'github-repository-profile-json-v1',
        codec: repositoryProfileCodec,
        migrate: _migrateFromLegacy,
      );
      final legacyBinding = borrowedStore.bind<RepositoryProfile>(
        codecId: 'github-repository-profile-json-v0',
        codec: _legacyRepositoryProfileCodec,
      );

      // 3) An encrypted box opened with a caller-owned HiveCipher. HMAC key
      //    derivation also hides low-entropy logical keys from the box file.
      final cipher = HiveAesCipher(_demoEncryptionKey);
      encryptedStore = await HiveCeKacheStore.open(
        boxName: '${boxPrefix}_encrypted',
        encryptionCipher: cipher,
        keyStrategy: HiveCeKeyStrategy.hmacSha256(_demoPhysicalKeySecret),
      );

      // 4) MemoryKachePersistence: a custom KachePersistenceBackend implemented
      //    entirely in the core SDK (no Hive, no Flutter). Useful for tests and
      //    for callers who want process-local typed persistence without a binary
      //    format. We back a real client with it so the demo query round-trips.
      memoryBackend = MemoryKachePersistence();
      final memoryBinding = memoryBackend.bind<RepositoryProfile>(
        fingerprint: 'example-memory:v1',
      );
      memoryClient = KacheClient(
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
      final migrationKey = KacheKey(
        'persistence-demo-codec-migration',
        <Object?>[memorySnapshot.requireData.fullName],
      );
      await borrowedStore.write<RepositoryProfile>(
        key: migrationKey,
        binding: legacyBinding,
        entry: KachePersistedEntry<RepositoryProfile>(
          data: memorySnapshot.requireData,
          metadata: KachePersistedMetadata(fetchedAt: DateTime.now().toUtc()),
        ),
      );
      final migrationRead = await borrowedStore.read<RepositoryProfile>(
        key: migrationKey,
        binding: migratorBinding,
      );
      if (migrationRead == null) {
        throw StateError('Codec migration did not return the seeded record.');
      }
      await migrationRead.runMaintenance();

      return PersistenceDemo._(
        borrowedStore: borrowedStore,
        borrowedBox: borrowedBox,
        migratorBinding: migratorBinding,
        migratedProfile: migrationRead.entry.data,
        encryptedStore: encryptedStore,
        memoryBackend: memoryBackend,
        memoryClient: memoryClient,
        memoryQuery: memoryQuery,
        memorySnapshot: memorySnapshot,
      );
    } on Object catch (error, stackTrace) {
      try {
        await _closePersistenceResources(<Future<void> Function()>[
          if (memoryClient != null)
            memoryClient.close
          else if (memoryBackend != null)
            memoryBackend.close,
          if (encryptedStore != null) encryptedStore.close,
          if (borrowedStore != null) borrowedStore.close,
          if (borrowedBox != null) borrowedBox.close,
        ]);
      } on Object {
        // The construction failure is the first lifecycle failure and retains
        // precedence after every acquired resource has been offered cleanup.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Store built from [HiveCeKacheStore.fromBox] with borrowed ownership.
  final HiveCeKacheStore borrowedStore;

  /// The raw Hive box that [borrowedStore] wraps; owned by this demo.
  final Box<Object?> borrowedBox;

  /// Binding that carries a [HiveCeMigrator] for codec upgrades.
  final HiveCeBinding<RepositoryProfile> migratorBinding;

  /// Profile read through the old-codec migration and maintenance path.
  final RepositoryProfile migratedProfile;

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
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    _closed = true;
    final completion = Completer<void>();
    final future = completion.future;
    _closeFuture = future;
    unawaited(
      _doClose().then<void>(
        (_) => completion.complete(),
        onError: (Object error, StackTrace stackTrace) {
          completion.completeError(error, stackTrace);
        },
      ),
    );
    return future;
  }

  Future<void>? _closeFuture;
  bool _closed = false;

  Future<void> _doClose() =>
      _closePersistenceResources(<Future<void> Function()>[
        // The client owns and closes the memory backend.
        memoryClient.close,
        // The Kache-managed encrypted store owns its box lease.
        encryptedStore.close,
        // End the borrowed store lifecycle before its owner closes the raw box.
        borrowedStore.close,
        borrowedBox.close,
      ]);

  /// Whether [close] has run.
  bool get isClosed => _closed;
}

/// Fixed, separate demonstration keys. A production app must load independent,
/// cryptographically random encryption and HMAC secrets from secure storage;
/// Kache never records either secret.
final List<int> _demoEncryptionKey = _deriveDemoKey('kache-example-encryption');
final List<int> _demoPhysicalKeySecret = _deriveDemoKey(
  'kache-example-physical-key',
);

List<int> _deriveDemoKey(String seed) {
  final bytes = utf8.encode(seed);
  final key = Uint8List(32);
  for (var i = 0; i < bytes.length; i++) {
    key[i % 32] ^= bytes[i];
  }
  return key.toList();
}

Future<void> _closePersistenceResources(
  List<Future<void> Function()> close,
) async {
  Object? firstError;
  StackTrace? firstStackTrace;
  for (final operation in close) {
    try {
      await operation();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }
  final error = firstError;
  if (error != null) {
    Error.throwWithStackTrace(error, firstStackTrace!);
  }
}

final HiveCeCodec<RepositoryProfile> _legacyRepositoryProfileCodec =
    HiveCeCodec<RepositoryProfile>(
      encode: (profile) => Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'full_name': profile.fullName,
            'description': profile.description,
            'html_url': profile.htmlUrl,
            'owner': <String, Object?>{'avatar_url': profile.ownerAvatarUrl},
            'stargazers_count': profile.stars,
            'forks_count': profile.forks,
            'open_issues_count': profile.openIssues,
            'language': profile.language,
            'updated_at': profile.updatedAt.toUtc().toIso8601String(),
          }),
        ),
      ),
      decode: (payload) =>
          _migrateFromLegacy(payload, 'github-repository-profile-json-v0'),
    );

/// Migrates a payload written under the legacy snake_case JSON codec into the
/// current [repositoryProfileCodec] shape. This is passed to `bind()`.
RepositoryProfile _migrateFromLegacy(Uint8List payload, String fromCodecId) {
  if (fromCodecId != 'github-repository-profile-json-v0') {
    throw FormatException('Unsupported repository codec: $fromCodecId');
  }
  try {
    final decoded = jsonDecode(utf8.decode(payload));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Legacy repository must be an object.');
    }
    return RepositoryProfile.fromGitHubJson(decoded);
  } on FormatException {
    throw const FormatException('Legacy repository payload is invalid.');
  }
}
