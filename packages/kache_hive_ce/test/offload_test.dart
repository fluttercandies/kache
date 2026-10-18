import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';
import 'package:kache/kache.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';
import 'package:kache_hive_ce/src/envelope.dart';
import 'package:test/test.dart';

/// Isolate in which [_trackingCodec] last ran its callbacks.
///
/// Top-level state is reinitialized in every isolate, so the value observed
/// here is only updated by work that ran on this test's isolate.
Isolate? _lastCodecIsolate;

Uint8List _encodeTracked(String value) {
  _lastCodecIsolate = Isolate.current;
  return utf8.encode(value);
}

String _decodeTracked(Uint8List bytes) {
  _lastCodecIsolate = Isolate.current;
  return utf8.decode(bytes);
}

const HiveCeCodec<String> _trackingCodec = HiveCeCodec<String>(
  encode: _encodeTracked,
  decode: _decodeTracked,
);

String _migrateTracked(Uint8List payload, String fromCodecId) {
  _lastCodecIsolate = Isolate.current;
  return '${utf8.decode(payload)}<-$fromCodecId';
}

void main() {
  setUp(() => _lastCodecIsolate = null);

  test('rejects a negative isolate threshold before opening a box', () {
    expect(
      () => HiveCeKacheStore.open(
        boxName: _boxName('negative'),
        bytes: Uint8List(0),
        isolateThreshold: -1,
      ),
      throwsArgumentError,
    );
  });

  test('defaults to a 64 KiB threshold', () async {
    final store = await _store('default', threshold: 65536);
    final defaulted = await HiveCeKacheStore.open(
      boxName: _boxName('defaulted'),
      bytes: Uint8List(0),
    );
    expect(defaulted.isolateThreshold, store.isolateThreshold);
    await defaulted.close();
    await store.close();
  });

  test('decodes below the threshold within the caller stack', () async {
    final store = await _store('inline-read', threshold: 1 << 20);
    final binding = store.bind<String>(codecId: 'text', codec: _trackingCodec);
    await _write(store, binding, 'small');
    _lastCodecIsolate = null;

    final read = store.read<String>(key: _key, binding: binding);

    expect(_lastCodecIsolate, same(Isolate.current));
    expect((await read)?.entry.data, 'small');
    await store.close();
  });

  test('decodes above the threshold on another isolate', () async {
    final store = await _store('offload-read', threshold: 0);
    final binding = store.bind<String>(codecId: 'text', codec: _trackingCodec);
    await _write(store, binding, 'large');
    _lastCodecIsolate = null;

    final read = await store.read<String>(key: _key, binding: binding);

    expect(read?.entry.data, 'large');
    expect(read?.entry.metadata.fetchedAt, _fetchedAt);
    expect(_lastCodecIsolate, isNull);
    await store.close();
  });

  test('first write without size evidence stays inline', () async {
    final store = await _store('first-write', threshold: 1);
    final binding = store.bind<String>(codecId: 'text', codec: _trackingCodec);

    final write = _write(store, binding, 'first');

    expect(_lastCodecIsolate, same(Isolate.current));
    await write;
    _lastCodecIsolate = null;
    await _write(store, binding, 'second');
    expect(_lastCodecIsolate, isNull);
    await store.close();
  });

  test('encodes above the threshold on another isolate', () async {
    final store = await _store('offload-write', threshold: 0);
    final binding = store.bind<String>(codecId: 'text', codec: _trackingCodec);

    await _write(store, binding, 'second');

    expect(_lastCodecIsolate, isNull);
    final raw = store.box.get(_physicalKey(store.box))! as Uint8List;
    final envelope = HiveCeEnvelope.decode(raw);
    expect(utf8.decode(envelope.payload), 'second');
    expect(envelope.codecId, 'text');
    await store.close();
  });

  test('offloaded migration returns migrated data and rewrites it', () async {
    final store = await _store('offload-migration', threshold: 0);
    await _write(
      store,
      store.bind<String>(codecId: 'text-v1', codec: _trackingCodec),
      'old',
    );
    final current = store.bind<String>(
      codecId: 'text-v2',
      codec: _trackingCodec,
      migrate: _migrateTracked,
    );
    _lastCodecIsolate = null;

    final read = await store.read<String>(key: _key, binding: current);
    await read?.runMaintenance();

    expect(read?.entry.data, 'old<-text-v1');
    expect(_lastCodecIsolate, isNull);
    final rewritten = HiveCeEnvelope.decode(
      store.box.get(_physicalKey(store.box))! as Uint8List,
    );
    expect(rewritten.codecId, 'text-v2');
    expect(utf8.decode(rewritten.payload), 'old<-text-v1');
    await store.close();
  });

  test('offloaded codec failures keep their persistence stage', () async {
    final store = await _store('offload-failures', threshold: 0);
    await _write(
      store,
      store.bind<String>(codecId: 'text', codec: _trackingCodec),
      'value',
    );
    final failingDecode = store.bind<String>(
      codecId: 'text',
      codec: const HiveCeCodec<String>(
        encode: _encodeTracked,
        decode: _throwingDecode,
      ),
    );
    final failingMigrate = store.bind<String>(
      codecId: 'text-v2',
      codec: _trackingCodec,
      migrate: _throwingMigrate,
    );
    final failingEncode = store.bind<String>(
      codecId: 'text',
      codec: const HiveCeCodec<String>(
        encode: _throwingEncode,
        decode: _decodeTracked,
      ),
    );

    await expectLater(
      store.read<String>(key: _key, binding: failingDecode),
      _throwsStage(KachePersistenceStage.decode, isA<FormatException>()),
    );
    await expectLater(
      store.read<String>(key: _key, binding: failingMigrate),
      _throwsStage(KachePersistenceStage.migration, isA<StateError>()),
    );
    await expectLater(
      _write(store, failingEncode, 'next'),
      _throwsStage(KachePersistenceStage.encode, isA<ArgumentError>()),
    );
    final intact = await store.read<String>(
      key: _key,
      binding: store.bind<String>(codecId: 'text', codec: _trackingCodec),
    );
    expect(intact?.entry.data, 'value');
    await store.close();
  });

  test('a codec that cannot leave the isolate falls back inline', () async {
    final store = await _store('unsendable-codec', threshold: 0);
    final port = ReceivePort();
    addTearDown(port.close);
    var decodeCalls = 0;
    final binding = store.bind<String>(
      codecId: 'text',
      codec: HiveCeCodec<String>(
        encode: (value) {
          port.hashCode;
          return utf8.encode(value);
        },
        decode: (bytes) {
          port.hashCode;
          decodeCalls += 1;
          return utf8.decode(bytes);
        },
      ),
    );
    await _write(store, binding, 'first');
    await _write(store, binding, 'second');

    final read = await store.read<String>(key: _key, binding: binding);
    final again = await store.read<String>(key: _key, binding: binding);

    expect(read?.entry.data, 'second');
    expect(again?.entry.data, 'second');
    expect(decodeCalls, 2);
    await store.close();
  });

  test('a result that cannot leave the worker falls back inline', () async {
    final store = await _store('unsendable-result', threshold: 0);
    final binding = store.bind<ReceivePort>(
      codecId: 'port',
      codec: const HiveCeCodec<ReceivePort>(
        encode: _encodePort,
        decode: _decodePort,
      ),
    );
    await store.write<ReceivePort>(
      key: _key,
      binding: binding,
      entry: KachePersistedEntry<ReceivePort>(
        data: ReceivePort(),
        metadata: KachePersistedMetadata(fetchedAt: _fetchedAt),
      ),
    );

    final read = await store.read<ReceivePort>(key: _key, binding: binding);

    expect(read?.entry.data, isA<ReceivePort>());
    read?.entry.data.close();
    await store.close();
  });

  test('offloaded writes keep per-key call order', () async {
    final store = await _store('ordering', threshold: 0);
    final binding = store.bind<String>(codecId: 'text', codec: _trackingCodec);
    await _write(store, binding, 'seed');

    final writes = <Future<void>>[
      for (var index = 0; index < 5; index++)
        _write(store, binding, 'value-$index'),
    ];
    final readAfterWrites = store.read<String>(key: _key, binding: binding);
    await Future.wait(writes);

    expect((await readAfterWrites)?.entry.data, 'value-4');
    await _write(store, binding, 'doomed');
    final pending = _write(store, binding, 'pending');
    final delete = store.delete(key: _key);
    await pending;
    await delete;
    expect(await store.read<String>(key: _key, binding: binding), isNull);
    await store.close();
  });

  test('clear and close wait for offloaded writes', () async {
    final directory = await Directory.systemTemp.createTemp('kache_drain_');
    addTearDown(() => directory.delete(recursive: true));
    final boxName = _boxName('drain');
    final store = await HiveCeKacheStore.open(
      boxName: boxName,
      path: directory.path,
      isolateThreshold: 0,
    );
    final binding = store.bind<String>(codecId: 'text', codec: _trackingCodec);

    final beforeClear = _write(store, binding, 'cleared');
    await store.clear();
    await beforeClear;
    expect(await store.read<String>(key: _key, binding: binding), isNull);

    final beforeClose = _write(store, binding, 'kept');
    await store.close();
    await beforeClose;

    final reopened = await HiveCeKacheStore.open(
      boxName: boxName,
      path: directory.path,
    );
    final read = await reopened.read<String>(
      key: _key,
      binding: reopened.bind<String>(codecId: 'text', codec: _trackingCodec),
    );
    expect(read?.entry.data, 'kept');
    await reopened.close();
  });
}

