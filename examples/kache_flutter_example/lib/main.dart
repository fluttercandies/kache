import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:kache_example_support/kache_example_support.dart';
import 'package:kache_flutter_hooks/kache_flutter_hooks.dart';

void main() {
  runApp(const KacheFlutterExampleApp());
}

class KacheFlutterExampleApp extends StatelessWidget {
  const KacheFlutterExampleApp({
    this.runtimeFactory,
    this.showNetworkImage = true,
    super.key,
  });

  final ExampleRuntimeFactory? runtimeFactory;
  final bool showNetworkImage;

  @override
  Widget build(BuildContext context) => KacheExampleApp(
    adapterName: 'Flutter',
    boxName: 'kache_flutter_example_repository_v1',
    runtimeFactory: runtimeFactory,
    builder: (context, runtime) => KachePlayground(
      adapterName: 'Flutter',
      repository: (context) => _FlutterRepository(
        runtime: runtime,
        showNetworkImage: showNetworkImage,
      ),
      slots: PlaygroundSlots(
        persistence: (context) => PersistencePlaygroundHost(
          runtime: runtime,
          boxPrefix: 'kache_flutter_example',
        ),
        commands: (context) => _FlutterCommandsTab(
          runtime: runtime,
          showNetworkImage: showNetworkImage,
        ),
        policies: (context) => _FlutterPoliciesTab(runtime: runtime),
        activity: (context) => ActivityPlayground(
          client: runtime.client,
          peekQuery: runtime.query,
        ),
      ),
    ),
  );
}

final class _FlutterRepository extends HookWidget {
  const _FlutterRepository({
    required this.runtime,
    required this.showNetworkImage,
  });

  final ExampleRuntime runtime;
  final bool showNetworkImage;

  @override
  Widget build(BuildContext context) {
    final cache = useKache(runtime.query);
    return RepositoryDashboard(
      adapterName: 'Flutter Hooks',
      snapshot: cache.snapshot,
      onRefresh: cache.refresh,
      onClear: cache.remove,
      showNetworkImage: showNetworkImage,
      compact: true,
    );
  }
}

/// Demonstrates [KacheBuilder] + [KacheController] commands + [KacheListener]
/// side effects + [KacheController.updateQuery].
final class _FlutterCommandsTab extends StatefulWidget {
  const _FlutterCommandsTab({
    required this.runtime,
    required this.showNetworkImage,
  });

  final ExampleRuntime runtime;
  final bool showNetworkImage;

  @override
  State<_FlutterCommandsTab> createState() => _FlutterCommandsTabState();
}

final class _FlutterCommandsTabState extends State<_FlutterCommandsTab> {
  late KacheController<RepositoryProfile> _controller;
  bool _usingCacheFirst = false;

  @override
  void initState() {
    super.initState();
    _controller = KacheController<RepositoryProfile>(
      client: widget.runtime.client,
      query: widget.runtime.query,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final snapshot = _controller.value;
        // KacheListener fires only on phase transitions, independent of build.
        return KacheListener<RepositoryProfile>(
          controller: _controller,
          listenWhen: (previous, current) => previous.phase != current.phase,
          listener: _onPhaseChanged,
          child: CommandPlayground(
            snapshot: snapshot,
            leading: Tooltip(
              message: 'controller.updateQuery(...): rebind to a new query',
              child: ActionChip(
                avatar: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text(
                  _usingCacheFirst
                      ? 'Rebind → SWR (current: cacheFirst)'
                      : 'Rebind → cacheFirst (current: SWR)',
                ),
                onPressed: _togglePolicy,
              ),
            ),
            commands: PlaygroundCommandSet(
              load: _controller.load,
              refresh: _controller.refresh,
              setData: () =>
                  _controller.setData(_bumpStars(snapshot.requireData)),
              updateData: () => _controller.updateData(
                (previous) => _bumpStars(previous.requireData),
              ),
              invalidate: () => _controller.invalidate(),
              invalidateNoRefetch: () => _controller.invalidate(refetch: false),
              remove: _controller.remove,
            ),
          ),
        );
      },
    );
  }

  void _togglePolicy() {
    final next = _usingCacheFirst
        ? widget.runtime.query
        : widget.runtime.cacheFirstQuery;
    _controller.updateQuery(next);
    setState(() => _usingCacheFirst = !_usingCacheFirst);
  }

  void _onPhaseChanged(
    BuildContext context,
    KacheSnapshot<RepositoryProfile> previous,
    KacheSnapshot<RepositoryProfile> current,
  ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'KacheListener: ${previous.phase.name} → ${current.phase.name}',
          ),
        ),
      );
  }

  RepositoryProfile _bumpStars(RepositoryProfile profile) => RepositoryProfile(
    fullName: profile.fullName,
    description: profile.description,
    htmlUrl: profile.htmlUrl,
    ownerAvatarUrl: profile.ownerAvatarUrl,
    stars: profile.stars + 1,
    forks: profile.forks,
    openIssues: profile.openIssues,
    language: profile.language,
    updatedAt: profile.updatedAt,
  );
}

