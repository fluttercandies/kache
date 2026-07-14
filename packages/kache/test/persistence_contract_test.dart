import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  group('KachePersistenceBackend', () {
    test('reads and writes typed String data', () async {
      final backend = _FakeBackend();
      final binding = _Binding<String>(
        backend: backend,
        fingerprint: 'string-v1',
      );
      final key = KacheKey('users', [1]);
      final entry = KachePersistedEntry<String>(
        data: 'Ada',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026, 1, 2)),
      );

      await backend.write(key: key, binding: binding, entry: entry);
      final read = await backend.read(key: key, binding: binding);

      expect(read?.entry.data, 'Ada');
      expect(read?.entry.metadata, entry.metadata);
    });

    test('reads and writes typed custom objects', () async {
      final backend = _FakeBackend();
      final binding = _Binding<_Profile>(
        backend: backend,
        fingerprint: 'profile-v1',
      );
      final key = KacheKey('profiles', [7]);
      final profile = _Profile('Grace');

      await backend.write(
        key: key,
        binding: binding,
        entry: KachePersistedEntry<_Profile>(
          data: profile,
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026, 2, 3)),
        ),
      );
      final read = await backend.read(key: key, binding: binding);

      expect(read?.entry.data, same(profile));
    });

    test('preserves null data when T is nullable', () async {
      final backend = _FakeBackend();
      final binding = _Binding<String?>(
        backend: backend,
        fingerprint: 'nullable-string-v1',
      );
      final key = KacheKey('nullable', [1]);

      await backend.write(
        key: key,
        binding: binding,
        entry: KachePersistedEntry<String?>(
          data: null,
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026, 3, 4)),
        ),
      );
      final read = await backend.read(key: key, binding: binding);

      expect(read, isNotNull);
      expect(read?.entry.data, isNull);
    });

    test('uses null to report a read miss', () async {
      final backend = _FakeBackend();
      final binding = _Binding<String>(
        backend: backend,
        fingerprint: 'string-v1',
      );

      final read = await backend.read(
        key: KacheKey('missing'),
        binding: binding,
      );

      expect(read, isNull);
    });

    test(
      'exposes delete, namespace clear, clear, and close operations',
      () async {
        final backend = _FakeBackend();
        final binding = _Binding<String>(
          backend: backend,
          fingerprint: 'string-v1',
        );
        final first = KacheKey('first', [1]);
        final second = KacheKey('second', [2]);
        final metadata = KachePersistedMetadata(
          fetchedAt: DateTime.utc(2026, 4, 5),
        );

        await backend.write(
          key: first,
          binding: binding,
          entry: KachePersistedEntry(data: 'first', metadata: metadata),
        );
        await backend.write(
          key: second,
          binding: binding,
          entry: KachePersistedEntry(data: 'second', metadata: metadata),
        );
        await backend.delete(key: first);
        expect(await backend.read(key: first, binding: binding), isNull);

        await backend.clearNamespace(namespace: KacheNamespace('second'));
        expect(await backend.read(key: second, binding: binding), isNull);

        await backend.clear();
        await backend.close();
        expect(backend.clearCount, 1);
        expect(backend.closeCount, 1);
      },
    );
  });

  group('KachePersistenceBinding', () {
    test('exposes its backend and stable fingerprint', () {
      final backend = _FakeBackend();
      final binding = _Binding<String>(
        backend: backend,
        fingerprint: 'binding-fingerprint-v1',
      );

      expect(binding.backend, same(backend));
      expect(binding.fingerprint, 'binding-fingerprint-v1');
    });

    test('rejects empty and whitespace-only fingerprints', () {
      final backend = _FakeBackend();

      for (final fingerprint in ['', ' ', '\t\n']) {
        expect(
          () => _Binding<String>(backend: backend, fingerprint: fingerprint),
          throwsA(isA<KachePersistenceBindingException>()),
        );
      }
    });

    test('accepts the identical backend instance', () {
      final backend = _FakeBackend();
      final binding = _Binding<String>(
        backend: backend,
        fingerprint: 'string-v1',
      );

      expect(() => binding.ensureBackend(backend), returnsNormally);
    });

    test('rejects another backend without leaking the fingerprint', () {
      const secret = 'fingerprint-secret';
      final binding = _Binding<String>(
        backend: _FakeBackend(),
        fingerprint: secret,
      );

      final exception = _captureBindingException(
        () => binding.ensureBackend(_FakeBackend()),
      );

      expect(exception.toString(), isNot(contains(secret)));
    });
  });

  group('KachePersistedMetadata', () {
    test('normalizes fetchedAt to UTC and defaults to valid', () {
      final fetchedAt = DateTime(2026, 5, 6, 7, 8, 9, 10, 11);

      final metadata = KachePersistedMetadata(fetchedAt: fetchedAt);

      expect(metadata.fetchedAt, fetchedAt.toUtc());
      expect(metadata.fetchedAt.isUtc, isTrue);
      expect(metadata.isInvalidated, isFalse);
    });

    test('supports invalidation and value semantics', () {
      final first = KachePersistedMetadata(
        fetchedAt: DateTime.utc(2026, 6, 7),
        isInvalidated: true,
      );
      final equal = KachePersistedMetadata(
        fetchedAt: DateTime.utc(2026, 6, 7),
        isInvalidated: true,
      );
      final different = KachePersistedMetadata(
        fetchedAt: DateTime.utc(2026, 6, 7),
      );

      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(first, isNot(different));
    });

    test('copyWith replaces selected fields and keeps UTC normalization', () {
      final original = KachePersistedMetadata(
        fetchedAt: DateTime.utc(2026, 7, 8),
      );
      final replacementTime = DateTime(2026, 8, 9, 10);

      final invalidated = original.copyWith(isInvalidated: true);
      final rescheduled = original.copyWith(fetchedAt: replacementTime);

      expect(invalidated.fetchedAt, original.fetchedAt);
      expect(invalidated.isInvalidated, isTrue);
      expect(rescheduled.fetchedAt, replacementTime.toUtc());
      expect(rescheduled.fetchedAt.isUtc, isTrue);
      expect(rescheduled.isInvalidated, isFalse);
    });
  });

  group('KachePersistenceRead', () {
    test('allows maintenance to be absent', () async {
      final read = KachePersistenceRead<String>(
        entry: KachePersistedEntry(
          data: 'cached',
          metadata: KachePersistedMetadata(
            fetchedAt: DateTime.utc(2026, 9, 10),
          ),
        ),
      );

      expect(read.entry.data, 'cached');
      expect(read.hasMaintenance, isFalse);
      await expectLater(read.runMaintenance(), completes);
    });

    test('does not start or report lazy maintenance before run', () {
      var invocationCount = 0;

      final read = KachePersistenceRead<String>(
        entry: KachePersistedEntry(
          data: 'available-now',
          metadata: KachePersistedMetadata(
            fetchedAt: DateTime.utc(2026, 10, 11),
          ),
        ),
        maintenance: () {
          invocationCount++;
          throw StateError('not observed before run');
        },
      );

      expect(read.entry.data, 'available-now');
      expect(read.hasMaintenance, isTrue);
      expect(invocationCount, 0);
    });

    test('allows successful maintenance to be observed', () async {
      var invocationCount = 0;
      final read = KachePersistenceRead<String>(
        entry: KachePersistedEntry(
          data: 'cached',
          metadata: KachePersistedMetadata(
            fetchedAt: DateTime.utc(2026, 11, 12),
          ),
        ),
        maintenance: () {
          invocationCount++;
        },
      );

      await expectLater(read.runMaintenance(), completes);
      expect(invocationCount, 1);
    });

    test('allows failed maintenance to be observed', () async {
      final cause = StateError('migration failed');
      final read = KachePersistenceRead<String>(
        entry: KachePersistedEntry(
          data: 'still-usable',
          metadata: KachePersistedMetadata(
            fetchedAt: DateTime.utc(2026, 12, 13),
          ),
        ),
        maintenance: () => Future<void>.error(cause),
      );

      expect(read.entry.data, 'still-usable');
      await expectLater(read.runMaintenance(), throwsA(same(cause)));
    });

    test('runs maintenance once and shares the same future', () async {
      final completer = Completer<void>();
      var invocationCount = 0;
      final read = KachePersistenceRead<String>(
        entry: KachePersistedEntry(
          data: 'cached',
          metadata: KachePersistedMetadata(
            fetchedAt: DateTime.utc(2027, 1, 14),
          ),
        ),
        maintenance: () {
          invocationCount++;
          return completer.future;
        },
      );

      final first = read.runMaintenance();
      final second = read.runMaintenance();

      expect(second, same(first));
      expect(invocationCount, 1);
      completer.complete();
      await first;
    });

    test('shares the cached future during synchronous reentrancy', () async {
      var invocationCount = 0;
      late Future<void> reentrant;
      late KachePersistenceRead<String> read;
      read = KachePersistenceRead<String>(
        entry: KachePersistedEntry(
          data: 'cached',
          metadata: KachePersistedMetadata(
            fetchedAt: DateTime.utc(2027, 2, 15),
          ),
        ),
        maintenance: () {
          invocationCount++;
          if (invocationCount == 1) {
            reentrant = read.runMaintenance();
          }
        },
      );

      final first = read.runMaintenance();

      expect(invocationCount, 1);
      expect(reentrant, same(first));
      await first;
    });

    test('turns synchronous maintenance throws into future errors', () async {
      final cause = StateError('synchronous migration failure');
      final read = KachePersistenceRead<String>(
        entry: KachePersistedEntry(
          data: 'still-usable',
          metadata: KachePersistedMetadata(
            fetchedAt: DateTime.utc(2027, 2, 15),
          ),
        ),
        maintenance: () => throw cause,
      );

      late Future<void> maintenance;
      expect(() => maintenance = read.runMaintenance(), returnsNormally);
      await expectLater(maintenance, throwsA(same(cause)));
    });
  });

  group('KachePersistenceException', () {
    test('retains operation, stage, cause, and stack trace', () {
      final cause = StateError('write failed');
      final stackTrace = StackTrace.current;

      final exception = KachePersistenceException(
        operation: KachePersistenceOperation.write,
        stage: KachePersistenceStage.encode,
        cause: cause,
        stackTrace: stackTrace,
      );

      expect(exception.operation, KachePersistenceOperation.write);
      expect(exception.stage, KachePersistenceStage.encode);
      expect(exception.cause, same(cause));
      expect(exception.stackTrace, same(stackTrace));
    });

    test('renders operation and stage without rendering its cause', () {
      const secret = 'persistence-secret';
      final cause = _SensitiveCause(secret);
      final exception = KachePersistenceException(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.decode,
        cause: cause,
        stackTrace: StackTrace.current,
      );

      final rendered = exception.toString();

      expect(rendered, contains('read'));
      expect(rendered, contains('decode'));
      expect(rendered, isNot(contains(secret)));
      expect(cause.wasRendered, isFalse);
    });

    test('defines every persistence operation and stage', () {
      expect(KachePersistenceOperation.values, [
        KachePersistenceOperation.read,
        KachePersistenceOperation.write,
        KachePersistenceOperation.delete,
        KachePersistenceOperation.clearNamespace,
        KachePersistenceOperation.clear,
        KachePersistenceOperation.close,
      ]);
      expect(KachePersistenceStage.values, [
        KachePersistenceStage.backend,
        KachePersistenceStage.encode,
        KachePersistenceStage.decode,
        KachePersistenceStage.migration,
      ]);
    });

    test('accepts the complete valid operation and stage matrix', () {
      for (final MapEntry(key: operation, value: stages)
          in _validPersistenceStages.entries) {
        for (final stage in stages) {
          expect(
            () => KachePersistenceException(
              operation: operation,
              stage: stage,
              cause: StateError('expected failure'),
              stackTrace: StackTrace.current,
            ),
            returnsNormally,
          );
        }
      }
    });

    test('rejects every invalid operation and stage combination', () {
      for (final operation in KachePersistenceOperation.values) {
        final validStages = _validPersistenceStages[operation]!;
        for (final stage in KachePersistenceStage.values) {
          if (validStages.contains(stage)) {
            continue;
          }
          expect(
            () => KachePersistenceException(
              operation: operation,
              stage: stage,
              cause: StateError('invalid combination'),
              stackTrace: StackTrace.current,
            ),
            throwsArgumentError,
            reason: '${operation.name}/${stage.name}',
          );
        }
      }
    });

    test('does not render the cause when rejecting an invalid matrix pair', () {
      const secret = 'invalid-matrix-secret';
      final cause = _SensitiveCause(secret);

      final error = _captureArgumentError(
        () => KachePersistenceException(
          operation: KachePersistenceOperation.close,
          stage: KachePersistenceStage.decode,
          cause: cause,
          stackTrace: StackTrace.current,
        ),
      );

      expect(error.toString(), isNot(contains(secret)));
      expect(cause.wasRendered, isFalse);
    });
  });
}

