import 'dart:convert';
import 'dart:typed_data';

import 'package:kache_hive_ce/src/adapter_envelope.dart';
import 'package:kache_hive_ce/src/envelope.dart';
import 'package:test/test.dart';

void main() {
  test('v2 envelope matches the fixed golden bytes', () {
    final encoded = HiveCeEnvelope.encode(
      fetchedAt: DateTime.fromMicrosecondsSinceEpoch(1, isUtc: true),
      isInvalidated: true,
      codecId: 'json',
      payload: Uint8List.fromList(utf8.encode('{}')),
    );

    expect(
      _hex(encoded),
      '4b4348320100000000000000010004000000026a736f6e7b7d',
    );
  });

  test('decodes every v2 field and owns payload bytes', () {
    final bytes = HiveCeEnvelope.encode(
      fetchedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      isInvalidated: false,
      codecId: 'profile-json',
      payload: Uint8List.fromList(<int>[1, 2, 3]),
    );

    final decoded = HiveCeEnvelope.decode(bytes);
    bytes[bytes.length - 1] = 9;

    expect(decoded.fetchedAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
    expect(decoded.isInvalidated, isFalse);
    expect(decoded.codecId, 'profile-json');
    expect(decoded.payload, orderedEquals(<int>[1, 2, 3]));
  });

  test('round-trips negative microseconds without Int64 accessors', () {
    final fetchedAt = DateTime.fromMicrosecondsSinceEpoch(-1, isUtc: true);

    final decoded = HiveCeEnvelope.decode(
      HiveCeEnvelope.encode(
        fetchedAt: fetchedAt,
        isInvalidated: false,
        codecId: 'text',
        payload: Uint8List(0),
      ),
    );

    expect(decoded.fetchedAt, fetchedAt);
  });

  test('rejects truncation, unknown flags, bad magic, and trailing bytes', () {
    final valid = HiveCeEnvelope.encode(
      fetchedAt: DateTime.utc(2026),
      isInvalidated: false,
      codecId: 'text',
      payload: Uint8List.fromList(<int>[1]),
    );
    final corruptions = <Uint8List>[
      Uint8List.sublistView(valid, 0, valid.length - 1),
      Uint8List.fromList(valid)..[4] = 0x80,
      Uint8List.fromList(valid)..[0] = 0,
      Uint8List.fromList(<int>[...valid, 0]),
    ];

    for (final corrupted in corruptions) {
      expect(
        () => HiveCeEnvelope.decode(corrupted),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('validates codec identifiers before encoding', () {
    expect(
      () => HiveCeEnvelope.encode(
        fetchedAt: DateTime.utc(2026),
        isInvalidated: false,
        codecId: '',
        payload: Uint8List(0),
      ),
      throwsArgumentError,
    );
  });

  test('accepts the full Hive CE external adapter type id range', () {
    for (final typeId in <int>[0, 223, 224, 65439]) {
      final encoded = HiveCeAdapterEnvelope.encode(
        fetchedAt: DateTime.utc(2026),
        isInvalidated: false,
        typeId: typeId,
        data: null,
      );

      expect(HiveCeAdapterEnvelope.decode(encoded).typeId, typeId);
    }
  });

  test('rejects adapter type ids outside the Hive CE external range', () {
    for (final typeId in <int>[-1, 65440]) {
      expect(
        () => HiveCeAdapterEnvelope.encode(
          fetchedAt: DateTime.utc(2026),
          isInvalidated: false,
          typeId: typeId,
          data: null,
        ),
        throwsArgumentError,
      );
      expect(
        () => HiveCeAdapterEnvelope.decode(<Object?>[
          'KCH-A1',
          1,
          typeId,
          0,
          false,
          null,
        ]),
        throwsArgumentError,
      );
    }
  });
}

String _hex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
