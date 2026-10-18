import 'dart:async';

import 'package:flutter/widgets.dart';
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
    await source.checked.future;

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

  test('only an all-none result maps to unavailable', () async {
    final source = _FakeConnectivity(
      initial: <ConnectivityResult>[ConnectivityResult.none],
    );
    final network = ConnectivityPlusNetwork(connectivity: source);
    final states = <KacheNetworkState>[];
    final subscription = network.states.listen(states.add);
    await source.checked;
    await pumpEventQueue();

    source.emit(<ConnectivityResult>[
      ConnectivityResult.wifi,
      ConnectivityResult.none,
    ]);
    source.emit(<ConnectivityResult>[
      ConnectivityResult.none,
      ConnectivityResult.none,
    ]);
    await pumpEventQueue();

    expect(states, <KacheNetworkState>[
      KacheNetworkState.unavailable,
      KacheNetworkState.available,
      KacheNetworkState.unavailable,
    ]);
    await subscription.cancel();
    await network.close();
  });

  test('a flapping storm emits only strict alternations', () async {
    final source = _FakeConnectivity(
      initial: <ConnectivityResult>[ConnectivityResult.wifi],
    );
    final network = ConnectivityPlusNetwork(connectivity: source);
    final states = <KacheNetworkState>[];
    final subscription = network.states.listen(states.add);
    await source.checked;
    await pumpEventQueue();

    const interfaces = <ConnectivityResult>[
      ConnectivityResult.wifi,
      ConnectivityResult.mobile,
      ConnectivityResult.vpn,
    ];
    for (var index = 0; index < 300; index++) {
      source.emit(<ConnectivityResult>[interfaces[index % 3]]);
      if (index % 3 == 2) {
        source.emit(<ConnectivityResult>[ConnectivityResult.none]);
        source.emit(<ConnectivityResult>[ConnectivityResult.none]);
      }
    }
    await pumpEventQueue();

    // The first cycle starts on the already-available state.
    expect(states, hasLength(200));
    for (var index = 0; index < states.length; index++) {
      expect(
        states[index],
        index.isEven
            ? KacheNetworkState.available
            : KacheNetworkState.unavailable,
      );
    }
    await subscription.cancel();
    await network.close();
  });

  test('a subscriber after a failed check retries and receives state',
      () async {
    final source = _FakeConnectivity(
      initialError: StateError('check failed'),
      onCheck: () async => <ConnectivityResult>[ConnectivityResult.mobile],
    );
    final network = ConnectivityPlusNetwork(connectivity: source);
    final firstErrors = <Object>[];
    final first = network.states.listen((_) {}, onError: firstErrors.add);
    await source.checked;
    await pumpEventQueue();
    expect(firstErrors, hasLength(1));

    final late = await network.states.first.timeout(
      const Duration(seconds: 1),
    );

    expect(late, KacheNetworkState.available);
    expect(source.checkCount, 2);
    await first.cancel();
    await network.close();
  });

  test('a paused subscriber resumes with only the latest state', () async {
    final source = _FakeConnectivity(
      initial: <ConnectivityResult>[ConnectivityResult.wifi],
    );
    final network = ConnectivityPlusNetwork(connectivity: source);
    final states = <KacheNetworkState>[];
    final subscription = network.states.listen(states.add);
    await source.checked;
    await pumpEventQueue();

    subscription.pause();
    source.emit(<ConnectivityResult>[ConnectivityResult.none]);
    source.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
    source.emit(<ConnectivityResult>[ConnectivityResult.none]);
    await pumpEventQueue();
    subscription.resume();
    await pumpEventQueue();

    expect(states, <KacheNetworkState>[
      KacheNetworkState.available,
      KacheNetworkState.unavailable,
    ]);
    await subscription.cancel();
    await network.close();
  });

  test('a paused subscriber skips a round trip back to its state', () async {
    final source = _FakeConnectivity(
      initial: <ConnectivityResult>[ConnectivityResult.wifi],
    );
    final network = ConnectivityPlusNetwork(connectivity: source);
    final states = <KacheNetworkState>[];
    final subscription = network.states.listen(states.add);
    await source.checked;
    await pumpEventQueue();

    subscription.pause();
    source.emit(<ConnectivityResult>[ConnectivityResult.none]);
    source.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
    await pumpEventQueue();
    subscription.resume();
    await pumpEventQueue();

    expect(states, <KacheNetworkState>[KacheNetworkState.available]);
    await subscription.cancel();
    await network.close();
  });

  test('source completion before the initial check waits for it', () async {
    final initial = Completer<List<ConnectivityResult>>();
    final source = _FakeConnectivity(initialFuture: initial.future);
    final network = ConnectivityPlusNetwork(connectivity: source);
    final states = network.states.toList();
    await source.checked;

    await source.end();
    initial.complete(<ConnectivityResult>[ConnectivityResult.ethernet]);

    expect(await states, <KacheNetworkState>[KacheNetworkState.available]);
    await network.close();
  });

  test('a synchronous listen failure is reported and still checks', () async {
    final network = ConnectivityPlusNetwork(
      connectivity: _ThrowingListenConnectivity(),
    );
    final errors = <Object>[];
    final states = <KacheNetworkState>[];
    final done = Completer<void>();
    network.states.listen(
      states.add,
      onError: errors.add,
      onDone: done.complete,
    );

    await done.future.timeout(const Duration(seconds: 1));

    expect(errors.single, isA<UnsupportedError>());
    expect(states, <KacheNetworkState>[KacheNetworkState.unavailable]);
    await network.close();
  });

  test('streams after close are broadcast like live streams', () async {
    final network = ConnectivityPlusNetwork(connectivity: _FakeConnectivity());
    expect(network.states.isBroadcast, isTrue);
    await network.close();
    expect(network.states.isBroadcast, isTrue);
  });

  group('app resume', () {
    late TestWidgetsFlutterBinding binding;

    setUp(() {
      binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    void background() {
      binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
    }

    void foreground() {
      binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    test('re-checks and recovers a change missed in the background', () async {
      var current = <ConnectivityResult>[ConnectivityResult.none];
      final source = _FakeConnectivity(
        initial: current,
        onCheck: () async => current,
      );
      final network = ConnectivityPlusNetwork(
        connectivity: source,
        binding: binding,
      );
      final states = <KacheNetworkState>[];
      final subscription = network.states.listen(states.add);
      await source.checked;
      await pumpEventQueue();

      background();
      current = <ConnectivityResult>[ConnectivityResult.wifi];
      foreground();
      await pumpEventQueue();

      expect(source.checkCount, 2);
      expect(states, <KacheNetworkState>[
        KacheNetworkState.unavailable,
        KacheNetworkState.available,
      ]);
      await subscription.cancel();
      await network.close();
    });

    test('a change during the resume check wins over its result', () async {
      final resumeCheck = Completer<List<ConnectivityResult>>();
      final source = _FakeConnectivity(
        initial: <ConnectivityResult>[ConnectivityResult.wifi],
        onCheck: () => resumeCheck.future,
      );
      final network = ConnectivityPlusNetwork(
        connectivity: source,
        binding: binding,
      );
      final states = <KacheNetworkState>[];
      final subscription = network.states.listen(states.add);
      await source.checked;
      await pumpEventQueue();

      background();
      foreground();
      source.emit(<ConnectivityResult>[ConnectivityResult.none]);
      resumeCheck.complete(<ConnectivityResult>[ConnectivityResult.wifi]);
      await pumpEventQueue();

      expect(states, <KacheNetworkState>[
        KacheNetworkState.available,
        KacheNetworkState.unavailable,
      ]);
      await subscription.cancel();
      await network.close();
    });

    test('an unchanged resume check emits nothing', () async {
      final source = _FakeConnectivity(
        initial: <ConnectivityResult>[ConnectivityResult.wifi],
      );
      final network = ConnectivityPlusNetwork(
        connectivity: source,
        binding: binding,
      );
      final states = <KacheNetworkState>[];
      final subscription = network.states.listen(states.add);
      await source.checked;
      await pumpEventQueue();

      background();
      foreground();
      await pumpEventQueue();

      expect(source.checkCount, 2);
      expect(states, <KacheNetworkState>[KacheNetworkState.available]);
      await subscription.cancel();
      await network.close();
    });

    test('close stops resume checks', () async {
      final source = _FakeConnectivity(
        initial: <ConnectivityResult>[ConnectivityResult.wifi],
      );
      final network = ConnectivityPlusNetwork(
        connectivity: source,
        binding: binding,
      );
      await network.states.first;
      await network.close();

      background();
      foreground();
      await pumpEventQueue();

      expect(source.checkCount, 1);
    });

    test('an injected source without a binding never observes it', () async {
      final source = _FakeConnectivity(
        initial: <ConnectivityResult>[ConnectivityResult.wifi],
      );
      final network = ConnectivityPlusNetwork(connectivity: source);
      final subscription = network.states.listen((_) {});
      await source.checked;

      background();
      foreground();
      await pumpEventQueue();

      expect(source.checkCount, 1);
      await subscription.cancel();
      await network.close();
    });
  });
}

final class _ThrowingListenConnectivity implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      const <ConnectivityResult>[ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      throw UnsupportedError('no event channel');
}

final class _FakeConnectivity implements Connectivity {
  _FakeConnectivity({
    List<ConnectivityResult>? initial,
    Future<List<ConnectivityResult>>? initialFuture,
    Object? initialError,
    this.onCheck,
  }) : _initial = initialFuture ??
            (initialError == null
                ? Future<List<ConnectivityResult>>.value(
                    initial ??
                        const <ConnectivityResult>[ConnectivityResult.none],
                  )
                : Future<List<ConnectivityResult>>.error(initialError)) {
    _initial.ignore();
  }

  final Future<List<ConnectivityResult>> _initial;

  /// Answers every check after the first one; defaults to the initial answer.
  Future<List<ConnectivityResult>> Function()? onCheck;
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
      return _initial;
    }
    final answer = onCheck;
    return answer == null ? _initial : answer();
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
