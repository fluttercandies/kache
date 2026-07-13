import 'package:kache/kache.dart';

final class ScriptedPersistence implements KachePersistenceBackend {
  Object? storedEntry;
  Object? readError;
  StackTrace? readStackTrace;
  Object? writeError;
  StackTrace? writeStackTrace;
  Object? deleteError;
  StackTrace? deleteStackTrace;
  KachePersistenceMaintenance? maintenance;

  int readCount = 0;
  int writeCount = 0;
  int deleteCount = 0;
  int clearNamespaceCount = 0;
  int clearCount = 0;
  int closeCount = 0;
  bool isClosed = false;

  KachePersistenceBinding<T> bind<T>({required String fingerprint}) =>
      _ScriptedBinding<T>(backend: this, fingerprint: fingerprint);

  @override
  Future<KachePersistenceRead<T>?> read<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
  }) async {
    _ensureOpen(KachePersistenceOperation.read);
    binding.ensureBackend(this);
    readCount += 1;
    final error = readError;
    if (error != null) {
      Error.throwWithStackTrace(error, readStackTrace ?? StackTrace.current);
    }
    final stored = storedEntry;
    if (stored == null) {
      return null;
    }
    return KachePersistenceRead<T>(
      entry: stored as KachePersistedEntry<T>,
      maintenance: maintenance,
    );
  }

  @override
  Future<void> write<T>({
    required KacheKey key,
    required KachePersistenceBinding<T> binding,
    required KachePersistedEntry<T> entry,
  }) async {
    _ensureOpen(KachePersistenceOperation.write);
    binding.ensureBackend(this);
    writeCount += 1;
    final error = writeError;
    if (error != null) {
      Error.throwWithStackTrace(error, writeStackTrace ?? StackTrace.current);
    }
    storedEntry = entry;
  }

  @override
  Future<void> delete({required KacheKey key}) async {
    _ensureOpen(KachePersistenceOperation.delete);
    deleteCount += 1;
    final error = deleteError;
    if (error != null) {
      Error.throwWithStackTrace(error, deleteStackTrace ?? StackTrace.current);
    }
    storedEntry = null;
  }

  @override
  Future<void> clearNamespace({required KacheNamespace namespace}) async {
    _ensureOpen(KachePersistenceOperation.clearNamespace);
    clearNamespaceCount += 1;
    storedEntry = null;
  }

  @override
  Future<void> clear() async {
    _ensureOpen(KachePersistenceOperation.clear);
    clearCount += 1;
    storedEntry = null;
  }

  @override
  Future<void> close() async {
    if (isClosed) {
      return;
    }
    closeCount += 1;
    isClosed = true;
    storedEntry = null;
  }

  void _ensureOpen(KachePersistenceOperation operation) {
    if (!isClosed) {
      return;
    }
    final cause = StateError('Scripted persistence is closed.');
    throw KachePersistenceException(
      operation: operation,
      stage: KachePersistenceStage.backend,
      cause: cause,
      stackTrace: StackTrace.current,
    );
  }
}

final class _ScriptedBinding<T> extends KachePersistenceBinding<T> {
  _ScriptedBinding({required super.backend, required super.fingerprint});
}

KachePersistenceException persistenceException({
  required KachePersistenceOperation operation,
  required KachePersistenceStage stage,
  String message = 'scripted failure',
}) {
  final cause = StateError(message);
  return KachePersistenceException(
    operation: operation,
    stage: stage,
    cause: cause,
    stackTrace: StackTrace.current,
  );
}
