part of 'store.dart';

/// Default encoded size at which byte-codec work leaves the caller's isolate.
///
/// Measured on JSON list payloads: below 64 KiB, inline decode and encode stay
/// well under one millisecond on desktop hardware, while an isolate round trip
/// adds roughly 0.3 to 0.9 ms of latency. Above it, inline work grows linearly
/// into multi-frame stalls on mobile hardware.
const int _defaultIsolateThreshold = 64 * 1024;

int? _validateIsolateThreshold(int? threshold) {
  if (threshold != null && threshold < 0) {
    throw ArgumentError.value(
      threshold,
      'isolateThreshold',
      'Must be null or a non-negative byte count.',
    );
  }
  return threshold;
}

extension _HiveCeCodecRunner on HiveCeKacheStore {
  bool _shouldOffload(int estimatedBytes, Object codec) {
    final threshold = isolateThreshold;
    return supportsBackgroundWork &&
        threshold != null &&
        estimatedBytes >= threshold &&
        !_inlineCodecs.contains(codec);
  }

  /// Estimates a write's record size before encoding it.
  ///
  /// Uses the larger of the record currently stored for the key and the last
  /// record observed for the codec. Without evidence the write stays inline.
  int _estimateWriteBytes(String physicalKey, String codecId) {
    final current = box.get(physicalKey);
    final stored = current is Uint8List ? current.length : 0;
    final observed = _recordSizeHints[codecId] ?? 0;
    return stored > observed ? stored : observed;
  }

  /// Decodes the payload of [raw] with the current codec or the migrator.
  Future<T> _decodePayload<T>(
    HiveCeBinding<T> binding,
    Uint8List raw,
    HiveCeEnvelopeHeader header,
  ) async {
    final isCurrent = header.codecId == binding.codecId;
    final stage = isCurrent
        ? KachePersistenceStage.decode
        : KachePersistenceStage.migration;
    final migrate = binding.migrate;
    if (!isCurrent && migrate == null) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: KachePersistenceStage.migration,
        cause: StateError('No migration is configured for the stored codec.'),
        stackTrace: StackTrace.current,
      );
    }
    _recordSizeHints[header.codecId] = raw.length;
    final decode = binding.codec.decode;
    final fromCodecId = header.codecId;
    final offset = header.payloadOffset;
    try {
      if (_shouldOffload(raw.length, binding.codec)) {
        try {
          return await runInBackground<T>(
            isCurrent
                ? _backgroundDecode<T>(raw, offset, decode)
                : _backgroundMigrate<T>(raw, offset, migrate!, fromCodecId),
          );
        } on BackgroundWorkUnavailable {
          _inlineCodecs.add(binding.codec);
        }
      }
      // The Hive frame value is shared box memory, so codecs receive a copy.
      final payload = raw.sublist(offset);
      return isCurrent ? decode(payload) : migrate!(payload, fromCodecId);
    } on Object catch (error, stackTrace) {
      _throwPersistence(
        operation: KachePersistenceOperation.read,
        stage: stage,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Encodes [entry] into a complete record for [binding].
  ///
  /// Codec failures use [stage] for [operation]; envelope limits are reported
  /// at the same stage because the encoded payload caused them.
  FutureOr<Uint8List> _encodeRecord<T>(
    HiveCeBinding<T> binding,
    KachePersistedEntry<T> entry, {
    required int estimatedBytes,
    required KachePersistenceOperation operation,
    required KachePersistenceStage stage,
  }) {
    final encode = binding.codec.encode;
    final codecId = binding.codecId;
    final fetchedAt = entry.metadata.fetchedAt;
    final isInvalidated = entry.metadata.isInvalidated;
    Uint8List encodeInline() {
      final record = _encodeEnvelope<T>(
        encode,
        entry.data,
        codecId,
        fetchedAt,
        isInvalidated,
      );
      _recordSizeHints[codecId] = record.length;
      return record;
    }

    Never fail(Object error, StackTrace stackTrace) => _throwPersistence(
          operation: operation,
          stage: stage,
          cause: error,
          stackTrace: stackTrace,
        );

    if (!_shouldOffload(estimatedBytes, binding.codec)) {
      try {
        return encodeInline();
      } on Object catch (error, stackTrace) {
        fail(error, stackTrace);
      }
    }
    return () async {
      try {
        try {
          final record = await runInBackground<Uint8List>(
            _backgroundEncode<T>(
              encode,
              entry.data,
              codecId,
              fetchedAt,
              isInvalidated,
            ),
          );
          _recordSizeHints[codecId] = record.length;
          return record;
        } on BackgroundWorkUnavailable {
          _inlineCodecs.add(binding.codec);
        }
        return encodeInline();
      } on Object catch (error, stackTrace) {
        fail(error, stackTrace);
      }
    }();
  }

  /// Waits for every keyed operation that is still encoding or storing.
  Future<void> _drainPendingWrites() async {
    while (_pendingWrites.isNotEmpty) {
      await Future.wait<void>(_pendingWrites.values.toList(growable: false));
    }
  }

  /// Runs [action] after every earlier pending operation on [physicalKey].
  ///
  /// Used only when an operation must wait, so inline writes with nothing
  /// pending keep their synchronous start. The returned future reports the
  /// action's own failure; the ordering chain itself never fails.
  Future<void> _runInOrder(
    String physicalKey,
    Future<void> Function() action,
  ) {
    final previous = _pendingWrites[physicalKey];
    final operation =
        previous == null ? action() : previous.then<void>((_) => action());
    late final Future<void> tail;
    tail = operation
        .then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    )
        .whenComplete(() {
      if (identical(_pendingWrites[physicalKey], tail)) {
        _pendingWrites.remove(physicalKey);
      }
    });
    _pendingWrites[physicalKey] = tail;
    return operation;
  }
}

T Function() _backgroundDecode<T>(
  Uint8List raw,
  int offset,
  T Function(Uint8List bytes) decode,
) =>
    // The worker owns its copy of [raw], so a view satisfies the owned-bytes
    // codec contract without another copy.
    () => decode(Uint8List.sublistView(raw, offset));

T Function() _backgroundMigrate<T>(
  Uint8List raw,
  int offset,
  HiveCeMigrator<T> migrate,
  String fromCodecId,
) =>
    () => migrate(Uint8List.sublistView(raw, offset), fromCodecId);

Uint8List Function() _backgroundEncode<T>(
  Uint8List Function(T value) encode,
  T value,
  String codecId,
  DateTime fetchedAt,
  bool isInvalidated,
) =>
    () => _encodeEnvelope<T>(encode, value, codecId, fetchedAt, isInvalidated);

Uint8List _encodeEnvelope<T>(
  Uint8List Function(T value) encode,
  T value,
  String codecId,
  DateTime fetchedAt,
  bool isInvalidated,
) =>
    HiveCeEnvelope.encode(
      fetchedAt: fetchedAt,
      isInvalidated: isInvalidated,
      codecId: codecId,
      payload: encode(value),
    );
