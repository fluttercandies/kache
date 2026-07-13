import 'dart:convert';
import 'dart:typed_data';

const _headerLength = 23;
const _invalidatedFlag = 0x01;
const _knownFlags = _invalidatedFlag;
const _maximumUint16 = 0xffff;
const _maximumUint32 = 0xffffffff;
const _maximumSafeInteger = 9007199254740991;
const _minimumSafeInteger = -_maximumSafeInteger;
const _twoTo32 = 4294967296;
const _magic = <int>[0x4b, 0x43, 0x48, 0x31];

/// The decoded physical Hive CE record envelope.
final class HiveCeEnvelope {
  const HiveCeEnvelope._({
    required this.fetchedAt,
    required this.isInvalidated,
    required this.schema,
    required this.codecId,
    required this.payload,
  });

  /// UTC instant stored with the value.
  final DateTime fetchedAt;

  /// Whether the cache value was explicitly invalidated.
  final bool isInvalidated;

  /// Backend-owned model schema.
  final int schema;

  /// Stable codec identifier.
  final String codecId;

  /// Owned encoded model bytes.
  final Uint8List payload;

  /// Encodes the fixed `KCH1` record format.
  static Uint8List encode({
    required DateTime fetchedAt,
    required bool isInvalidated,
    required int schema,
    required String codecId,
    required Uint8List payload,
  }) {
    if (schema <= 0 || schema > _maximumUint32) {
      throw ArgumentError.value(
        schema,
        'schema',
        'Must be in the unsigned 32-bit range starting at one.',
      );
    }
    final codecBytes = utf8.encode(codecId);
    if (codecId.isEmpty ||
        codecBytes.length > _maximumUint16 ||
        utf8.decode(codecBytes) != codecId) {
      throw ArgumentError.value(
        codecId.length,
        'codecId',
        'Must be non-empty valid Unicode within 65535 UTF-8 bytes.',
      );
    }
    if (payload.length > _maximumUint32) {
      throw ArgumentError.value(
        payload.length,
        'payload',
        'Must fit in an unsigned 32-bit length.',
      );
    }

    final fetchedAtMicros = fetchedAt.toUtc().microsecondsSinceEpoch;
    if (fetchedAtMicros < _minimumSafeInteger ||
        fetchedAtMicros > _maximumSafeInteger) {
      throw ArgumentError.value(
        fetchedAtMicros,
        'fetchedAt',
        'UTC microseconds must fit the JavaScript safe-integer range.',
      );
    }
    final bytes = Uint8List(_headerLength + codecBytes.length + payload.length);
    bytes.setRange(0, _magic.length, _magic);
    bytes[4] = isInvalidated ? _invalidatedFlag : 0;
    final data = ByteData.sublistView(bytes);
    _setSafeInt64(data, 5, fetchedAtMicros);
    data.setUint32(13, schema, Endian.big);
    data.setUint16(17, codecBytes.length, Endian.big);
    data.setUint32(19, payload.length, Endian.big);
    bytes.setRange(
      _headerLength,
      _headerLength + codecBytes.length,
      codecBytes,
    );
    bytes.setRange(_headerLength + codecBytes.length, bytes.length, payload);
    return bytes;
  }

  /// Decodes and strictly validates the fixed `KCH1` record format.
  static HiveCeEnvelope decode(Uint8List bytes) {
    if (bytes.length < _headerLength) {
      throw const FormatException('Hive CE record is truncated.');
    }
    for (var index = 0; index < _magic.length; index++) {
      if (bytes[index] != _magic[index]) {
        throw const FormatException('Hive CE record magic is unsupported.');
      }
    }
    final flags = bytes[4];
    if (flags & ~_knownFlags != 0) {
      throw const FormatException('Hive CE record flags are unsupported.');
    }

    final data = ByteData.sublistView(bytes);
    final fetchedAtMicros = _getSafeInt64(data, 5);
    final schema = data.getUint32(13, Endian.big);
    final codecLength = data.getUint16(17, Endian.big);
    final payloadLength = data.getUint32(19, Endian.big);
    if (schema == 0) {
      throw const FormatException('Hive CE record schema is invalid.');
    }
    final expectedLength = _headerLength + codecLength + payloadLength;
    if (expectedLength != bytes.length) {
      throw const FormatException('Hive CE record length is inconsistent.');
    }

    late final String codecId;
    try {
      codecId = utf8.decode(
        bytes.sublist(_headerLength, _headerLength + codecLength),
        allowMalformed: false,
      );
    } on FormatException {
      throw const FormatException('Hive CE codec identifier is invalid UTF-8.');
    }
    if (codecId.isEmpty) {
      throw const FormatException('Hive CE codec identifier is empty.');
    }
    late final DateTime fetchedAt;
    try {
      fetchedAt = DateTime.fromMicrosecondsSinceEpoch(
        fetchedAtMicros,
        isUtc: true,
      );
    } on ArgumentError {
      throw const FormatException('Hive CE fetchedAt is out of range.');
    }

    return HiveCeEnvelope._(
      fetchedAt: fetchedAt,
      isInvalidated: flags & _invalidatedFlag != 0,
      schema: schema,
      codecId: codecId,
      payload: Uint8List.fromList(
        bytes.sublist(_headerLength + codecLength, expectedLength),
      ),
    );
  }
}

void _setSafeInt64(ByteData data, int offset, int value) {
  var high = value ~/ _twoTo32;
  if (value < 0 && value % _twoTo32 != 0) {
    high -= 1;
  }
  final low = value - high * _twoTo32;
  data.setInt32(offset, high, Endian.big);
  data.setUint32(offset + 4, low, Endian.big);
}

int _getSafeInt64(ByteData data, int offset) {
  final high = data.getInt32(offset, Endian.big);
  final low = data.getUint32(offset + 4, Endian.big);
  final value = high * _twoTo32 + low;
  if (value < _minimumSafeInteger || value > _maximumSafeInteger) {
    throw const FormatException(
      'Hive CE fetchedAt exceeds the cross-platform safe range.',
    );
  }
  return value;
}
