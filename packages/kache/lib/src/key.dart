import 'dart:convert';
import 'dart:typed_data';

const _formatPrefix = 'k1:';
const _maxUint32 = 0xffffffff;
const _maxSafeInteger = 9007199254740991;
const _minSafeInteger = -_maxSafeInteger;

/// A validated cache namespace and its canonical storage prefix.
///
/// Namespace values are encoded without Unicode normalization. Constructing a
/// namespace validates the same empty-string and Unicode invariants as
/// [KacheKey]. Pass this type to persistence APIs so destructive namespace
/// operations cannot receive an arbitrary raw prefix.
final class KacheNamespace {
  /// Creates a validated namespace from [value].
  ///
  /// Throws [KacheKeyFormatException] when [value] is empty or contains an
  /// unpaired surrogate. The exception does not retain or render [value].
  factory KacheNamespace(String value) {
    _validateNamespace(value);
    return KacheNamespace._(value, '$_formatPrefix${_encodeString(value)}:');
  }

  const KacheNamespace._(this.value, this.storagePrefix);

  /// The validated, unnormalized namespace value.
  final String value;

  /// The canonical prefix shared by every [KacheKey] in this namespace.
  final String storagePrefix;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is KacheNamespace && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// A stable, typed cache key suitable for memory and persistent storage.
///
/// The canonical storage format is
/// `k1:<base64url(namespace)>:<base64url(parts)>`. Both base64url sections omit
/// padding. The namespace is encoded as UTF-8 without Unicode normalization.
///
/// The binary parts stream uses tags `0` for `null`, `1` for `false`, `2` for
/// `true`, `3` for integer-valued numbers, `4` for strings, and `5` for byte
/// lists. Tags `3` through `5` are followed by an unsigned 32-bit big-endian
/// byte length and then the value bytes. Numbers use canonical ASCII decimal,
/// strings use unnormalized UTF-8, and byte lists are copied as-is.
///
/// This versioned format is intended to remain byte-for-byte stable after
/// publication. For example:
///
/// ```dart
/// final key = KacheKey('users', [42, 'profile']);
/// print(key.storageKey);
/// ```
final class KacheKey {
  /// Creates a key in [namespace] from an ordered sequence of typed [parts].
  ///
  /// Supported parts are `null`, [bool], integer-valued [num] instances in the
  /// JavaScript safe-integer range `-(2^53 - 1)` through `2^53 - 1`, [String],
  /// and [Uint8List]. Integral `int` and `double` representations produce the
  /// same key; larger integer identifiers should be supplied as strings.
  ///
  /// The iterable is consumed synchronously. Each byte list is copied and
  /// encoded before iteration continues, so later input mutation cannot change
  /// the key. Strings are not normalized.
  ///
  /// Throws [KacheKeyFormatException] when the namespace is empty, a string
  /// contains an unpaired surrogate, a number is fractional, non-finite, or
  /// outside the safe range, or a part has an unsupported type. Exceptions do
  /// not retain or render the rejected input value.
  factory KacheKey(String namespace, [Iterable<Object?> parts = const []]) {
    final validatedNamespace = KacheNamespace(namespace);

    final partBytes = BytesBuilder(copy: false);
    var partIndex = 0;
    for (final part in parts) {
      final ownedPart = part is Uint8List ? Uint8List.fromList(part) : part;
      _writePart(partBytes, ownedPart, partIndex);
      partIndex++;
    }

    return KacheKey._(
      validatedNamespace.value,
      '${validatedNamespace.storagePrefix}${_encodeBytes(partBytes.takeBytes())}',
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
  static String namespacePrefix(String namespace) =>
      KacheNamespace(namespace).storagePrefix;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KacheKey && storageKey == other.storageKey;

  @override
  int get hashCode => storageKey.hashCode;
}

/// Reports a namespace or key-part value that cannot be encoded canonically.
final class KacheKeyFormatException extends FormatException {
  KacheKeyFormatException._(super.message);
}

void _validateNamespace(String namespace) {
  if (namespace.isEmpty) {
    throw KacheKeyFormatException._('Invalid namespace (size: 0).');
  }
  _validateUnicode(namespace, stage: 'namespace');
}

void _validateUnicode(String value, {required String stage, int? partIndex}) {
  final codeUnits = value.codeUnits;
  for (var index = 0; index < codeUnits.length; index++) {
    final codeUnit = codeUnits[index];
    if (_isHighSurrogate(codeUnit)) {
      if (index + 1 == codeUnits.length ||
          !_isLowSurrogate(codeUnits[index + 1])) {
        throw KacheKeyFormatException._(
          _unicodeErrorMessage(stage, partIndex, index, codeUnits.length),
        );
      }
      index++;
    } else if (_isLowSurrogate(codeUnit)) {
      throw KacheKeyFormatException._(
        _unicodeErrorMessage(stage, partIndex, index, codeUnits.length),
      );
    }
  }
}

String _unicodeErrorMessage(
  String stage,
  int? partIndex,
  int codeUnitIndex,
  int size,
) {
  final partLocation = partIndex == null ? '' : ' at part index $partIndex';
  return 'Invalid Unicode in $stage$partLocation '
      '(code-unit index: $codeUnitIndex, size: $size).';
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xd800 && codeUnit <= 0xdbff;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xdc00 && codeUnit <= 0xdfff;

String _encodeString(String value) => _encodeBytes(utf8.encode(value));

String _encodeBytes(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

void _writePart(BytesBuilder bytes, Object? part, int partIndex) {
  if (part == null) {
    bytes.addByte(0);
  } else if (part is bool) {
    bytes.addByte(part ? 2 : 1);
  } else if (part is num) {
    _writeLengthPrefixed(
      bytes,
      3,
      ascii.encode(_canonicalInteger(part, partIndex)),
      partIndex,
    );
  } else if (part is String) {
    _validateUnicode(part, stage: 'string part', partIndex: partIndex);
    _writeLengthPrefixed(bytes, 4, utf8.encode(part), partIndex);
  } else if (part is Uint8List) {
    _writeLengthPrefixed(bytes, 5, part, partIndex);
  } else {
    throw KacheKeyFormatException._(
      'Unsupported key part at index $partIndex '
      '(type: ${part.runtimeType}).',
    );
  }
}

String _canonicalInteger(num value, int partIndex) {
  if (!value.isFinite ||
      value < _minSafeInteger ||
      value > _maxSafeInteger ||
      value != value.truncate()) {
    throw KacheKeyFormatException._(
      'Invalid numeric key part at index $partIndex '
      '(type: ${value.runtimeType}).',
    );
  }
  return value.toInt().toString();
}

void _writeLengthPrefixed(
  BytesBuilder target,
  int tag,
  List<int> value,
  int partIndex,
) {
  final length = value.length;
  if (length > _maxUint32) {
    throw KacheKeyFormatException._(
      'Key part at index $partIndex exceeds the binary length limit '
      '(size: $length).',
    );
  }

  final lengthBytes = ByteData(4)..setUint32(0, length, Endian.big);
  target
    ..addByte(tag)
    ..add(lengthBytes.buffer.asUint8List())
    ..add(value);
}
