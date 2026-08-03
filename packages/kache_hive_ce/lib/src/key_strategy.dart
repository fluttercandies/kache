part of 'store.dart';

const _kacheKeyPrefix = 'kache:2:';
const _shaCategory = 's';
const _hmacCategory = 'h';
const _domainNamespace = 'kache-hive-ce:namespace';
const _domainKey = 'kache-hive-ce:key';
const _domainIdentity = 'kache-hive-ce:identity';

/// Controls how logical [KacheKey]s map to physical Hive box keys.
///
/// The default [HiveCeKeyStrategy.sha256] strategy applies a domain-separated
/// SHA-256 digest to each key component. The physical key does not directly
/// encode reversible canonical key material, and logical keys can exceed Hive
/// CE's 255-byte string key boundary.
///
/// **Limitations of [HiveCeKeyStrategy.sha256]:**
/// - SHA-256 is a deterministic digest: identical logical keys produce
///   identical physical keys, so equality relationships are still observable.
/// - Low-entropy key parts (short namespace strings, small integers) remain
///   susceptible to dictionary attacks because an attacker who knows the
///   digest algorithm can pre-compute candidate digests.
/// - **Never** pass secrets (API keys, tokens, passwords) as cache key parts.
///
/// For caches whose key material may be sensitive, use
/// [HiveCeKeyStrategy.hmacSha256] with a high-entropy secret of at least
/// 32 bytes. The HMAC strategy makes dictionary attacks infeasible without the
/// secret. Do not derive the secret from the 32-bit Hive cipher key CRC.
///
/// Treat the selected strategy and any HMAC secret as persistent storage
/// configuration. A different v2 strategy cannot address existing records;
/// use [HiveCeKacheStore.clear] before intentionally rotating it.
abstract final class HiveCeKeyStrategy {
  const HiveCeKeyStrategy._(this._category, this._identity);

  /// The default domain-separated SHA-256 key strategy.
  const factory HiveCeKeyStrategy.sha256() = _Sha256KeyStrategy;

  /// An HMAC-SHA-256 key strategy keyed by [secret].
  ///
  /// The [secret] is copied internally and never exposed. The strategy
  /// identity is derived from the secret without revealing it, allowing lease
  /// validation to detect configuration mismatches.
  ///
  /// [secret] must be at least 32 bytes. Use a cryptographically random value.
  factory HiveCeKeyStrategy.hmacSha256(List<int> secret) {
    if (secret.length < 32) {
      throw ArgumentError.value(
        secret.length,
        'secret',
        'Must be at least 32 bytes for HMAC-SHA-256.',
      );
    }
    final validated = Uint8List(secret.length);
    for (var i = 0; i < secret.length; i++) {
      final byte = secret[i];
      if (byte < 0 || byte > 255) {
        throw ArgumentError.value(
          secret.length,
          'secret',
          'Each byte must be in the range 0 through 255.',
        );
      }
      validated[i] = byte;
    }
    return _HmacSha256KeyStrategy(validated);
  }

  final String _category;
  final String _identity;

  String _namespaceDigest(KacheNamespace namespace);

  String _keyDigest(KacheKey key);

  String _formatKey(KacheKey key) {
    final ns = KacheNamespace(key.namespace);
    return '$_kacheKeyPrefix$_category:${_namespaceDigest(ns)}:'
        '${_keyDigest(key)}';
  }

  String _formatNamespacePrefix(KacheNamespace namespace) =>
      '$_kacheKeyPrefix$_category:${_namespaceDigest(namespace)}:';
}

final class _Sha256KeyStrategy extends HiveCeKeyStrategy {
  const _Sha256KeyStrategy() : super._(_shaCategory, _shaCategory);

  @override
  String _namespaceDigest(KacheNamespace namespace) {
    final input =
        utf8.encode('$_domainNamespace\x00${namespace.storagePrefix}');
    return _digestBase64(sha256.convert(input).bytes);
  }

  @override
  String _keyDigest(KacheKey key) {
    final input = utf8.encode('$_domainKey\x00${key.storageKey}');
    return _digestBase64(sha256.convert(input).bytes);
  }
}

final class _HmacSha256KeyStrategy extends HiveCeKeyStrategy {
  _HmacSha256KeyStrategy(Uint8List secret)
      : _hmac = Hmac(sha256, secret),
        super._(_hmacCategory, _hmacIdentity(secret));

  final Hmac _hmac;

  @override
  String _namespaceDigest(KacheNamespace namespace) {
    final input =
        utf8.encode('$_domainNamespace\x00${namespace.storagePrefix}');
    return _digestBase64(_hmac.convert(input).bytes);
  }

  @override
  String _keyDigest(KacheKey key) {
    final input = utf8.encode('$_domainKey\x00${key.storageKey}');
    return _digestBase64(_hmac.convert(input).bytes);
  }

  static String _hmacIdentity(Uint8List secret) {
    final hmac = Hmac(sha256, secret);
    final digest = hmac.convert(utf8.encode(_domainIdentity));
    return '$_hmacCategory:${_digestBase64(digest.bytes)}';
  }
}

String _digestBase64(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Strict grammar for new managed physical keys:
/// `kache:2:[sh]:<43 base64url chars>:<43 base64url chars>`.
final _newManagedKeyPattern = RegExp(
  r'^kache:2:[sh]:[A-Za-z0-9_-]{43}:[A-Za-z0-9_-]{43}$',
);

/// Strict grammar for legacy managed keys: `k1:<base64url+>:<base64url*>`.
final _legacyManagedKeyPattern = RegExp(
  r'^k1:[A-Za-z0-9_-]+:[A-Za-z0-9_-]*$',
);

bool _isNewManagedKey(String key) => _newManagedKeyPattern.hasMatch(key);

bool _isLegacyManagedKey(String key) => _legacyManagedKeyPattern.hasMatch(key);

bool _isManagedKey(String key) =>
    _isNewManagedKey(key) || _isLegacyManagedKey(key);

/// Whether [key] is a managed key belonging to [newPrefix] or [legacyPrefix].
///
/// Both the prefix match and the strict grammar match must pass, preventing
/// host keys that merely share a prefix from being deleted.
bool _isManagedNamespaceKey(
  String key,
  String newPrefix,
  String legacyPrefix,
) {
  if (key.startsWith(newPrefix) && _isNewManagedKey(key)) {
    return true;
  }
  return key.startsWith(legacyPrefix) && _isLegacyManagedKey(key);
}
