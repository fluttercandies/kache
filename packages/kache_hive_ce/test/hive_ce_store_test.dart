import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';
import 'package:kache/kache.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';
import 'package:test/test.dart';

void main() {
  test('persists typed data across a real box restart', () async {
    final directory = await Directory.systemTemp.createTemp('kache_hive_');
    addTearDown(() => directory.delete(recursive: true));
    final boxName = _boxName('restart');
    final key = KacheKey('profile', [1]);

    final first = await HiveCeKacheStore.open(
      boxName: boxName,
      path: directory.path,
    );
    final firstBinding = _stringBinding(first);
    await first.write<String>(
      key: key,
      binding: firstBinding,
      entry: KachePersistedEntry<String>(
        data: 'Ada',
        metadata: KachePersistedMetadata(
          fetchedAt: DateTime.utc(2026, 2, 3),
          isInvalidated: true,
        ),
      ),
    );
    expect(first.box.get(key.storageKey), isA<Uint8List>());
    await first.close();

    final second = await HiveCeKacheStore.open(
      boxName: boxName,
      path: directory.path,
    );
    final read = await second.read<String>(
      key: key,
      binding: _stringBinding(second),
    );

    expect(read?.entry.data, 'Ada');
    expect(read?.entry.metadata.isInvalidated, isTrue);
    await second.close();
  });

  test('shared open leases close the box after the final store', () async {
    final first = await HiveCeKacheStore.open(
      boxName: _boxName('shared'),
      bytes: Uint8List(0),
    );
    final second = await HiveCeKacheStore.open(boxName: first.box.name);

    await first.close();
    expect(second.box.isOpen, isTrue);

    await second.close();
    expect(second.box.isOpen, isFalse);
  });

  test('an externally opened box is borrowed by open factory', () async {
    final boxName = _boxName('borrowed-open');
    final box = await Hive.openBox<Object?>(boxName, bytes: Uint8List(0));
    final store = await HiveCeKacheStore.open(boxName: boxName);

    await store.close();

    expect(box.isOpen, isTrue);
    await box.close();
  });

  test('fromBox ownership controls whether close releases the box', () async {
    final borrowedBox = await Hive.openBox<Object?>(
      _boxName('borrowed-box'),
      bytes: Uint8List(0),
    );
    final borrowed = HiveCeKacheStore.fromBox(borrowedBox);
    await borrowed.close();
    expect(borrowedBox.isOpen, isTrue);
    await borrowedBox.close();

    final ownedBox = await Hive.openBox<Object?>(
      _boxName('owned-box'),
      bytes: Uint8List(0),
    );
    final owned = HiveCeKacheStore.fromBox(
      ownedBox,
      ownership: HiveCeBoxOwnership.owned,
    );
    await owned.close();
    expect(ownedBox.isOpen, isFalse);
  });

  test('supports a Hive encrypted box without owning key material', () async {
    final directory = await Directory.systemTemp.createTemp('kache_cipher_');
    addTearDown(() => directory.delete(recursive: true));
    final boxName = _boxName('encrypted');
    final cipher = HiveAesCipher(List<int>.generate(32, (index) => index));
    final first = await HiveCeKacheStore.open(
      boxName: boxName,
      path: directory.path,
      encryptionCipher: cipher,
    );
    final key = KacheKey('encrypted');
    await first.write<String>(
      key: key,
      binding: _stringBinding(first),
      entry: KachePersistedEntry<String>(
        data: 'secret-data',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );
    await first.close();

    final second = await HiveCeKacheStore.open(
      boxName: boxName,
      path: directory.path,
      encryptionCipher: cipher,
    );
    final read = await second.read<String>(
      key: key,
      binding: _stringBinding(second),
    );

    expect(read?.entry.data, 'secret-data');
    await second.close();
  });

  test('classifies a non-byte box value as decode corruption', () async {
    final box = await Hive.openBox<Object?>(
      _boxName('corrupt-value'),
      bytes: Uint8List(0),
    );
    final store = HiveCeKacheStore.fromBox(
      box,
      ownership: HiveCeBoxOwnership.owned,
    );
    final key = KacheKey('corrupt');
    await box.put(key.storageKey, 'not-bytes');

    await expectLater(
      store.read<String>(key: key, binding: _stringBinding(store)),
      throwsA(
        isA<KachePersistenceException>()
            .having(
              (error) => error.operation,
              'operation',
              KachePersistenceOperation.read,
            )
            .having(
              (error) => error.stage,
              'stage',
              KachePersistenceStage.decode,
            ),
      ),
    );
    await store.close();
  });

  test('post-close operations fail before binding validation', () async {
    final first = await HiveCeKacheStore.open(
      boxName: _boxName('closed-first'),
      bytes: Uint8List(0),
    );
    final second = await HiveCeKacheStore.open(
      boxName: _boxName('closed-second'),
      bytes: Uint8List(0),
    );
    final foreign = _stringBinding(second);
    await first.close();

    await expectLater(
      first.read<String>(key: KacheKey('closed'), binding: foreign),
      throwsA(isA<KachePersistenceException>()),
    );
    await second.close();
  });
}

HiveCeBinding<String> _stringBinding(HiveCeKacheStore store) => store.bind(
  codecId: 'utf8-string',
  schema: 1,
  codec: HiveCeCodec<String>(
    encode: (value) => Uint8List.fromList(utf8.encode(value)),
    decode: (bytes) => utf8.decode(bytes),
  ),
);

String _boxName(String label) =>
    'kache_${label}_${DateTime.now().microsecondsSinceEpoch}';
