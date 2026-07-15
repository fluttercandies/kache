const _adapterMagic = 'KCH-A1';
const _adapterVersion = 1;
const _maximumAdapterTypeId = 223;
const _maximumSafeMicroseconds = 9007199254740991;

final class HiveCeAdapterEnvelope {
  const HiveCeAdapterEnvelope._({
    required this.fetchedAt,
    required this.isInvalidated,
    required this.typeId,
    required this.data,
  });

  final DateTime fetchedAt;
  final bool isInvalidated;
  final int typeId;
  final Object? data;

  static List<Object?> encode({
    required DateTime fetchedAt,
    required bool isInvalidated,
    required int typeId,
    required Object? data,
  }) {
    _validateTypeId(typeId);
    final micros = fetchedAt.toUtc().microsecondsSinceEpoch;
    if (micros < -_maximumSafeMicroseconds ||
        micros > _maximumSafeMicroseconds) {
      throw ArgumentError.value(
        fetchedAt,
        'fetchedAt',
        'UTC microseconds must fit the JavaScript safe-integer range.',
      );
    }
    return <Object?>[
      _adapterMagic,
      _adapterVersion,
      typeId,
      micros,
      isInvalidated,
      data,
    ];
  }

  static HiveCeAdapterEnvelope decode(Object? raw) {
    if (raw is! List || raw.length != 6) {
      throw const FormatException('Hive CE adapter record is malformed.');
    }
    if (raw[0] != _adapterMagic || raw[1] != _adapterVersion) {
      throw const FormatException('Hive CE adapter record version is unknown.');
    }
    final typeId = raw[2];
    final micros = raw[3];
    final invalidated = raw[4];
    if (typeId is! int || micros is! int || invalidated is! bool) {
      throw const FormatException('Hive CE adapter record fields are invalid.');
    }
    _validateTypeId(typeId);
    if (micros < -_maximumSafeMicroseconds ||
        micros > _maximumSafeMicroseconds) {
      throw const FormatException(
        'Hive CE adapter record timestamp is out of range.',
      );
    }
    late final DateTime fetchedAt;
    try {
      fetchedAt = DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
    } on ArgumentError {
      throw const FormatException(
        'Hive CE adapter record timestamp is invalid.',
      );
    }
    return HiveCeAdapterEnvelope._(
      fetchedAt: fetchedAt,
      isInvalidated: invalidated,
      typeId: typeId,
      data: raw[5],
    );
  }

  static void _validateTypeId(int typeId) {
    if (typeId < 0 || typeId > _maximumAdapterTypeId) {
      throw ArgumentError.value(
        typeId,
        'typeId',
        'Must be an external Hive CE type id from 0 through 223.',
      );
    }
  }
}
