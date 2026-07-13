import 'dart:typed_data';

/// Encodes and decodes one application model for Hive CE persistence.
final class HiveCeCodec<T> {
  /// Creates a codec from typed callbacks.
  const HiveCeCodec({required this.encode, required this.decode});

  /// Encodes a typed value into owned payload bytes.
  final Uint8List Function(T value) encode;

  /// Decodes payload bytes into a typed value.
  final T Function(Uint8List bytes) decode;
}

/// Migrates an older schema payload into the binding's current typed value.
typedef HiveCeMigrator<T> = T Function(Uint8List payload, int fromSchema);
