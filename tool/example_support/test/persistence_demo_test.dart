import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kache/kache.dart';
import 'package:kache_example_support/kache_example_support.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

void main() {
  setUpAll(() {
    Hive.init(
      Directory.systemTemp.createTempSync('kache_persistence_test').path,
    );
  });

  test('PersistenceDemo builds all four persistence capabilities', () async {
    final demo = await PersistenceDemo.open(
      gateway: _FakeGateway(),
      boxPrefix: 'persistence_demo_capabilities',
    );

    // fromBox + borrowed ownership.
    expect(demo.borrowedStore.boxOwnership, HiveCeBoxOwnership.borrowed);
    expect(demo.borrowedBox.isOpen, isTrue);

    // migrator binding carries a non-null migrate callback and schema 1.
    expect(demo.migratorBinding.schema, 1);
    expect(demo.migratorBinding.migrate, isNotNull);

    // encrypted store is a real HiveCeKacheStore.
    expect(demo.encryptedStore, isA<HiveCeKacheStore>());

    // MemoryKachePersistence backs a real client + query.
    expect(demo.memoryBackend, isA<MemoryKachePersistence>());
    expect(demo.memoryClient.isClosed, isFalse);
    final memoryRead = await demo.memoryBackend.read<RepositoryProfile>(
      key: demo.memoryQuery.key,
      binding: demo.memoryQuery.binding!,
    );
    expect(memoryRead?.entry.data.fullName, 'flutter/flutter');

    await demo.close();
    expect(demo.isClosed, isTrue);
    expect(demo.memoryClient.isClosed, isTrue);
  });

  test(
    'memory-backed query round-trips through MemoryKachePersistence',
    () async {
      final demo = await PersistenceDemo.open(
        gateway: _FakeGateway(),
        boxPrefix: 'persistence_demo_roundtrip',
      );
      addTearDown(demo.close);

      final snapshot = await demo.memoryClient.prefetch(demo.memoryQuery);
      expect(snapshot.hasData, isTrue);
      expect(snapshot.requireData.fullName, 'flutter/flutter');

      // The memory backend retains the value for the same key.
      final read = await demo.memoryBackend.read<RepositoryProfile>(
        key: demo.memoryQuery.key,
        binding: demo.memoryQuery.binding!,
      );
      expect(read?.entry.data.fullName, 'flutter/flutter');
    },
  );
}

final class _FakeGateway implements RepositoryGateway {
  @override
  Future<RepositoryProfile> fetch(KacheFetchContext context) async =>
      RepositoryProfile(
        fullName: 'flutter/flutter',
        description: 'Flutter makes it easy to build beautiful apps.',
        htmlUrl: 'https://github.com/flutter/flutter',
        ownerAvatarUrl: 'https://avatars.example/flutter.png',
        stars: 170000,
        forks: 29000,
        openIssues: 12000,
        language: 'Dart',
        updatedAt: DateTime.utc(2026, 7, 14, 8, 30),
      );
}
