import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:kache/kache.dart';
import 'package:kache_contract_tests/persistence_contract.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

void main() {
  runPersistenceContract(
    backendName: 'MemoryKachePersistence',
    createHarness: _MemoryPersistenceHarness.new,
  );
  runPersistenceContract(
    backendName: 'HiveCeKacheStore',
    createHarness: _HiveCePersistenceHarness.create,
  );
}

final class _MemoryPersistenceHarness implements PersistenceContractHarness {
  @override
  final MemoryKachePersistence backend = MemoryKachePersistence();

  @override
  KachePersistenceBinding<T> bind<T>({required String fingerprint}) =>
      backend.bind<T>(fingerprint: fingerprint);

  @override
  FutureOr<void> dispose() => backend.close();
}

final class _HiveCePersistenceHarness implements PersistenceContractHarness {
  _HiveCePersistenceHarness._(this.backend);

  static int _nextBox = 0;

  static Future<_HiveCePersistenceHarness> create() async {
    final store = await HiveCeKacheStore.open(
      boxName: 'kache_contract_${_nextBox++}',
      bytes: Uint8List(0),
    );
    return _HiveCePersistenceHarness._(store);
  }

  @override
  final HiveCeKacheStore backend;

  @override
  KachePersistenceBinding<T> bind<T>({required String fingerprint}) =>
      backend.bind<T>(
        codecId: fingerprint,
        schema: 1,
        codec: _contractCodec<T>(fingerprint),
      );

  @override
  FutureOr<void> dispose() => backend.close();
}

HiveCeCodec<T> _contractCodec<T>(String fingerprint) => HiveCeCodec<T>(
  encode: (value) {
    final Object? object = value;
    if (object == null) {
      return Uint8List.fromList(<int>[0]);
    }
    if (object is PersistenceContractValue) {
      return Uint8List.fromList(utf8.encode(object.value));
    }
    if (object is int) {
      return Uint8List.fromList(utf8.encode(object.toString()));
    }
    if (object is String) {
      final marker = fingerprint.contains('nullable') ? <int>[1] : <int>[];
      return Uint8List.fromList(<int>[...marker, ...utf8.encode(object)]);
    }
    throw StateError('Unsupported persistence contract value type.');
  },
  decode: (bytes) {
    Object? value;
    if (T == PersistenceContractValue) {
      value = PersistenceContractValue(utf8.decode(bytes));
    } else if (T == int) {
      value = int.parse(utf8.decode(bytes));
    } else if (fingerprint.contains('nullable')) {
      value = bytes.singleOrNull == 0 ? null : utf8.decode(bytes.sublist(1));
    } else {
      value = utf8.decode(bytes);
    }
    return value as T;
  },
);
