import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kache_connectivity_plus/kache_connectivity_plus.dart';

void main() {
  test('emits the initial check then distinct availability changes', () async {
    final source = _FakeConnectivity(
      initial: <ConnectivityResult>[ConnectivityResult.none],
    );
    final network = ConnectivityPlusNetwork(connectivity: source);
    final states = <KacheNetworkState>[];
    final subscription = network.states.listen(states.add);

    await source.checked;
    await pumpEventQueue();
    source.emit(<ConnectivityResult>[ConnectivityResult.none]);
    source.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
    source.emit(<ConnectivityResult>[
      ConnectivityResult.wifi,
      ConnectivityResult.vpn,
    ]);
    source.emit(<ConnectivityResult>[ConnectivityResult.mobile]);
    await pumpEventQueue();

    expect(states, <KacheNetworkState>[
      KacheNetworkState.unavailable,
      KacheNetworkState.available,
    ]);
    await subscription.cancel();
    await network.close();
  });

  test(
    'a change that wins the initial check race is never overwritten',
    () async {
      final initial = Completer<List<ConnectivityResult>>();
      final source = _FakeConnectivity(initialFuture: initial.future);
      final network = ConnectivityPlusNetwork(connectivity: source);
      final states = <KacheNetworkState>[];
      final subscription = network.states.listen(states.add);

      source.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
      initial.complete(<ConnectivityResult>[ConnectivityResult.none]);
      await pumpEventQueue();

      expect(states, <KacheNetworkState>[KacheNetworkState.available]);
      await subscription.cancel();
      await network.close();
    },
  );

  test('every subscription starts with the latest state', () async {
    final source = _FakeConnectivity(
      initial: <ConnectivityResult>[ConnectivityResult.wifi],
    );
    final network = ConnectivityPlusNetwork(connectivity: source);
    final first = await network.states.first;
    source.emit(<ConnectivityResult>[ConnectivityResult.none]);
    await pumpEventQueue();
    final second = await network.states.first;

    expect(first, KacheNetworkState.available);
    expect(second, KacheNetworkState.unavailable);
    expect(source.checkCount, 1);
    await network.close();
  });

  test(
    'initial and change errors remain observable without stale data',
    () async {
      final source = _FakeConnectivity(
        initialError: StateError('check failed'),
      );
      final network = ConnectivityPlusNetwork(connectivity: source);
      final errors = <Object>[];
      final states = <KacheNetworkState>[];
      final subscription = network.states.listen(
        states.add,
        onError: errors.add,
      );

      await source.checked;
      source.emitError(ArgumentError('stream failed'));
      source.emit(<ConnectivityResult>[ConnectivityResult.ethernet]);
      await pumpEventQueue();

      expect(errors, hasLength(2));
      expect(states, <KacheNetworkState>[KacheNetworkState.available]);
      await subscription.cancel();
      await network.close();
    },
  );

  test('source completion closes state subscribers', () async {
    final source = _FakeConnectivity(
      initial: <ConnectivityResult>[ConnectivityResult.wifi],
    );
    final network = ConnectivityPlusNetwork(connectivity: source);
    final states = network.states.toList();

    await source.checked;
    await source.end();

    expect(await states, <KacheNetworkState>[KacheNetworkState.available]);
    await network.close();
  });

  test(
    'an empty platform result is reported and later changes recover',
    () async {
      final source = _FakeConnectivity(initial: const <ConnectivityResult>[]);
      final network = ConnectivityPlusNetwork(connectivity: source);
      final errors = <Object>[];
      final states = <KacheNetworkState>[];
      final subscription = network.states.listen(
        states.add,
        onError: errors.add,
      );

      await source.checked;
      await pumpEventQueue();
      source.emit(<ConnectivityResult>[ConnectivityResult.mobile]);
      await pumpEventQueue();

      expect(errors.single, isA<StateError>());
      expect(states, <KacheNetworkState>[KacheNetworkState.available]);
      await subscription.cancel();
      await network.close();
    },
  );

  test('close suppresses a late initial result', () async {
    final initial = Completer<List<ConnectivityResult>>();
    final source = _FakeConnectivity(initialFuture: initial.future);
    final network = ConnectivityPlusNetwork(connectivity: source);
    final states = <KacheNetworkState>[];
    network.states.listen(states.add);

    await source.checked;
    await network.close();
    initial.complete(<ConnectivityResult>[ConnectivityResult.wifi]);
    await pumpEventQueue();

    expect(states, isEmpty);
  });

  test(
    'close is idempotent, cancels the source, and rejects later use',
    () async {
      final source = _FakeConnectivity(
        initial: <ConnectivityResult>[ConnectivityResult.wifi],
      );
      final network = ConnectivityPlusNetwork(connectivity: source);
      await network.states.first;

      await network.close();
      await network.close();
      final errors = <Object>[];
      await network.states
          .handleError((Object error) => errors.add(error))
          .drain<void>();

      expect(source.cancelCount, 1);
      expect(errors.single, isA<StateError>());
    },
  );

  test('close does not wait for a paused state subscriber', () async {
    final source = _FakeConnectivity(
      initial: <ConnectivityResult>[ConnectivityResult.wifi],
    );
    final network = ConnectivityPlusNetwork(connectivity: source);
    final done = Completer<void>();
    final subscription = network.states.listen(
      (_) {},
      onDone: done.complete,
    );
    await source.checked;
    subscription.pause();

    await network.close().timeout(const Duration(seconds: 1));
    expect(done.isCompleted, isFalse);
    expect(source.cancelCount, 1);

    subscription.resume();
    await done.future;
  });

  test('close does not wait for stalled platform cancellation', () async {
    final source = _StalledCancelConnectivity();
    final network = ConnectivityPlusNetwork(connectivity: source);
    final subscription = network.states.listen((_) {});
    source.checked;

    await network.close().timeout(const Duration(seconds: 1));

    expect(source.cancellationStarted.isCompleted, isTrue);
    await source.releaseCancellation();
    await subscription.cancel();
  });

  test(
    'a stream obtained before close still rejects a late listener',
    () async {
      final source = _FakeConnectivity(
        initial: <ConnectivityResult>[ConnectivityResult.wifi],
      );
      final network = ConnectivityPlusNetwork(connectivity: source);
      final delayedStates = network.states;
      await network.close();
      final errors = <Object>[];

      await delayedStates
          .handleError((Object error) => errors.add(error))
          .drain<void>();

      expect(errors.single, isA<StateError>());
    },
  );
  test('state listeners can close the adapter synchronously', () async {
    final source = _FakeConnectivity(
      initial: <ConnectivityResult>[ConnectivityResult.wifi],
    );
    final network = ConnectivityPlusNetwork(connectivity: source);
    final closeStarted = Completer<void>();
    late Future<void> close;
    final subscription = network.states.listen((_) {
      close = network.close();
      closeStarted.complete();
    });

    await closeStarted.future;
    await close;

    expect(source.cancelCount, 1);
    await subscription.cancel();
  });
}

