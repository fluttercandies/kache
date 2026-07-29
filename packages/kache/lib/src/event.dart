part of 'client.dart';

/// Stable operation types emitted by [KacheClient.events].
enum KacheEventKind {
  /// A memory or persistence cache lookup completed.
  lookup,

  /// A query fetcher was invoked.
  fetch,

  /// A persistence value was read.
  read,

  /// A value or migration was written to persistence.
  write,

  /// A persisted value was deleted.
  delete,

  /// Data was set or atomically updated.
  set,

  /// A key was explicitly invalidated.
  invalidate,

  /// A key was explicitly removed.
  remove,

  /// A namespace or the complete cache was cleared.
  clear,

  /// The configured network source changed or failed.
  network,

  /// Network recovery revalidation ran.
  reconnect,

  /// The client or one of its owned dependencies closed.
  close,
}

/// Lifecycle phase of a [KacheEvent].
enum KacheEventPhase {
  /// The operation started after its observable state was committed.
  started,

  /// The operation completed successfully.
  succeeded,

  /// The operation completed with [KacheEvent.failure].
  failed,

  /// The operation was superseded for [KacheEvent.cancelReason].
  cancelled,
}

/// The command or lifecycle transition that initiated an event trace.
enum KacheEventTrigger {
  /// A resource load.
  load,

  /// An explicit resource refresh.
  refresh,

  /// A client prefetch.
  prefetch,

  /// An interval refresh.
  poll,

  /// Foreground resume revalidation.
  resume,

  /// A state or failure from the configured network source.
  network,

  /// Network recovery revalidation.
  reconnect,

  /// Revalidation requested by a clear command.
  clearRefetch,

  /// A set-data command.
  set,

  /// An atomic update-data command.
  update,

  /// An invalidate command and its optional fetch.
  invalidate,

  /// A remove command.
  remove,

  /// A namespace or global clear command.
  clear,

  /// A client close command.
  close,

  /// Persistence maintenance initiated by a read.
  maintenance,
}

/// The component involved in an event.
enum KacheLayer {
  /// The active in-process entry registry.
  memory,

  /// The configured persistence backend.
  persistence,

  /// The configured network state source.
  network,
}

/// Outcome of a cache [KacheEventKind.lookup].
enum KacheLookupResult {
  /// Usable data was found.
  hit,

  /// No data was found.
  miss,

  /// Data was found but had reached its hard expiry.
  expired,
}

/// An immutable cache operation event.
///
/// Events are trusted in-process objects: successful data operations may expose
/// their original value through [requireData]. Kache never logs or uploads
/// events, and [toString] intentionally omits keys, metadata, data, causes, and
/// stack traces. Applications control filtering, redaction, mapping, and
/// export when subscribing to [KacheClient.events].
final class KacheEvent {
  KacheEvent._({
    required this.clientId,
    required this.sequence,
    required this.traceId,
    required this.id,
    required this.parentId,
    required this.kind,
    required this.phase,
    required this.trigger,
    required this.occurredAt,
    required this.duration,
    required this.key,
    required this.namespace,
    required this.debugName,
    required this.metadata,
    required this.layer,
    required this.lookup,
    required this.networkState,
    required this.failure,
    required this.cancelReason,
    required this.revision,
    required Object? data,
  }) : _data = data {
    _validate();
  }

  /// Stable identity of the client that emitted this event.
  final String clientId;

  /// Monotonically increasing emission order within [clientId].
  final int sequence;

  /// Correlates every span initiated by one command or lifecycle action.
  final String traceId;

  /// Correlates one started event with its terminal event.
  final String id;

  /// The direct parent span, or `null` for the trace root.
  final String? parentId;

  /// The operation represented by this event.
  final KacheEventKind kind;

  /// Current lifecycle phase of [kind].
  final KacheEventPhase phase;

  /// What initiated this event trace.
  final KacheEventTrigger trigger;

  /// UTC wall-clock time at which this event was emitted.
  final DateTime occurredAt;

  /// Elapsed monotonic time for terminal events, otherwise `null`.
  final Duration? duration;

  /// Affected key for key-scoped events.
  final KacheKey? key;

  /// Affected namespace for namespace-scoped events.
  final KacheNamespace? namespace;

  /// Optional query label supplied by the initiating handle.
  final String? debugName;

