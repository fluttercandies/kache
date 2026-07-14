import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kache_bloc/kache_bloc.dart';
import 'package:kache_example_support/kache_example_support.dart';

void main() {
  runApp(const KacheBlocExampleApp());
}

class KacheBlocExampleApp extends StatelessWidget {
  const KacheBlocExampleApp({
    this.runtimeFactory,
    this.showNetworkImage = true,
    super.key,
  });

  final ExampleRuntimeFactory? runtimeFactory;
  final bool showNetworkImage;

  @override
  Widget build(BuildContext context) => KacheExampleApp(
    adapterName: 'Bloc/Cubit',
    boxName: 'kache_bloc_example_repository_v1',
    runtimeFactory: runtimeFactory,
    builder: (context, runtime) => KachePlayground(
      adapterName: 'Bloc/Cubit',
      repository: (context) => BlocProvider<KacheCubit<RepositoryProfile>>(
        lazy: false,
        create: (_) => KacheCubit<RepositoryProfile>(
          client: runtime.client,
          query: runtime.query,
        ),
        child:
            BlocBuilder<
              KacheCubit<RepositoryProfile>,
              KacheSnapshot<RepositoryProfile>
            >(
              builder: (context, snapshot) {
                final cubit = context.read<KacheCubit<RepositoryProfile>>();
                return RepositoryDashboard(
                  adapterName: 'Bloc/Cubit',
                  snapshot: snapshot,
                  onRefresh: cubit.refresh,
                  onClear: cubit.remove,
                  showNetworkImage: showNetworkImage,
                  compact: true,
                );
              },
            ),
      ),
      slots: PlaygroundSlots(
        persistence: (context) => PersistencePlaygroundHost(
          runtime: runtime,
          boxPrefix: 'kache_bloc_example',
        ),
        commands: (context) => _BlocCommandsTab(runtime: runtime),
        policies: (context) => _BlocPoliciesTab(runtime: runtime),
        activity: (context) => ActivityPlayground(
          client: runtime.client,
          peekQuery: runtime.query,
        ),
      ),
    ),
  );
}

/// Commands tab using [KacheCubit].
final class _BlocCommandsTab extends StatelessWidget {
  const _BlocCommandsTab({required this.runtime});

  final ExampleRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<KacheCubit<RepositoryProfile>>(
      lazy: false,
      create: (_) => KacheCubit<RepositoryProfile>(
        client: runtime.client,
        query: runtime.query,
      ),
      child:
          BlocBuilder<
            KacheCubit<RepositoryProfile>,
            KacheSnapshot<RepositoryProfile>
          >(
            builder: (context, snapshot) {
              final cubit = context.read<KacheCubit<RepositoryProfile>>();
              return CommandPlayground(
                snapshot: snapshot,
                commands: PlaygroundCommandSet(
                  load: cubit.load,
                  refresh: cubit.refresh,
                  setData: () =>
                      cubit.setData(_bumpStars(snapshot.requireData)),
                  updateData: () => cubit.updateData(
                    (previous) => _bumpStars(previous.requireData),
                  ),
                  invalidate: cubit.invalidate,
                  invalidateNoRefetch: () => cubit.invalidate(refetch: false),
                  remove: cubit.remove,
                ),
              );
            },
          ),
    );
  }
}

/// Policies tab: one [KacheCubit] per policy, plus a composed
/// [KacheBlocBinding] demo card.
final class _BlocPoliciesTab extends StatefulWidget {
  const _BlocPoliciesTab({required this.runtime});

  final ExampleRuntime runtime;

  @override
  State<_BlocPoliciesTab> createState() => _BlocPoliciesTabState();
}

final class _BlocPoliciesTabState extends State<_BlocPoliciesTab> {
  late final List<
    ({String name, String desc, KacheCubit<RepositoryProfile> cubit})
  >
  _entries;
  late final KacheBlocBinding<RepositoryProfile> _binding;
  late final _BindingDemoCubit _bindingCubit;
  StreamSubscription<KacheEvent>? _sub;
  final Map<String, int> _fetchCounts = <String, int>{};