final class _FakeConnectivity implements Connectivity {
  _FakeConnectivity({
    List<ConnectivityResult>? initial,
    Future<List<ConnectivityResult>>? initialFuture,
    Object? initialError,
  }) : _initial = initialFuture ??
            (initialError == null
                ? Future<List<ConnectivityResult>>.value(
                    initial ??
                        const <ConnectivityResult>[ConnectivityResult.none],
                  )
                : Future<List<ConnectivityResult>>.error(initialError));

  final Future<List<ConnectivityResult>> _initial;
  late final StreamController<List<ConnectivityResult>> _changes =
      StreamController<List<ConnectivityResult>>.broadcast(
    sync: true,
    onCancel: () => cancelCount += 1,
  );
  final Completer<void> _checked = Completer<void>();
  int checkCount = 0;
  int cancelCount = 0;

  Future<void> get checked => _checked.future;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    checkCount += 1;
    if (!_checked.isCompleted) {
      _checked.complete();
    }
    return _initial;
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;

  void emit(List<ConnectivityResult> results) => _changes.add(results);

  void emitError(Object error) => _changes.addError(error);

  Future<void> end() => _changes.close();
}

final class _StalledCancelConnectivity implements Connectivity {
  final Completer<void> checked = Completer<void>();
  final Completer<void> cancellationStarted = Completer<void>();
  final Completer<void> _cancellationGate = Completer<void>();
  late final StreamController<List<ConnectivityResult>> _changes =
      StreamController<List<ConnectivityResult>>(
    sync: true,
    onCancel: () {
      cancellationStarted.complete();
      return _cancellationGate.future;
    },
  );

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    checked.complete();
    return const <ConnectivityResult>[ConnectivityResult.wifi];
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;

  Future<void> releaseCancellation() async {
    _cancellationGate.complete();
    await _changes.close();
  }
}
