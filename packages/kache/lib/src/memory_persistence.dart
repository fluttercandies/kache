import 'key.dart';
import 'persistence.dart';

/// An in-process, SDK-only persistence backend for typed cache entries.
///
/// Values are retained by reference and are not serialized or copied. This
/// makes the backend suitable for process-local persistence, deterministic
/// tests, and environments where callers intentionally own object mutation.
/// Entries do not survive process termination.
///
/// Each stored key is bound to the binding fingerprint and reified type used
/// for its first write. Later reads and writes for that key must use the same
/// fingerprint and type. [close] is idempotent, releases all retained values,
/// and causes every later operation other than [close] to fail.
final class MemoryKachePersistence implements KachePersistenceBackend {
  final Map<String, _MemoryPersistedRecord> _entries =
      <String, _MemoryPersistedRecord>{};
  bool _isClosed = false;

  /// Creates an opaque binding owned by this backend.
  ///
  /// [fingerprint] follows the validation and compatibility rules defined by
  /// [KachePersistenceBinding]. A binding can only be used with this exact
  /// backend instance.
  KachePersistenceBinding<T> bind<T>({required String fingerprint}) =>
      _MemoryKachePersistenceBinding<T>(
        backend: this,
        fingerprint: fingerprint,
      );

  @override
  Future<KachePersistenceRead<T>?> read<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
  }) async {
    binding.ensureBackend(this);
    _ensureOpen(KachePersistenceOperation.read);

    final record = _entries[key.storageKey];
    if (record == null) {
      return null;
    }
    _ensureCompatible<T>(
      record: record,
      binding: binding,
      operation: KachePersistenceOperation.read,
    );
    return KachePersistenceRead<T>(
      entry: KachePersistedEntry<T>(
        data: record.data as T,
        metadata: record.metadata,
      ),
    );
  }

  @override
  Future<void> write<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
    required KachePersistedEntry<T> entry,
  }) async {
    binding.ensureBackend(this);
    _ensureOpen(KachePersistenceOperation.write);

    final existing = _entries[key.storageKey];
    if (existing != null) {
      _ensureCompatible<T>(
        record: existing,
        binding: binding,
        operation: KachePersistenceOperation.write,
      );
    }
    _entries[key.storageKey] = _MemoryPersistedRecord(
      fingerprint: binding.fingerprint,
      type: T,
      data: entry.data,
      metadata: entry.metadata,
    );
  }

  @override
  Future<void> delete({required KacheKey key}) async {
    _ensureOpen(KachePersistenceOperation.delete);
    _entries.remove(key.storageKey);
  }

  @override
  Future<void> clearNamespace({required KacheNamespace namespace}) async {
    _ensureOpen(KachePersistenceOperation.clearNamespace);
    _entries.removeWhere(
      (storageKey, _) => storageKey.startsWith(namespace.storagePrefix),
    );
  }

  @override
  Future<void> clear() async {
    _ensureOpen(KachePersistenceOperation.clear);
    _entries.clear();
  }

  @override
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _entries.clear();
    _isClosed = true;
  }

  void _ensureOpen(KachePersistenceOperation operation) {
    if (_isClosed) {
      _throwBackendFailure(operation, 'Memory persistence backend is closed.');
    }
  }

  void _ensureCompatible<T>({
    required _MemoryPersistedRecord record,
    required KachePersistenceBinding<T> binding,
    required KachePersistenceOperation operation,
  }) {
    if (record.fingerprint != binding.fingerprint || record.type != T) {
      _throwBackendFailure(
        operation,
        'Memory persistence entry is incompatible with the binding.',
      );
    }
  }
}

final class _MemoryKachePersistenceBinding<T>
    extends KachePersistenceBinding<T> {
  _MemoryKachePersistenceBinding({
    required super.backend,
    required super.fingerprint,
  });
}

final class _MemoryPersistedRecord {
  const _MemoryPersistedRecord({
    required this.fingerprint,
    required this.type,
    required this.data,
    required this.metadata,
  });

  final String fingerprint;
  final Type type;
  final Object? data;
  final KachePersistedMetadata metadata;
}

Never _throwBackendFailure(
  KachePersistenceOperation operation,
  String message,
) {
  try {
    throw StateError(message);
  } on Object catch (cause, stackTrace) {
    throw KachePersistenceException(
      operation: operation,
      stage: KachePersistenceStage.backend,
      cause: cause,
      stackTrace: stackTrace,
    );
  }
}