  /// Immutable query context supplied by the initiating handle.
  final Map<String, Object?> metadata;

  /// Component involved in this operation, when meaningful.
  final KacheLayer? layer;

  /// Lookup outcome for [KacheEventKind.lookup], otherwise `null`.
  final KacheLookupResult? lookup;

  /// Latest state for a successful [KacheEventKind.network] event.
  final KacheNetworkState? networkState;

  /// Classified error for [KacheEventPhase.failed].
  final KacheFailure? failure;

  /// Cancellation reason for [KacheEventPhase.cancelled].
  final KacheCancelReason? cancelReason;

  /// Snapshot revision visible when this event was emitted, when applicable.
  final int? revision;

  final Object? _data;

  /// Whether this event contains data, including a nullable `null` value.
  bool get hasData => !identical(_data, _noEventData);

  /// The contained data, or `null` when absent or when the data itself is null.
  Object? get dataOrNull => hasData ? _data : null;

  /// Returns the contained data as [T].
  ///
  /// Throws [StateError] when this event has no data and propagates the normal
  /// Dart cast error when the requested type does not match.
  T requireData<T>() {
    if (!hasData) {
      throw StateError('KacheEvent has no data.');
    }
    return _data as T;
  }

  /// The non-sensitive operation scope.
  KacheFailureScope get scope => key != null
      ? KacheFailureScope.key
      : namespace != null
          ? KacheFailureScope.namespace
          : KacheFailureScope.global;

  /// Whether this event completes an operation span.
  bool get isTerminal => phase != KacheEventPhase.started;

  void _validate() {
    if (clientId.isEmpty || traceId.isEmpty || id.isEmpty || sequence < 1) {
      throw StateError('Invalid Kache event identity.');
    }
    if (!occurredAt.isUtc || key != null && namespace != null) {
      throw StateError('Invalid Kache event context.');
    }
    if (parentId == id) {
      throw StateError('A Kache event cannot parent itself.');
    }
    if (phase == KacheEventPhase.started) {
      if (duration != null || failure != null || cancelReason != null) {
        throw StateError('A started event cannot contain terminal fields.');
      }
    } else if (duration == null || duration!.isNegative) {
      throw StateError('A terminal event requires a non-negative duration.');
    }
    if ((phase == KacheEventPhase.failed) != (failure != null)) {
      throw StateError('Only failed events require a failure.');
    }
    if ((phase == KacheEventPhase.cancelled) != (cancelReason != null)) {
      throw StateError('Only cancelled events require a cancellation reason.');
    }
    final allowsData = phase == KacheEventPhase.succeeded &&
        (kind == KacheEventKind.lookup ||
            kind == KacheEventKind.fetch ||
            kind == KacheEventKind.read ||
            kind == KacheEventKind.write ||
            kind == KacheEventKind.set);
    if (hasData && !allowsData) {
      throw StateError('This Kache event cannot contain data.');
    }
    if (kind == KacheEventKind.lookup) {
      if (key == null ||
          lookup == null ||
          layer != KacheLayer.memory && layer != KacheLayer.persistence ||
          phase == KacheEventPhase.started ||
          phase == KacheEventPhase.cancelled) {
        throw StateError('Invalid cache lookup event.');
      }
      if ((lookup == KacheLookupResult.hit) != hasData) {
        throw StateError('Only cache hits contain data.');
      }
    } else if (lookup != null) {
      throw StateError('Only lookup events have lookup results.');
    }
    if (kind == KacheEventKind.network) {
      if (layer != KacheLayer.network || key != null || namespace != null) {
        throw StateError('Invalid network event.');
      }
      if ((phase == KacheEventPhase.succeeded) != (networkState != null)) {
        throw StateError('Only successful network events contain state.');
      }
    } else if (networkState != null) {
      throw StateError('Only network events contain network state.');
    }
    if ((kind == KacheEventKind.read ||
            kind == KacheEventKind.write ||
            kind == KacheEventKind.delete) &&
        layer != KacheLayer.persistence) {
      throw StateError('Persistence events require the persistence layer.');
    }
    if (layer == KacheLayer.network &&
        kind != KacheEventKind.network &&
        kind != KacheEventKind.close) {
      throw StateError('The network layer is invalid for this event.');
    }
  }