final KacheKey _key = KacheKey('profile', <Object?>[1]);
final DateTime _fetchedAt = DateTime.utc(2026, 4, 5);

Future<void> _write(
  HiveCeKacheStore store,
  HiveCeBinding<String> binding,
  String value,
) =>
    store.write<String>(
      key: _key,
      binding: binding,
      entry: KachePersistedEntry<String>(
        data: value,
        metadata: KachePersistedMetadata(fetchedAt: _fetchedAt),
      ),
    );

String _throwingDecode(Uint8List bytes) =>
    throw const FormatException('decode failed');

String _throwingMigrate(Uint8List payload, String fromCodecId) =>
    throw StateError('migration failed');

Uint8List _throwingEncode(String value) =>
    throw ArgumentError.value(value, 'value', 'encode failed');

Uint8List _encodePort(ReceivePort port) => Uint8List.fromList(<int>[1]);

ReceivePort _decodePort(Uint8List bytes) => ReceivePort();

Matcher _throwsStage(KachePersistenceStage stage, Matcher cause) => throwsA(
      isA<KachePersistenceException>()
          .having((error) => error.stage, 'stage', stage)
          .having((error) => error.cause, 'cause', cause),
    );

Future<HiveCeKacheStore> _store(String label, {required int threshold}) =>
    HiveCeKacheStore.open(
      boxName: _boxName(label),
      bytes: Uint8List(0),
      isolateThreshold: threshold,
    );

String _boxName(String label) =>
    'kache_offload_${label}_${DateTime.now().microsecondsSinceEpoch}';

String _physicalKey(Box<Object?> box) => box.keys
    .whereType<String>()
    .firstWhere((key) => key.startsWith('kache:3:'));
