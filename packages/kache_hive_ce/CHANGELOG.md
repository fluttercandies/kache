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
