import 'package:bloc/bloc.dart';
import 'package:kache/kache.dart';

import 'binding.dart';

/// A cache-backed Cubit whose state is the complete [KacheSnapshot].
///
/// The Cubit owns its resource handle but never closes the supplied client.
/// Subclasses may add domain-specific commands while retaining cache semantics.
class KacheCubit<T> extends Cubit<KacheSnapshot<T>> {
  /// Creates a Cubit and starts loading when the resource stream is attached.
  KacheCubit({required KacheClient client, required KacheQuery<T> query})
    : this.fromBinding(KacheBlocBinding<T>(client: client, query: query));

  /// Creates a Cubit from an unattached binding.
  KacheCubit.fromBinding(this.binding) : super(binding.snapshot) {
    binding.attach(_accept);
  }

  /// The composed binding owned by this Cubit.
  final KacheBlocBinding<T> binding;

  bool _isClosing = false;
  Future<void>? _closeFuture;

  /// The core resource owned by this Cubit.
  KacheResource<T> get resource => binding.resource;

  /// The query currently bound to [resource].
  KacheQuery<T> get query => binding.query;

  /// Forces a fetch while retaining cached data according to policy.
  Future<KacheSnapshot<T>> refresh() {
    _ensureActive();
    return _run(binding.refresh());
  }

  /// Loads persistence and applies the query's load policy.
  Future<KacheSnapshot<T>> load() {
    _ensureActive();
    return _run(binding.load());
  }

  /// Replaces the current value immediately.
  Future<KacheSnapshot<T>> setData(T data) {
    _ensureActive();
    return _run(binding.setData(data));
  }

  /// Atomically updates data from the latest shared snapshot.
  Future<KacheSnapshot<T>> updateData(
    T Function(KacheSnapshot<T> snapshot) update,
  ) {
    _ensureActive();
    return _run(binding.updateData(update));
  }

  /// Marks current data stale and optionally starts a fetch.
  Future<KacheSnapshot<T>> invalidate({bool refetch = true}) {
    _ensureActive();
    return _run(binding.invalidate(refetch: refetch));
  }

  /// Removes current memory and persisted data without fetching.
  Future<KacheSnapshot<T>> remove() {
    _ensureActive();
    return _run(binding.remove());
  }

  @override
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    _isClosing = true;
    final future = _waitForClose(binding.close(), super.close());
    _closeFuture = future;
    return future;
  }

  void _accept(KacheSnapshot<T> snapshot) {
    if (_isClosing || isClosed || identical(state, snapshot)) {
      return;
    }
    emit(snapshot);
  }

  void _ensureActive() {
    if (_isClosing || isClosed) {
      throw const KacheLifecycleException(
        'cubit_closed',
        'The Kache Cubit is closed.',
      );
    }
  }

  Future<KacheSnapshot<T>> _run(Future<KacheSnapshot<T>> command) async {
    final snapshot = await command;
    _accept(snapshot);
    return snapshot;
  }

  Future<void> _waitForClose(
    Future<void> bindingClose,
    Future<void> cubitClose,
  ) async {
    await bindingClose;
    await cubitClose;
  }
}
