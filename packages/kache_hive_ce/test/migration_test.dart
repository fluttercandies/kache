import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';
import 'package:kache/kache.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';
import 'package:kache_hive_ce/src/envelope.dart';
import 'package:test/test.dart';

void main() {
  test('returns migrated data before lazily rewriting its codec', () async {
    final store = await _memoryStore('migration-success');
    final key = KacheKey('profile');
    await store.write<String>(
      key: key,
      binding: _textBinding(store, 'text-v1'),
      entry: KachePersistedEntry<String>(
        data: 'Ada',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );
    final current = _textBinding(
      store,
      'text-v2',
      migrate: (payload, fromCodecId) =>
          '${utf8.decode(payload)}-migrated-from-$fromCodecId',
    );

    final read = await store.read<String>(key: key, binding: current);

    expect(read?.entry.data, 'Ada-migrated-from-text-v1');
    expect(read?.hasMaintenance, isTrue);
    expect(
      HiveCeEnvelope.decode(
        store.box.get(_physicalKeyOf(store.box))! as Uint8List,
      ).codecId,
      'text-v1',
    );

    await read?.runMaintenance();
    final rewritten = HiveCeEnvelope.decode(
      store.box.get(_physicalKeyOf(store.box))! as Uint8List,
    );
    expect(rewritten.codecId, 'text-v2');
    expect(utf8.decode(rewritten.payload), 'Ada-migrated-from-text-v1');
    await store.close();
  });

  test('classifies missing and failed migrators', () async {
    final store = await _memoryStore('migration-failure');
    final key = KacheKey('profile');
    await store.write<String>(
      key: key,
      binding: _textBinding(store, 'text-v1'),
      entry: KachePersistedEntry<String>(
        data: 'Ada',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );

    for (final binding in <HiveCeBinding<String>>[
      _textBinding(store, 'text-v2'),
      _textBinding(
        store,
        'text-v3',
        migrate: (_, __) => throw StateError('migration failed'),
      ),
    ]) {
      await expectLater(
        store.read<String>(key: key, binding: binding),
        throwsA(
          isA<KachePersistenceException>().having(
            (error) => error.stage,
            'stage',
            KachePersistenceStage.migration,
          ),
        ),
      );
    }
    await store.close();
  });

  test('lazy migration never overwrites a newer record', () async {
    final store = await _memoryStore('migration-race');
    final key = KacheKey('profile');
    await store.write<String>(
      key: key,
      binding: _textBinding(store, 'text-v1'),
      entry: KachePersistedEntry<String>(
        data: 'old',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );
    final current = _textBinding(
      store,
      'text-v2',
      migrate: (payload, _) => '${utf8.decode(payload)}-migrated',
    );
    final staleRead = await store.read<String>(key: key, binding: current);
    await store.write<String>(
      key: key,
      binding: current,
      entry: KachePersistedEntry<String>(
        data: 'new',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026, 2)),
      ),
    );

    await staleRead?.runMaintenance();
    final latest = await store.read<String>(key: key, binding: current);

    expect(latest?.entry.data, 'new');
    await store.close();
  });

  test('classifies encode and current-codec decode failures', () async {
    final store = await _memoryStore('codec-failures');
    final key = KacheKey('profile');
    final encodeFailure = store.bind<String>(
      codecId: 'encode-failure-v1',
      codec: HiveCeCodec<String>(
        encode: (_) => throw StateError('encode failed'),
        decode: utf8.decode,
      ),
    );

    await expectLater(
      store.write<String>(
        key: key,
        binding: encodeFailure,
        entry: KachePersistedEntry<String>(
          data: 'Ada',
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      ),
      throwsA(
        isA<KachePersistenceException>().having(
          (error) => error.stage,
          'stage',
          KachePersistenceStage.encode,
        ),
      ),
    );

    final valid = _textBinding(store, 'text-v1');
    await store.write<String>(
      key: key,
      binding: valid,
      entry: KachePersistedEntry<String>(
        data: 'Ada',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );
    final decodeFailure = store.bind<String>(
      codecId: 'text-v1',
      codec: HiveCeCodec<String>(
        encode: _textCodec.encode,
        decode: (_) => throw StateError('decode failed'),
      ),
    );
    await expectLater(
      store.read<String>(key: key, binding: decodeFailure),
      throwsA(
        isA<KachePersistenceException>().having(
          (error) => error.stage,
          'stage',
          KachePersistenceStage.decode,
        ),
      ),
    );
    await store.close();
  });

  test('migration encode reentrancy cannot overwrite a newer write', () async {
    final store = await _memoryStore('migration-encode-reentrancy');
    final key = KacheKey('profile');
    final currentBinding = _textBinding(store, 'text-v2');
    await store.write<String>(
      key: key,
      binding: _textBinding(store, 'text-v1'),
      entry: KachePersistedEntry<String>(
        data: 'old',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );

    Future<void>? newerWrite;
    var injected = false;
    final reentrantBinding = store.bind<String>(
      codecId: 'text-v2',
      codec: HiveCeCodec<String>(
        encode: (value) {
          if (!injected) {
            injected = true;
            newerWrite = store.write<String>(
              key: key,
              binding: currentBinding,
              entry: KachePersistedEntry<String>(
                data: 'new',
                metadata: KachePersistedMetadata(
                  fetchedAt: DateTime.utc(2026, 2),
                ),
              ),
            );
          }
          return Uint8List.fromList(utf8.encode(value));
        },
        decode: utf8.decode,
      ),
      migrate: (payload, _) => '${utf8.decode(payload)}-migrated',
    );
    final staleRead = await store.read<String>(
      key: key,
      binding: reentrantBinding,
    );

    await staleRead?.runMaintenance();
    await newerWrite;
    final latest = await store.read<String>(
      key: key,
      binding: currentBinding,
    );

    expect(injected, isTrue);
    expect(latest?.entry.data, 'new');
    await store.close();
  });

  test('migration maintenance cannot mutate a borrowed box after close',
      () async {
    final box = await Hive.openBox<Object?>(
      'kache_migration_close_${DateTime.now().microsecondsSinceEpoch}',
      bytes: Uint8List(0),
    );
    final store = HiveCeKacheStore.fromBox(box);
    final key = KacheKey('profile');
    await store.write<String>(
      key: key,
      binding: _textBinding(store, 'text-v1'),
      entry: KachePersistedEntry<String>(
        data: 'old',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );
    final physicalKey = _physicalKeyOf(box);
    final oldRecord = Uint8List.fromList(box.get(physicalKey)! as Uint8List);
    final read = await store.read<String>(
      key: key,
      binding: _textBinding(
        store,
        'text-v2',
        migrate: (payload, _) => '${utf8.decode(payload)}-migrated',
      ),
    );

    await store.close();
    expect(box.isOpen, isTrue);
    await expectLater(
      read?.runMaintenance(),
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
              KachePersistenceStage.migration,
            ),
      ),
    );
    expect(box.get(physicalKey), orderedEquals(oldRecord));
    await box.close();
  });
}

final HiveCeCodec<String> _textCodec = HiveCeCodec<String>(
  encode: (value) => Uint8List.fromList(utf8.encode(value)),
  decode: utf8.decode,
);

HiveCeBinding<String> _textBinding(
  HiveCeKacheStore store,
  String codecId, {
  HiveCeMigrator<String>? migrate,
}) =>
    store.bind<String>(
      codecId: codecId,
      codec: _textCodec,
      migrate: migrate,
    );

Future<HiveCeKacheStore> _memoryStore(String label) => HiveCeKacheStore.open(
      boxName: 'kache_${label}_${DateTime.now().microsecondsSinceEpoch}',
      bytes: Uint8List(0),
    );

String _physicalKeyOf(Box<Object?> box) => box.keys
    .whereType<String>()
    .firstWhere((key) => key.startsWith('kache:3:'));
