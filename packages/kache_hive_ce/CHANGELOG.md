## 2.1.0

- Added `HiveCeKeyStrategy` with domain-separated SHA-256 (default) and
  HMAC-SHA-256 keyed strategies. Physical keys are fixed-length digests that do
  not embed canonical key material and remain under Hive CE's 255-byte limit;
  the documentation states deterministic SHA-256's equality and dictionary
  attack limitations.
- Added `HiveCeOpenException` wrapping all cipher lease mismatches, strategy
  lease mismatches, and asynchronous Hive I/O failures during box acquisition.
  Its `toString` is sanitized.
- Added cipher identity pinning: concurrent opens sharing an active managed-box
  lease reject a different cipher object, type, or key CRC. Borrowed boxes
  reject any supplied cipher because it cannot be verified.
- Added race-safe lazy migration from 2.0.0 canonical `k1:` keys to the new
  hashed format.
- Added strict managed-key grammar for selective `clear()` and
  `clearNamespace()`, preserving host keys that only resemble Kache prefixes.
- Added `crypto` ^3.0.7 as a direct dependency.
- Reserved pending shared-box acquisitions before awaiting `openBox`, preventing
  an earlier lease from closing the box returned to a concurrent opener.
- Enforced store closure for deferred native-adapter maintenance and rejected
  `bindAdapter<T>` calls whose adapter cannot encode `T`.
- Removed filesystem paths from the mutually exclusive `path`/`bytes`
  argument error.

## 2.0.0

- Updated the Kache core range for trace/span persistence events and reasoned
  read/write/delete cancellation.
- Kept native TypeAdapter records, byte envelopes, migrations, and on-disk
  compatibility unchanged.

## 1.2.0

- Updated the Kache core compatibility range for the coordinated 1.2 release.
- Added support for Hive CE extended external TypeAdapter ids through 65439.

## 1.1.0

- Added `bindAdapter<T>` for reusing Hive CE `TypeAdapter` registrations
  without duplicating model codecs.
- Added a strictly validated, versioned Hive-native envelope with nullable
  value support and byte-envelope mode isolation.
- Added Hive interface ownership validation for injected boxes.

## 1.0.1

- Lowered the verified Dart SDK requirement from 3.9 to 3.5.

## 1.0.0

- Initial release of versioned Hive CE persistence for Kache.
- Added typed codecs, schema migration, encrypted box support, corruption
  recovery, and explicit box ownership.