const _validPersistenceStages =
    <KachePersistenceOperation, Set<KachePersistenceStage>>{
  KachePersistenceOperation.read: {
    KachePersistenceStage.backend,
    KachePersistenceStage.decode,
    KachePersistenceStage.migration,
  },
  KachePersistenceOperation.write: {
    KachePersistenceStage.backend,
    KachePersistenceStage.encode,
  },
  KachePersistenceOperation.delete: {KachePersistenceStage.backend},
  KachePersistenceOperation.clearNamespace: {KachePersistenceStage.backend},
  KachePersistenceOperation.clear: {KachePersistenceStage.backend},
  KachePersistenceOperation.close: {KachePersistenceStage.backend},
};

final class _Binding<T> extends KachePersistenceBinding<T> {
  _Binding({required super.backend, required super.fingerprint});
}

final class _FakeBackend implements KachePersistenceBackend {
  final Map<KacheKey, _StoredEntry> _entries = <KacheKey, _StoredEntry>{};

  KachePersistenceMaintenance? maintenance;
  int clearCount = 0;
  int closeCount = 0;

  @override
  Future<KachePersistenceRead<T>?> read<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
  }) async {
    binding.ensureBackend(this);
    final stored = _entries[key];
    if (stored == null) {
      return null;
    }
    return KachePersistenceRead<T>(
      entry: KachePersistedEntry<T>(
        data: stored.data as T,
        metadata: stored.metadata,
      ),
      maintenance: maintenance,
    );
  }

  @override
  Future<void> write<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
    required KachePersistedEntry<T> entry,
  }) async {
    binding.ensureBackend(this);
    _entries[key] = _StoredEntry(entry.data, entry.metadata);
  }

  @override
  Future<void> delete({required KacheKey key}) async {
    _entries.remove(key);
  }

  @override
  Future<void> clearNamespace({required KacheNamespace namespace}) async {
    _entries.removeWhere(
      (key, _) => key.storageKey.startsWith(namespace.storagePrefix),
    );
  }

  @override
  Future<void> clear() async {
    clearCount++;
    _entries.clear();
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

final class _StoredEntry {
  const _StoredEntry(this.data, this.metadata);

  final Object? data;
  final KachePersistedMetadata metadata;
}

final class _Profile {
  const _Profile(this.name);

  final String name;
}

final class _SensitiveCause {
  _SensitiveCause(this.secret);

  final String secret;
  bool wasRendered = false;

  @override
  String toString() {
    wasRendered = true;
    return secret;
  }
}

KachePersistenceBindingException _captureBindingException(
  void Function() action,
) {
  try {
    action();
  } on KachePersistenceBindingException catch (error) {
    return error;
  }
  fail('Expected KachePersistenceBindingException.');
}

ArgumentError _captureArgumentError(void Function() action) {
  try {
    action();
  } on ArgumentError catch (error) {
    return error;
  }
  fail('Expected ArgumentError.');
}