  @override
  void initState() {
    super.initState();
    final client = widget.runtime.client;
    _entries =
        <({String name, String desc, KacheCubit<RepositoryProfile> cubit})>[
          (
            name: 'SWR',
            desc: 'Serve cache, revalidate in background.',
            cubit: KacheCubit<RepositoryProfile>(
              client: client,
              query: widget.runtime.query,
            ),
          ),
          (
            name: 'cacheFirst',
            desc: 'Fresh window, no fetch while fresh.',
            cubit: KacheCubit<RepositoryProfile>(
              client: client,
              query: widget.runtime.cacheFirstQuery,
            ),
          ),
          (
            name: 'cacheOnly',
            desc: 'Never fetch automatically.',
            cubit: KacheCubit<RepositoryProfile>(
              client: client,
              query: widget.runtime.cacheOnlyQuery,
            ),
          ),
          (
            name: 'networkOnly',
            desc: 'No storage, always fetch + poll.',
            cubit: KacheCubit<RepositoryProfile>(
              client: client,
              query: widget.runtime.networkOnlyQuery,
            ),
          ),
        ];
    // KacheBlocBinding demo: compose a core resource into a custom Cubit.
    _binding = KacheBlocBinding<RepositoryProfile>(
      client: client,
      query: widget.runtime.memoryQuery,
    );
    _bindingCubit = _BindingDemoCubit();
    _binding.attach(_bindingCubit.update);
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
    _bindingCubit.close();
    unawaited(_binding.close());
    for (final e in _entries) {
      e.cubit.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildPolicyListeners(0);
  }

  Widget _buildPolicyListeners(int index) {
    if (index < _entries.length) {
      final entry = _entries[index];
      return BlocBuilder<
        KacheCubit<RepositoryProfile>,
        KacheSnapshot<RepositoryProfile>
      >(
        bloc: entry.cubit,
        builder: (context, snapshot) => _buildPolicyListeners(index + 1),
      );
    }
    return PolicyPlayground(
      cards: <PolicyCardModel>[
        for (final entry in _entries)
          PolicyCardModel(
            name: entry.name,
            description: entry.desc,
            snapshot: entry.cubit.state,
            fetchCount: _fetchCounts[entry.cubit.query.key.storageKey] ?? 0,
            onForceFetch: entry.cubit.refresh,
          ),
      ],
      trailing:
          BlocBuilder<_BindingDemoCubit, KacheSnapshot<RepositoryProfile>?>(
            bloc: _bindingCubit,
            builder: (context, snapshot) =>
                _BindingDemoCard(binding: _binding, snapshot: snapshot),
          ),
    );
  }
}

/// A hand-written Cubit composed around a [KacheBlocBinding], demonstrating that
/// a binding can bridge a core resource into any Bloc/Cubit you already own.
final class _BindingDemoCubit extends Cubit<KacheSnapshot<RepositoryProfile>?> {
  _BindingDemoCubit() : super(null);

  void update(KacheSnapshot<RepositoryProfile> snapshot) => emit(snapshot);
}

class _BindingDemoCard extends StatelessWidget {
  const _BindingDemoCard({required this.binding, required this.snapshot});

  final KacheBlocBinding<RepositoryProfile> binding;
  final KacheSnapshot<RepositoryProfile>? snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = snapshot;
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
            'KacheBlocBinding (memory query)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Compose a core resource into an existing Bloc/Cubit via attach().',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            snap == null
                ? 'Phase: ${playgroundPhaseLabel(binding.snapshot.phase)}'
                : 'Phase: ${playgroundPhaseLabel(snap.phase)}'
                      '${snap.hasData ? ' · ${snap.requireData.stars} stars' : ''}',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: binding.refresh,
                child: const Text('binding.refresh()'),
              ),
              FilledButton.tonal(
                onPressed: () => binding.setData(
                  RepositoryProfile(
                    fullName: 'flutter/flutter',
                    description: 'Manual binding update.',
                    htmlUrl: 'https://github.com/flutter/flutter',
                    ownerAvatarUrl: 'https://avatars.example/flutter.png',
                    stars: snap?.hasData == true
                        ? snap!.requireData.stars + 1
                        : 1,
                    forks: 0,
                    openIssues: 0,
                    language: 'Dart',
                    updatedAt: DateTime.now().toUtc(),
                  ),
                ),
                child: const Text('binding.setData()'),
              ),
            ],
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
