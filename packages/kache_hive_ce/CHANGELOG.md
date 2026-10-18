## 3.1.0

- Added `isolateThreshold` to `HiveCeKacheStore.open` and `fromBox`
  (default 64 KiB, `null` keeps all codec work inline). Byte-codec decode,
  migration, and encode for records at or above the threshold run on a
  background isolate, so large cached pages no longer block the frame that
  subscribes to them. Smaller records still decode synchronously and render in
  the first frame. Codecs whose callbacks cannot be sent to another isolate
  fall back to inline work without failing the read or deleting the record.
- Large cached reads now complete asynchronously. Widget tests that use large
  payloads under the fake clock should pass `isolateThreshold: null`.
- Kept per-key call order for offloaded writes: later reads, writes, and
  deletes of the same key wait for them, and `clear`, `clearNamespace`, and
  `close` drain them first. Inline writes keep their synchronous start.
- Removed redundant whole-payload copies on read and write, and replaced the
  migration rewrite's byte-by-byte record comparison with an identity check.
  On Web, codec work always runs inline.
- Updated the Kache dependency to `^3.1.0`.

## 3.0.0

- Removed the duplicate integer schema API. `codecId` is now the sole byte
  format identity, and `HiveCeMigrator` receives the stored codec identifier.
- Added race-safe lazy codec migration that never hides migrated data or
  overwrites a newer record.
- Removed reads, rewrites, and clears for retired canonical keys, v2 hashed
  keys, and v1 byte envelopes. Current managed keys use the strict v3 grammar.
- Updated the Kache dependency to `^3.0.0`.

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
