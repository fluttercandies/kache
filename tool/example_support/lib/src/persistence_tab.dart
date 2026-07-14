import 'package:flutter/material.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

import 'persistence_demo.dart';
import 'persistence_playground.dart';
import 'playground_components.dart';
import 'runtime.dart';

/// Adapter-agnostic host for the persistence playground tab.
///
/// It lazily builds the [PersistenceDemo] from the host [runtime] and renders
/// one capability card per demonstrated persistence API surface. Because the
/// persistence layer is identical across all four adapters, every example app
/// shares this widget.
class PersistencePlaygroundHost extends StatefulWidget {
  /// Creates the persistence tab host.
  const PersistencePlaygroundHost({
    required this.runtime,
    required this.boxPrefix,
    super.key,
  });

  /// Runtime whose persistence demo is loaded.
  final ExampleRuntime runtime;

  /// Box-name prefix namespacing the demo Hive boxes.
  final String boxPrefix;

  @override
  State<PersistencePlaygroundHost> createState() =>
      _PersistencePlaygroundHostState();
}

final class _PersistencePlaygroundHostState
    extends State<PersistencePlaygroundHost> {
  late Future<PersistenceDemo> _demo;

  @override
  void initState() {
    super.initState();
    _demo = widget.runtime.persistenceDemo(boxPrefix: widget.boxPrefix);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PersistenceDemo>(
    future: _demo,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _PersistenceError(error: snapshot.error!);
      }
      final demo = snapshot.data;
      if (demo == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return PersistencePlayground(capabilities: _capabilities(demo));
    },
  );

  List<PersistenceCapabilityModel> _capabilities(PersistenceDemo demo) {
    return <PersistenceCapabilityModel>[
      PersistenceCapabilityModel(
        title: 'fromBox + borrowed ownership',
        description:
            'Open a raw Hive box yourself, then wrap it. Kache does NOT close a '
            'borrowed box; you own its lifecycle.',
        api: 'HiveCeKacheStore.fromBox(box, ownership: borrowed)',
        status: demo.borrowedStore.boxOwnership == HiveCeBoxOwnership.borrowed
            ? 'borrowed'
            : 'owned',
        detail: 'box=${demo.borrowedBox.name}',
      ),
      PersistenceCapabilityModel(
        title: 'Schema migration (HiveCeMigrator)',
        description:
            'bind() accepts a migrate callback that upgrades legacy payloads '
            'automatically when an older record is read.',
        api: 'store.bind(codecId, schema: 1, codec, migrate: ...)',
        status: 'schema=${demo.migratorBinding.schema}',
        detail: 'codecId=${demo.migratorBinding.codecId}',
      ),
      PersistenceCapabilityModel(
        title: 'Encrypted box',
        description:
            'Open a box with a HiveCipher. Kache never holds or logs the key; '
            'the cipher is owned by the caller.',
        api: 'HiveCeKacheStore.open(boxName, encryptionCipher: cipher)',
        status: 'encrypted',
        detail: 'fingerprint=${demo.encryptedStore.box.name}',
      ),
      PersistenceCapabilityModel(
        title: 'MemoryKachePersistence (custom backend)',
        description:
            'The SDK-only in-memory backend implements the persistence contract '
            'without Hive or Flutter. Backs a real client here so data round-trips.',
        api: 'MemoryKachePersistence() → backend.bind(fingerprint)',
        status: demo.isClosed
            ? 'closed'
            : demo.memorySnapshot.hasData
            ? 'round-trip ready'
            : 'round-trip failed',
        detail: demo.memorySnapshot.hasData
            ? '${demo.memorySnapshot.requireData.fullName} · owned client'
            : 'failure=${playgroundFailureKindLabel(demo.memorySnapshot.failure?.kind)}',
      ),
    ];
  }
}

final class _PersistenceError extends StatelessWidget {
  const _PersistenceError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.storage_rounded, size: 48),
          const SizedBox(height: 18),
          Text(
            'Persistence demo unavailable',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}
