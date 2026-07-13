part of 'store.dart';

/// Opaque Hive CE persistence configuration for values of type `T`.
final class HiveCeBinding<T> extends KachePersistenceBinding<T> {
  HiveCeBinding._({
    required super.backend,
    required this.codecId,
    required this.schema,
    required this.codec,
    required this.migrate,
    required bool hasTypeConflict,
  }) : _hasTypeConflict = hasTypeConflict,
       super(fingerprint: _bindingFingerprint(codecId, schema));

  /// Stable identifier written into every physical record.
  final String codecId;

  /// Current positive unsigned 32-bit model schema.
  final int schema;

  /// Typed payload codec for [schema].
  final HiveCeCodec<T> codec;

  /// Optional older-schema migration callback.
  final HiveCeMigrator<T>? migrate;

  final bool _hasTypeConflict;
}

String _bindingFingerprint(String codecId, int schema) {
  final encodedId = base64Url.encode(utf8.encode(codecId)).replaceAll('=', '');
  return 'hive-ce:v1:$encodedId:$schema';
}

void _validateBindingConfiguration({
  required String codecId,
  required int schema,
}) {
  HiveCeEnvelope.encode(
    fetchedAt: DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
    isInvalidated: false,
    schema: schema,
    codecId: codecId,
    payload: Uint8List(0),
  );
}
