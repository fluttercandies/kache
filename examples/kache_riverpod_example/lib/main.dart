import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kache_example_support/kache_example_support.dart';
import 'package:kache_hooks_riverpod/kache_hooks_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: KacheRiverpodExampleApp()));
}

final _runtimeProvider = Provider<ExampleRuntime>((ref) {
  throw StateError('ExampleRuntime must be overridden by the application.');
}, dependencies: const []);

// Repository tab: a plain kacheProvider over the SWR query.
final _repositoryProvider = kacheProvider<RepositoryProfile>(
  client: (ref) => ref.watch(_runtimeProvider).client,
  query: (ref) => ref.watch(_runtimeProvider).query,
  dependencies: [_runtimeProvider],
);

// Commands tab: another handle on the same shared SWR query.
final _commandsProvider = kacheProvider<RepositoryProfile>(
  client: (ref) => ref.watch(_runtimeProvider).client,
  query: (ref) => ref.watch(_runtimeProvider).query,
  dependencies: [_runtimeProvider],
);

// Policies tab: a family keyed by policy name, so one definition serves all
// four cards. Demonstrates kacheProvider.family.
final _policyFamilyProvider = kacheProvider.family<RepositoryProfile, String>(
  client: (ref) => ref.watch(_runtimeProvider).client,
  query: (ref, String policy) => switch (policy) {
    'SWR' => ref.watch(_runtimeProvider).query,
    'cacheFirst' => ref.watch(_runtimeProvider).cacheFirstQuery,
    'cacheOnly' => ref.watch(_runtimeProvider).cacheOnlyQuery,
    'networkOnly' => ref.watch(_runtimeProvider).networkOnlyQuery,
    _ => ref.watch(_runtimeProvider).query,
  },
  dependencies: [_runtimeProvider],
);

// Policies tab: an auto-dispose family with manual keep-alive, demonstrating
// kacheProvider.autoDispose.family together with keepAlive/releaseKeepAlive.
final _policyAutoDisposeProvider = kacheProvider.autoDispose
    .family<RepositoryProfile, String>(
      client: (ref) => ref.watch(_runtimeProvider).client,
      query: (ref, String policy) => switch (policy) {
        'SWR' => ref.watch(_runtimeProvider).query,
        'cacheFirst' => ref.watch(_runtimeProvider).cacheFirstQuery,
        'cacheOnly' => ref.watch(_runtimeProvider).cacheOnlyQuery,
        'networkOnly' => ref.watch(_runtimeProvider).networkOnlyQuery,
        _ => ref.watch(_runtimeProvider).query,
      },
      dependencies: [_runtimeProvider],
    );

class KacheRiverpodExampleApp extends StatelessWidget {
  const KacheRiverpodExampleApp({
    this.runtimeFactory,
    this.showNetworkImage = true,
    super.key,
  });

  final ExampleRuntimeFactory? runtimeFactory;
  final bool showNetworkImage;

  @override
  Widget build(BuildContext context) => KacheExampleApp(
    adapterName: 'Riverpod',
    boxName: 'kache_riverpod_example_repository_v1',
    runtimeFactory: runtimeFactory,
    builder: (context, runtime) => ProviderScope(
      overrides: [_runtimeProvider.overrideWithValue(runtime)],
      child: _RiverpodPlayground(showNetworkImage: showNetworkImage),
    ),
  );
}

class _RiverpodPlayground extends StatelessWidget {
  const _RiverpodPlayground({required this.showNetworkImage});

  final bool showNetworkImage;

  @override
  Widget build(BuildContext context) => KachePlayground(
    adapterName: 'Riverpod',
    repository: (context) =>
        _RiverpodRepository(showNetworkImage: showNetworkImage),
    slots: PlaygroundSlots(
      persistence: (context) => Consumer(
        builder: (context, ref, child) {
          final runtime = ref.watch(_runtimeProvider);
          return PersistencePlaygroundHost(
            runtime: runtime,
            boxPrefix: 'kache_riverpod_example',
          );
        },
      ),
      commands: (context) => const _RiverpodCommandsTab(),
      policies: (context) => const _RiverpodPoliciesTab(),
      activity: (context) => Consumer(
        builder: (context, ref, child) {
          final runtime = ref.watch(_runtimeProvider);
          return ActivityPlayground(
            client: runtime.client,
            peekQuery: runtime.query,
          );
        },
      ),
    ),
  );
}

