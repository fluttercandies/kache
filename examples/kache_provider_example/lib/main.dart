import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kache_example_support/kache_example_support.dart';
import 'package:kache_provider/kache_provider.dart';

void main() {
  runApp(const KacheProviderExampleApp());
}

class KacheProviderExampleApp extends StatelessWidget {
  const KacheProviderExampleApp({
    this.runtimeFactory,
    this.showNetworkImage = true,
    super.key,
  });

  final ExampleRuntimeFactory? runtimeFactory;
  final bool showNetworkImage;

  @override
  Widget build(BuildContext context) => KacheExampleApp(
    adapterName: 'Provider',
    boxName: 'kache_provider_example_repository_v1',
    runtimeFactory: runtimeFactory,
    builder: (context, runtime) => KachePlayground(
      adapterName: 'Provider',
      repository: (context) => KacheProvider<RepositoryProfile>(
        query: runtime.query,
        child: KacheConsumer<RepositoryProfile>(
          builder: (context, snapshot, controller, child) =>
              RepositoryDashboard(
                adapterName: 'Provider',
                snapshot: snapshot,
                onRefresh: controller.refresh,
                onClear: controller.remove,
                showNetworkImage: showNetworkImage,
                compact: true,
              ),
        ),
      ),
      slots: PlaygroundSlots(
        persistence: (context) => PersistencePlaygroundHost(
          runtime: runtime,
          boxPrefix: 'kache_provider_example',
        ),
        commands: (context) => _ProviderCommandsTab(runtime: runtime),
        policies: (context) => _ProviderPoliciesTab(runtime: runtime),
        activity: (context) => ActivityPlayground(
          client: runtime.client,
          peekQuery: runtime.query,
        ),
      ),
    ),
  );
}

/// Commands tab demonstrating [KacheProvider] + [KacheConsumer] and the
/// [BuildContext] extensions [readKache]/[watchKache].
final class _ProviderCommandsTab extends StatelessWidget {
  const _ProviderCommandsTab({required this.runtime});

  final ExampleRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return KacheProvider<RepositoryProfile>(
      query: runtime.query,
      child: KacheConsumer<RepositoryProfile>(
        builder: (context, snapshot, controller, child) {
          return CommandPlayground(
            snapshot: snapshot,
            // context.readKache<RepositoryProfile>() also returns the controller.
            commands: PlaygroundCommandSet(
              load: controller.load,
              refresh: controller.refresh,
              setData: () => context.readKache<RepositoryProfile>().setData(
                _bumpStars(snapshot.requireData),
              ),
              updateData: () => context
                  .readKache<RepositoryProfile>()
                  .updateData((previous) => _bumpStars(previous.requireData)),
              invalidate: () =>
                  context.readKache<RepositoryProfile>().invalidate(),
              invalidateNoRefetch: () => context
                  .readKache<RepositoryProfile>()
                  .invalidate(refetch: false),
              remove: () => context.readKache<RepositoryProfile>().remove(),
            ),
          );
        },
      ),
    );
  }
}

/// Policies tab: one [KacheController] per policy, exposed through
/// [ChangeNotifierProvider.value] so [KacheConsumer] / [watchKache] work too.
final class _ProviderPoliciesTab extends StatefulWidget {
  const _ProviderPoliciesTab({required this.runtime});

  final ExampleRuntime runtime;

  @override
  State<_ProviderPoliciesTab> createState() => _ProviderPoliciesTabState();
}

final class _ProviderPoliciesTabState extends State<_ProviderPoliciesTab> {
  late final List<
    ({String name, String desc, KacheController<RepositoryProfile> controller})
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
            KacheController<RepositoryProfile> controller,
          })
        >[
          (
            name: 'SWR',
            desc: 'Serve cache, revalidate in background.',
            controller: KacheController<RepositoryProfile>(
              client: client,
              query: widget.runtime.query,
            ),
          ),
          (
            name: 'cacheFirst',
            desc: 'Fresh window, no fetch while fresh.',
            controller: KacheController<RepositoryProfile>(
              client: client,
              query: widget.runtime.cacheFirstQuery,
            ),
          ),
          (
            name: 'cacheOnly',
            desc: 'Never fetch automatically.',
            controller: KacheController<RepositoryProfile>(
              client: client,
              query: widget.runtime.cacheOnlyQuery,
            ),
          ),
          (
            name: 'networkOnly',
            desc: 'No storage, always fetch + poll.',
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
      builder: (context, _) => PolicyPlayground(
        cards: <PolicyCardModel>[
          for (final e in _entries)
            PolicyCardModel(
              name: e.name,
              description: e.desc,
              snapshot: e.controller.value,
              fetchCount: _fetchCounts[e.controller.query.key.storageKey] ?? 0,
              onForceFetch: () => e.controller.refresh(),
            ),
        ],
      ),
    );
  }
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
