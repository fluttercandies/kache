import 'dart:convert';
import 'dart:typed_data';

const _formatPrefix = 'k1:';
const _maxUint32 = 0xffffffff;

/// A stable, typed cache key suitable for memory and persistent storage.
///
/// Storage keys use the versioned `k1` format. The format is canonical and is
/// intended to remain byte-for-byte stable after publication.
final class KacheKey {
  /// Creates a key in [namespace] from an ordered sequence of typed [parts].
  ///
  /// Supported parts are `null`, [bool], [int], [String], and [Uint8List].
  /// The iterable and byte-list values are copied during construction.
  ///
  /// Throws [KacheKeyFormatException] when the namespace is empty, a string
  /// contains an unpaired surrogate, or a part has an unsupported type.
  factory KacheKey(String namespace, [Iterable<Object?> parts = const []]) {
    _validateNamespace(namespace);

    final copiedParts = <Object?>[];
    for (final part in parts) {
      copiedParts.add(part is Uint8List ? Uint8List.fromList(part) : part);
    }

    final partBytes = BytesBuilder(copy: false);
    for (final part in copiedParts) {
      _writePart(partBytes, part);
    }

    return KacheKey._(
      namespace,
      '$_formatPrefix${_encodeString(namespace)}:'
      '${_encodeBytes(partBytes.takeBytes())}',
    );
  }

  const KacheKey._(this.namespace, this.storageKey);

  /// The namespace that owns this key.
  final String namespace;

  /// The canonical, versioned representation used by storage backends.
  final String storageKey;

  /// Returns the canonical storage prefix for every key in [namespace].
  ///
  /// Throws [KacheKeyFormatException] when [namespace] is empty or contains an
  /// unpaired surrogate.
  static String namespacePrefix(String namespace) {
    _validateNamespace(namespace);
    return '$_formatPrefix${_encodeString(namespace)}:';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KacheKey && storageKey == other.storageKey;

  @override
  int get hashCode => storageKey.hashCode;
}

/// Reports a namespace or key-part value that cannot be encoded canonically.
final class KacheKeyFormatException extends FormatException {
  /// Creates a cache-key format exception.
  KacheKeyFormatException(super.message, [super.source, super.offset]);
}

void _validateNamespace(String namespace) {
  if (namespace.isEmpty) {
    throw KacheKeyFormatException(
      'The namespace must not be empty.',
      namespace,
    );
  }
  _validateUnicode(namespace, 'namespace');
}

void _validateUnicode(String value, String description) {
  final codeUnits = value.codeUnits;
  for (var index = 0; index < codeUnits.length; index++) {
    final codeUnit = codeUnits[index];
    if (_isHighSurrogate(codeUnit)) {
      if (index + 1 == codeUnits.length ||
          !_isLowSurrogate(codeUnits[index + 1])) {
        throw KacheKeyFormatException(
          'The $description contains an unpaired high surrogate.',
          value,
          index,
        );
      }
      index++;
    } else if (_isLowSurrogate(codeUnit)) {
      throw KacheKeyFormatException(
        'The $description contains an unpaired low surrogate.',
        value,
        index,
      );
    }
  }
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xd800 && codeUnit <= 0xdbff;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xdc00 && codeUnit <= 0xdfff;

String _encodeString(String value) => _encodeBytes(utf8.encode(value));

String _encodeBytes(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

void _writePart(BytesBuilder bytes, Object? part) {
  if (part == null) {
    bytes.addByte(0);
  } else if (part is bool) {
    bytes.addByte(part ? 2 : 1);
  } else if (part is int) {
    _writeLengthPrefixed(bytes, 3, ascii.encode(part.toString()));
  } else if (part is String) {
    _validateUnicode(part, 'string part');
    _writeLengthPrefixed(bytes, 4, utf8.encode(part));
  } else if (part is Uint8List) {
    _writeLengthPrefixed(bytes, 5, part);
  } else {
    throw KacheKeyFormatException(
      'Unsupported key part type: ${part.runtimeType}.',
      part,
    );
  }
}

void _writeLengthPrefixed(BytesBuilder target, int tag, List<int> value) {
  final length = value.length;
  if (length > _maxUint32) {
    throw KacheKeyFormatException(
      'A key part cannot exceed $_maxUint32 bytes.',
      value,
    );
  }

  final lengthBytes = ByteData(4)..setUint32(0, length, Endian.big);
  target
    ..addByte(tag)
    ..add(lengthBytes.buffer.asUint8List())
    ..add(value);
}
