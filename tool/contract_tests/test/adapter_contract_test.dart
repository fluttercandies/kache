import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache/kache.dart';
import 'package:kache_bloc/kache_bloc.dart' show KacheCubit;
import 'package:kache_flutter/kache_flutter.dart'
    show KacheBuilder, KacheController, KacheScope;
import 'package:kache_provider/kache_provider.dart'
    show KacheConsumer, KacheProvider;
import 'package:kache_riverpod/kache_riverpod.dart'
    show KacheNotifier, kacheProvider;
import 'package:riverpod/riverpod.dart';

import 'support/adapter_contract.dart';

void main() {
  runAdapterContract(const <AdapterHarnessFactory>[
    AdapterHarnessFactory(name: 'Flutter', create: _FlutterHarness.create),
    AdapterHarnessFactory(name: 'Riverpod', create: _RiverpodHarness.create),
    AdapterHarnessFactory(name: 'Bloc/Cubit', create: _CubitHarness.create),
    AdapterHarnessFactory(name: 'Provider', create: _ProviderHarness.create),
  ]);
}

final class _FlutterHarness implements AdapterContractHarness {
  _FlutterHarness(this._tester, this._client, this._query);

  static Future<_FlutterHarness> create(
    WidgetTester tester,
    KacheClient client,
    KacheQuery<int> query,
  ) async {
    final harness = _FlutterHarness(tester, client, query);
    await harness._mount();
    return harness;
  }

  final WidgetTester _tester;
  final KacheClient _client;
  KacheQuery<int> _query;
  late KacheController<int> _controller;

  @override
  KacheSnapshot<int> get snapshot => _controller.value;

  @override
  Future<KacheSnapshot<int>> refresh() => _controller.refresh();

  @override
  Future<KacheSnapshot<int>> invalidate({required bool refetch}) =>
      _controller.invalidate(refetch: refetch);

  @override
  Future<void> replaceQuery(KacheQuery<int> query) async {
    _query = query;
    await _mount();
  }

  @override
  Future<void> resume() async {
    _tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    _tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle();
  }

  @override
  Future<void> settle() async {
    await _tester.pump();
    await _tester.pump();
  }

  @override
  Future<void> dispose() async {
    await _tester.pumpWidget(const SizedBox());
    await _tester.pump();
  }

  Future<void> _mount() => _tester.pumpWidget(
    KacheScope(
      client: _client,
      child: KacheBuilder<int>(
        query: _query,
        builder: (context, snapshot, controller) {
          _controller = controller;
          return const SizedBox();
        },
      ),
    ),
  );
}

final class _ProviderHarness implements AdapterContractHarness {
  _ProviderHarness(this._tester, this._client, this._query);

  static Future<_ProviderHarness> create(
    WidgetTester tester,
    KacheClient client,
    KacheQuery<int> query,
  ) async {
    final harness = _ProviderHarness(tester, client, query);
    await harness._mount();
    return harness;
  }

  final WidgetTester _tester;
  final KacheClient _client;
  KacheQuery<int> _query;
  late KacheController<int> _controller;

  @override
  KacheSnapshot<int> get snapshot => _controller.value;

  @override
  Future<KacheSnapshot<int>> refresh() => _controller.refresh();

  @override
  Future<KacheSnapshot<int>> invalidate({required bool refetch}) =>
      _controller.invalidate(refetch: refetch);

  @override
  Future<void> replaceQuery(KacheQuery<int> query) async {
    _query = query;
    await _mount();
  }

  @override
  Future<void> resume() async {
    _tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    _tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle();
  }

  @override
  Future<void> settle() async {
    await _tester.pump();
    await _tester.pump();
  }

  @override
  Future<void> dispose() async {
    await _tester.pumpWidget(const SizedBox());
    await _tester.pump();
  }

  Future<void> _mount() => _tester.pumpWidget(
    KacheScope(
      client: _client,
      child: KacheProvider<int>(
        query: _query,
        child: KacheConsumer<int>(
          builder: (context, snapshot, controller, child) {
            _controller = controller;
            return const SizedBox();
          },
        ),
      ),
    ),
  );
}

final class _RiverpodHarness implements AdapterContractHarness {
  _RiverpodHarness(this._tester, this._client, this._query) {
    _bind();
  }

  static Future<_RiverpodHarness> create(
    WidgetTester tester,
    KacheClient client,
    KacheQuery<int> query,
  ) async => _RiverpodHarness(tester, client, query);

  final WidgetTester _tester;
  final KacheClient _client;
  final ProviderContainer _container = ProviderContainer();
  late final _family = kacheProvider.autoDispose.family<int, KacheQuery<int>>(
    client: (ref) => _client,
    query: (ref, query) => query,
  );
  KacheQuery<int> _query;
  late ProviderSubscription<KacheSnapshot<int>> _subscription;

  @override
  KacheSnapshot<int> get snapshot => _subscription.read();

  KacheNotifier<int> get _notifier => _container.read(_family(_query).notifier);

  @override
  Future<KacheSnapshot<int>> refresh() => _notifier.refresh();

  @override
  Future<KacheSnapshot<int>> invalidate({required bool refetch}) =>
      _notifier.invalidate(refetch: refetch);

  @override
  Future<void> replaceQuery(KacheQuery<int> query) async {
    _subscription.close();
    await _tester.pump();
    _query = query;
    _bind();
  }

  @override
  Future<void> resume() async {
    await _client.revalidateOnResume();
    await settle();
  }

  @override
  Future<void> settle() async {
    await _tester.pump();
    await _tester.pump();
  }

  @override
  Future<void> dispose() async {
    _subscription.close();
    await _tester.pump();
    _container.dispose();
  }

  void _bind() {
    _subscription = _container.listen(
      _family(_query),
      (previous, next) {},
      fireImmediately: true,
    );
  }
}

final class _CubitHarness implements AdapterContractHarness {
  _CubitHarness(this._tester, this._client, KacheQuery<int> query)
    : _cubit = KacheCubit<int>(client: _client, query: query);

  static Future<_CubitHarness> create(
    WidgetTester tester,
    KacheClient client,
    KacheQuery<int> query,
  ) async => _CubitHarness(tester, client, query);

  final WidgetTester _tester;
  final KacheClient _client;
  late KacheCubit<int> _cubit;

  @override
  KacheSnapshot<int> get snapshot => _cubit.state;

  @override
  Future<KacheSnapshot<int>> refresh() => _cubit.refresh();

  @override
  Future<KacheSnapshot<int>> invalidate({required bool refetch}) =>
      _cubit.invalidate(refetch: refetch);

  @override
  Future<void> replaceQuery(KacheQuery<int> query) async {
    await _tester.runAsync(_cubit.close);
    _cubit = KacheCubit<int>(client: _client, query: query);
  }

  @override
  Future<void> resume() async {
    await _client.revalidateOnResume();
    await settle();
  }

  @override
  Future<void> settle() async {
    await _tester.pump();
    await _tester.pump();
  }

  @override
  Future<void> dispose() async {
    await _tester.runAsync(_cubit.close);
  }
}
