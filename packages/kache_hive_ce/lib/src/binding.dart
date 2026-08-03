part of 'store.dart';

/// Opaque Hive CE persistence configuration for values of type `T`.
final class HiveCeBinding<T> extends KachePersistenceBinding<T> {
  HiveCeBinding._({
    required super.backend,
    required this.codecId,
    required this.codec,
    required this.migrate,
    required bool hasTypeConflict,
  })  : _hasTypeConflict = hasTypeConflict,
        super(fingerprint: _bindingFingerprint(codecId));

  /// Sole stable identifier for the encoded payload format.
  ///
  /// Change this identifier whenever [codec] changes how bytes are interpreted.
  final String codecId;

  /// Typed payload codec identified by [codecId].
  final HiveCeCodec<T> codec;

  /// Optional migration from a previous codec identifier.
  final HiveCeMigrator<T>? migrate;

  final bool _hasTypeConflict;
}

String _bindingFingerprint(String codecId) {
  final encodedId = base64Url.encode(utf8.encode(codecId)).replaceAll('=', '');
  return 'hive-ce:bytes:v2:$encodedId';
}

void _validateBindingConfiguration({required String codecId}) {
  HiveCeEnvelope.encode(
    fetchedAt: DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
    isInvalidated: false,
    codecId: codecId,
    payload: Uint8List(0),
  );
}