final class _RiverpodRepository extends HookConsumerWidget {
  const _RiverpodRepository({required this.showNetworkImage});

  final bool showNetworkImage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = useKacheProvider(ref, _repositoryProvider);
    return RepositoryDashboard(
      adapterName: 'Riverpod Hooks',
      snapshot: cache.snapshot,
      onRefresh: cache.refresh,
      onClear: cache.remove,
      showNetworkImage: showNetworkImage,
      compact: true,
    );
  }
}

final class _RiverpodCommandsTab extends ConsumerWidget {
  const _RiverpodCommandsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(_commandsProvider);
    final notifier = ref.watch(_commandsProvider.notifier);
    return CommandPlayground(
      snapshot: snapshot,
      commands: PlaygroundCommandSet(
        load: notifier.load,
        refresh: notifier.refresh,
        setData: () => notifier.setData(_bumpStars(snapshot.requireData)),
        updateData: () =>
            notifier.updateData((previous) => _bumpStars(previous.requireData)),
        invalidate: notifier.invalidate,
        invalidateNoRefetch: () => notifier.invalidate(refetch: false),
        remove: notifier.remove,
      ),
    );
  }
}

final class _RiverpodPoliciesTab extends ConsumerStatefulWidget {
  const _RiverpodPoliciesTab();

  @override
  ConsumerState<_RiverpodPoliciesTab> createState() =>
      _RiverpodPoliciesTabState();
}

final class _RiverpodPoliciesTabState
    extends ConsumerState<_RiverpodPoliciesTab> {
  static const _policies = <(String, String)>[
    ('SWR', 'Serve cache, revalidate in background.'),
    ('cacheFirst', 'Fresh window, no fetch while fresh.'),
    ('cacheOnly', 'Never fetch automatically.'),
    ('networkOnly', 'No storage, always fetch + poll.'),
  ];
  final Map<String, int> _fetchCounts = <String, int>{};
  StreamSubscription<KacheEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = ref.read(_runtimeProvider).client.events.listen((event) {
      if (event.kind == KacheEventKind.fetchStarted && event.key != null) {
        final key = event.key!.storageKey;
        if (mounted) {
          setState(() => _fetchCounts[key] = (_fetchCounts[key] ?? 0) + 1);
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PolicyPlayground(
      cards: <PolicyCardModel>[
        for (final (name, desc) in _policies) _buildPolicyCard(name, desc),
      ],
      trailing: _AutoDisposeKeepAliveCard(),
    );
  }

  PolicyCardModel _buildPolicyCard(String name, String description) {
    final provider = _policyFamilyProvider(name);
    final snapshot = ref.watch(provider);
    final notifier = ref.watch(provider.notifier);
    return PolicyCardModel(
      name: name,
      description: description,
      snapshot: snapshot,
      fetchCount: _fetchCounts[notifier.query.key.storageKey] ?? 0,
      onForceFetch: notifier.refresh,
    );
  }
}

/// Demonstrates [kacheProvider.autoDispose] plus
/// [KacheNotifier.keepAlive]/[releaseKeepAlive].
final class _AutoDisposeKeepAliveCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AutoDisposeKeepAliveCard> createState() =>
      _AutoDisposeKeepAliveCardState();
}

final class _AutoDisposeKeepAliveCardState
    extends ConsumerState<_AutoDisposeKeepAliveCard> {
  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(_policyAutoDisposeProvider('SWR'));
    final notifier = ref.watch(_policyAutoDisposeProvider('SWR').notifier);
    final keptAlive = notifier.isKeptAlive;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'autoDispose + keepAlive',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'kacheProvider.autoDispose releases the handle when no one listens. '
            'keepAlive() forces it to survive.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              FilledButton.tonal(
                onPressed: () {
                  if (keptAlive) {
                    notifier.releaseKeepAlive();
                  } else {
                    notifier.keepAlive();
                  }
                  setState(() {});
                },
                child: Text(
                  keptAlive ? 'Release keepAlive' : 'Request keepAlive',
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'isKeptAlive: ${keptAlive ? 'yes' : 'no'}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Phase: ${playgroundPhaseLabel(snapshot.phase)}'),
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
