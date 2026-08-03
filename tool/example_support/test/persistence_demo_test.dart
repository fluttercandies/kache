import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    final encryptedKey = KacheKey('encrypted-profile', <Object?>['account']);
    final encryptedBinding = demo.encryptedStore.bind<String>(
      codecId: 'test-string',
      schema: 1,
      codec: HiveCeCodec<String>(encode: utf8.encode, decode: utf8.decode),
    );
    await demo.encryptedStore.write<String>(
      key: encryptedKey,
      binding: encryptedBinding,
      entry: KachePersistedEntry<String>(
        data: 'encrypted-value',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );
    final physicalKey = demo.encryptedStore.box.keys.single as String;
    expect(physicalKey, startsWith('kache:2:h:'));
    expect(physicalKey, isNot(encryptedKey.storageKey));

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
    expect(demo.borrowedBox.isOpen, isFalse);
    expect(demo.encryptedStore.box.isOpen, isFalse);
    await expectLater(
      demo.memoryBackend.read<RepositoryProfile>(
        key: demo.memoryQuery.key,
        binding: demo.memoryQuery.binding!,
      ),
      throwsA(isA<KachePersistenceException>()),
    );
    await expectLater(
      demo.borrowedStore.read<RepositoryProfile>(
        key: KacheKey('closed-borrowed'),
        binding: demo.migratorBinding,
      ),
      throwsA(isA<KachePersistenceException>()),
    );
    await demo.close();
  });

  test('PersistenceDemo close is idempotent during client events', () async {
    final demo = await PersistenceDemo.open(
      gateway: _FakeGateway(),
      boxPrefix: 'persistence_demo_reentrant_close',
    );
    Future<void>? reentrant;
    final subscription = demo.memoryClient.events.listen((event) {
      if (reentrant == null &&
          event.kind == KacheEventKind.close &&
          event.phase == KacheEventPhase.started) {
        reentrant = demo.close();
      }
    });

    final first = demo.close();

    expect(reentrant, same(first));
    await first;
    await subscription.cancel();
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

  test(
    'PersistenceDemo cleans acquired resources when construction fails',
    () async {
      const prefix = 'persistence_demo_open_failure';
      final conflictingBox = await Hive.openBox<int>('${prefix}_encrypted');
      addTearDown(conflictingBox.close);

      await expectLater(
        PersistenceDemo.open(gateway: _FakeGateway(), boxPrefix: prefix),
        throwsA(isA<HiveCeOpenException>()),
      );

      expect(Hive.isBoxOpen('${prefix}_borrowed'), isFalse);
      expect(conflictingBox.isOpen, isTrue);
    },
  );

  test(
    'persistence JSON failures never retain untrusted payload sources',
    () async {
      const marker = 'private-persisted-marker';
      for (final payload in <Uint8List>[
        Uint8List.fromList(utf8.encode('{"token":"$marker",')),
        Uint8List.fromList(const <int>[0xff, 0xfe, 0xfd]),
      ]) {
        try {
          repositoryProfileCodec.decode(payload);
          fail('Expected malformed persistence payload to fail.');
        } on FormatException catch (error) {
          expect(error.source, isNull);
          expect(error.toString(), isNot(contains(marker)));
        }
      }

      final demo = await PersistenceDemo.open(
        gateway: _FakeGateway(),
        boxPrefix: 'persistence_demo_legacy_sanitization',
      );
      addTearDown(demo.close);
      try {
        demo.migratorBinding.migrate!(
          Uint8List.fromList(utf8.encode('{"token":"$marker",')),
          0,
        );
        fail('Expected malformed legacy payload to fail.');
      } on FormatException catch (error) {
        expect(error.source, isNull);
        expect(error.toString(), isNot(contains(marker)));
      }
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