  @override
  String toString() => 'KacheEvent('
      'kind: ${kind.name}, phase: ${phase.name}, '
      'trigger: ${trigger.name}, scope: ${scope.name}, '
      'layer: ${layer?.name}, hasData: $hasData, '
      'hasFailure: ${failure != null})';
}

/// Receives cache events synchronously after related state is committed.
typedef KacheObserver = void Function(KacheEvent event);

const Object _noEventData = Object();

final class _KacheEventContext {
  const _KacheEventContext({
    this.key,
    this.namespace,
    this.debugName,
    this.metadata = const <String, Object?>{},
  });

  final KacheKey? key;
  final KacheNamespace? namespace;
  final String? debugName;
  final Map<String, Object?> metadata;
}

final class _KacheTrace {
  _KacheTrace({
    required this.client,
    required this.id,
    required this.trigger,
    required this.context,
  });

  final KacheClient client;
  final String id;
  final KacheEventTrigger trigger;
  final _KacheEventContext context;
  String? _rootId;

  _KacheEventSpan span(
    KacheEventKind kind, {
    KacheLayer? layer,
    _KacheEventContext? context,
  }) {
    final isRoot = _rootId == null;
    final spanId = isRoot ? id : client._nextEventId();
    final parentId = isRoot ? null : _rootId;
    _rootId ??= spanId;
    return _KacheEventSpan._(
      trace: this,
      id: spanId,
      parentId: parentId,
      kind: kind,
      layer: layer,
      context: context ?? this.context,
    );
  }
}

final class _KacheEventSpan {
  _KacheEventSpan._({
    required this.trace,
    required this.id,
    required this.parentId,
    required this.kind,
    required this.layer,
    required this.context,
  });

  final _KacheTrace trace;
  final String id;
  final String? parentId;
  final KacheEventKind kind;
  final KacheLayer? layer;
  final _KacheEventContext context;
  final Stopwatch _stopwatch = Stopwatch();
  bool _started = false;
  bool _ended = false;

  void start({int? revision}) {
    if (_started || _ended) {
      throw StateError('A Kache event span can only start once.');
    }
    _started = true;
    _stopwatch.start();
    _emit(KacheEventPhase.started, revision: revision);
  }

  void succeed({
    KacheLookupResult? lookup,
    KacheNetworkState? networkState,
    int? revision,
    Object? data = _noEventData,
  }) =>
      _finish(
        KacheEventPhase.succeeded,
        lookup: lookup,
        networkState: networkState,
        revision: revision,
        data: data,
      );

  void fail(KacheFailure failure, {KacheLookupResult? lookup, int? revision}) =>
      _finish(
        KacheEventPhase.failed,
        lookup: lookup,
        failure: failure,
        revision: revision,
      );

  void cancel(KacheCancelReason reason, {int? revision}) => _finish(
        KacheEventPhase.cancelled,
        cancelReason: reason,
        revision: revision,
      );

  void _finish(
    KacheEventPhase phase, {
    KacheLookupResult? lookup,
    KacheNetworkState? networkState,
    KacheFailure? failure,
    KacheCancelReason? cancelReason,
    int? revision,
    Object? data = _noEventData,
  }) {
    if (_ended) {
      throw StateError('A Kache event span can only terminate once.');
    }
    _ended = true;
    if (_started) {
      _stopwatch.stop();
    }
    _emit(
      phase,
      duration: _started ? _stopwatch.elapsed : Duration.zero,
      lookup: lookup,
      networkState: networkState,
      failure: failure,
      cancelReason: cancelReason,
      revision: revision,
      data: data,
    );
  }

  void _emit(
    KacheEventPhase phase, {
    Duration? duration,
    KacheLookupResult? lookup,
    KacheNetworkState? networkState,
    KacheFailure? failure,
    KacheCancelReason? cancelReason,
    int? revision,
    Object? data = _noEventData,
  }) {
    trace.client._dispatchEvent(
      traceId: trace.id,
      id: id,
      parentId: parentId,
      kind: kind,
      phase: phase,
      trigger: trace.trigger,
      duration: duration,
      context: context,
      layer: layer,
      lookup: lookup,
      networkState: networkState,
      failure: failure,
      cancelReason: cancelReason,
      revision: revision,
      data: data,
    );
  }
}