/// Four [KacheBuilder]s side-by-side, one per policy, with live fetch counts
/// read from [KacheClient.events].
final class _FlutterPoliciesTab extends StatefulWidget {
  const _FlutterPoliciesTab({required this.runtime});

  final ExampleRuntime runtime;

  @override
  State<_FlutterPoliciesTab> createState() => _FlutterPoliciesTabState();
}

final class _FlutterPoliciesTabState extends State<_FlutterPoliciesTab> {
  late final List<
    ({
      String name,
      String desc,
      KacheQuery<RepositoryProfile> query,
      KacheController<RepositoryProfile> controller,
    })
  >
  _entries;
  final Map<String, int> _fetchCounts = <String, int>{};
  StreamSubscription<KacheEvent>? _sub;

  @override
  void initState() {
    super.initState();
    final client = widget.runtime.client;
    _entries =
        <
          ({
            String name,
            String desc,
            KacheQuery<RepositoryProfile> query,
            KacheController<RepositoryProfile> controller,
          })
        >[
          (
            name: 'SWR',
            desc: 'Serve cache, revalidate in background.',
            query: widget.runtime.query,
            controller: KacheController<RepositoryProfile>(
              client: client,
              query: widget.runtime.query,
            ),
          ),
          (
            name: 'cacheFirst',
            desc: 'Fresh window, no fetch while fresh.',
            query: widget.runtime.cacheFirstQuery,
            controller: KacheController<RepositoryProfile>(
              client: client,
              query: widget.runtime.cacheFirstQuery,
            ),
          ),
          (
            name: 'cacheOnly',
            desc: 'Never fetch automatically.',
            query: widget.runtime.cacheOnlyQuery,
            controller: KacheController<RepositoryProfile>(
              client: client,
              query: widget.runtime.cacheOnlyQuery,
            ),
          ),
          (
            name: 'networkOnly',
            desc: 'No storage, always fetch + poll.',
            query: widget.runtime.networkOnlyQuery,
            controller: KacheController<RepositoryProfile>(
              client: client,
              query: widget.runtime.networkOnlyQuery,
            ),
          ),
        ];
    _sub = client.events.listen((event) {
      if (event.kind == KacheEventKind.fetchStarted && event.key != null) {
        final k = event.key!.storageKey;
        if (mounted) {
          setState(() => _fetchCounts[k] = (_fetchCounts[k] ?? 0) + 1);
        }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final e in _entries) {
      e.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(_entries.map((e) => e.controller)),
      builder: (context, _) {
        final cards = _entries
            .map(
              (e) => PolicyCardModel(
                name: e.name,
                description: e.desc,
                snapshot: e.controller.value,
                fetchCount: _fetchCounts[e.query.key.storageKey] ?? 0,
                onForceFetch: () => e.controller.refresh(),
              ),
            )
            .toList();
        return PolicyPlayground(cards: cards);
      },
    );
  }
}
