import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';
import 'package:kache/kache.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';
import 'package:kache_hive_ce/src/envelope.dart';
import 'package:test/test.dart';

void main() {
  test(
    'returns migrated data before lazily rewriting current schema',
    () async {
      final store = await _memoryStore('migration-success');
      final key = KacheKey('profile');
      final oldBinding = _textBinding(store, schema: 1);
      await store.write<String>(
        key: key,
        binding: oldBinding,
        entry: KachePersistedEntry<String>(
          data: 'Ada',
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      );
      final current = _textBinding(
        store,
        schema: 2,
        migrate: (payload, fromSchema) =>
            '${utf8.decode(payload)}-migrated-from-$fromSchema',
      );

      final read = await store.read<String>(key: key, binding: current);

      expect(read?.entry.data, 'Ada-migrated-from-1');
      expect(read?.hasMaintenance, isTrue);
      expect(
        HiveCeEnvelope.decode(
          store.box.get(_physicalKeyOf(store.box))! as Uint8List,
        ).schema,
        1,
      );

      await read?.runMaintenance();
      final rewritten = HiveCeEnvelope.decode(
        store.box.get(_physicalKeyOf(store.box))! as Uint8List,
      );
      expect(rewritten.schema, 2);
      expect(utf8.decode(rewritten.payload), 'Ada-migrated-from-1');
      await store.close();
    },
  );

  test('classifies migration callback failures', () async {
    final store = await _memoryStore('migration-failure');
    final key = KacheKey('profile');
    await store.write<String>(
      key: key,
      binding: _textBinding(store, schema: 1),
      entry: KachePersistedEntry<String>(
        data: 'Ada',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );
    final current = _textBinding(
      store,
      schema: 2,
      migrate: (_, __) => throw StateError('migration failed'),
    );

    await expectLater(
      store.read<String>(key: key, binding: current),
      throwsA(
        isA<KachePersistenceException>().having(
          (error) => error.stage,
          'stage',
          KachePersistenceStage.migration,
        ),
      ),
    );
    await store.close();
  });

  test('lazy migration never overwrites a newer record', () async {
    final store = await _memoryStore('migration-race');
    final key = KacheKey('profile');
    await store.write<String>(
      key: key,
      binding: _textBinding(store, schema: 1),
      entry: KachePersistedEntry<String>(
        data: 'old',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );
    final current = _textBinding(
      store,
      schema: 2,
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

  test('rejects newer schema without attempting current decode', () async {
    final store = await _memoryStore('future-schema');
    final key = KacheKey('profile');
    await store.write<String>(
      key: key,
      binding: _textBinding(store, schema: 3),
      entry: KachePersistedEntry<String>(
        data: 'future',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );

    await expectLater(
      store.read<String>(key: key, binding: _textBinding(store, schema: 2)),
      throwsA(
        isA<KachePersistenceException>().having(
          (error) => error.stage,
          'stage',
          KachePersistenceStage.migration,
        ),
      ),
    );
    await store.close();
  });

  test('classifies codec mismatch as backend incompatibility', () async {
    final store = await _memoryStore('codec-mismatch');
    final key = KacheKey('profile');
    await store.write<String>(
      key: key,
      binding: _textBinding(store, schema: 1),
      entry: KachePersistedEntry<String>(
        data: 'Ada',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );
    final other = store.bind<String>(
      codecId: 'other-text',
      schema: 1,
      codec: _textCodec,
    );

    await expectLater(
      store.read<String>(key: key, binding: other),
      throwsA(
        isA<KachePersistenceException>().having(
          (error) => error.stage,
          'stage',
          KachePersistenceStage.backend,
        ),
      ),
    );
    await store.close();
  });

  test('classifies encode and decode callback failures', () async {
    final store = await _memoryStore('codec-failures');
    final key = KacheKey('profile');
    final encodeFailure = store.bind<String>(
      codecId: 'encode-failure',
      schema: 1,
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

    final valid = _textBinding(store, schema: 1);
    await store.write<String>(
      key: key,
      binding: valid,
      entry: KachePersistedEntry<String>(
        data: 'Ada',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );
    final decodeFailure = store.bind<String>(
      codecId: 'text',
      schema: 1,
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
    final oldBinding = _textBinding(store, schema: 1);
    final currentBinding = _textBinding(store, schema: 2);
    await store.write<String>(
      key: key,
      binding: oldBinding,
      entry: KachePersistedEntry<String>(
        data: 'old',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );

    Future<void>? newerWrite;
    var injected = false;
    final reentrantBinding = store.bind<String>(
      codecId: 'text',
      schema: 2,
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

  test(
    'combined schema and key migration never overwrites a newer record',
    () async {
      final store = await _memoryStore('combined-migration-race');
      final key = KacheKey('profile');
      final legacyRecord = HiveCeEnvelope.encode(
        fetchedAt: DateTime.utc(2026),
        isInvalidated: false,
        schema: 1,
        codecId: 'text',
        payload: Uint8List.fromList(utf8.encode('old')),
      );
      await store.box.put(key.storageKey, legacyRecord);

      final current = _textBinding(
        store,
        schema: 2,
        migrate: (payload, _) => '${utf8.decode(payload)}-migrated',
      );
      final staleRead = await store.read<String>(key: key, binding: current);
      expect(staleRead?.entry.data, 'old-migrated');

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
      expect(store.box.get(key.storageKey), isNull);
      await store.close();
    },
  );
}

final HiveCeCodec<String> _textCodec = HiveCeCodec<String>(
  encode: (value) => Uint8List.fromList(utf8.encode(value)),
  decode: utf8.decode,
);

HiveCeBinding<String> _textBinding(
  HiveCeKacheStore store, {
  required int schema,
  HiveCeMigrator<String>? migrate,
}) =>
    store.bind<String>(
      codecId: 'text',
      schema: schema,
      codec: _textCodec,
      migrate: migrate,
    );

Future<HiveCeKacheStore> _memoryStore(String label) => HiveCeKacheStore.open(
      boxName: 'kache_${label}_${DateTime.now().microsecondsSinceEpoch}',
      bytes: Uint8List(0),
    );

String _physicalKeyOf(Box<Object?> box) =>
    box.keys.whereType<String>().firstWhere((k) => k.startsWith('kache:2:'));
