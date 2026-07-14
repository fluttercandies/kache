import 'package:flutter/material.dart';
import 'package:kache/kache.dart';

import 'playground_components.dart';
import 'repository_profile.dart';

/// Describes one policy card rendered by [PolicyPlayground].
final class PolicyCardModel {
  /// Creates a policy card model.
  const PolicyCardModel({
    required this.name,
    required this.description,
    required this.snapshot,
    required this.fetchCount,
    required this.onForceFetch,
  });

  /// Short policy name, e.g. `SWR`.
  final String name;

  /// One-line description of the policy's behaviour.
  final String description;

  /// Latest snapshot for this policy's query.
  final KacheSnapshot<RepositoryProfile> snapshot;

  /// Number of `fetchStarted` events observed for this query's key.
  final int fetchCount;

  /// Triggers an explicit refresh on this query.
  final VoidCallback onForceFetch;
}

/// Compares cache policies side-by-side, each backed by its own query.
///
/// The host adapter supplies one [PolicyCardModel] per policy so the same UI is
/// reused across Flutter/Riverpod/Bloc/Provider without duplicating logic.
class PolicyPlayground extends StatelessWidget {
  /// Creates the policy comparison view.
  const PolicyPlayground({required this.cards, this.trailing, super.key});

  /// One card per demonstrated policy.
  final List<PolicyCardModel> cards;

  /// Optional adapter-specific widget rendered after the policy cards.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
    children: <Widget>[
      Text(
        'Each card subscribes to its own query on the same client, so you can '
        'see how freshness, fetch triggers and storage differ by policy.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: <Widget>[for (final card in cards) _PolicyCard(model: card)],
      ),
      if (trailing case final trailing?) ...<Widget>[
        const SizedBox(height: 16),
        trailing,
      ],
    ],
  );
}

final class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.model});

  final PolicyCardModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = model.snapshot;
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                model.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (snapshot.isRefreshing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            model.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: <Widget>[
              PlaygroundStatusItem(
                label: 'Phase',
                value: playgroundPhaseLabel(snapshot.phase),
              ),
              PlaygroundStatusItem(
                label: 'Source',
                value: playgroundSourceLabel(snapshot.source),
              ),
              PlaygroundStatusItem(
                label: 'Freshness',
                value: playgroundFreshnessLabel(snapshot.freshness),
              ),
              PlaygroundStatusItem(
                label: 'Fetches',
                value: model.fetchCount.toString(),
              ),
              if (snapshot.hasData)
                PlaygroundStatusItem(
                  label: 'Stars',
                  value: snapshot.requireData.stars.toString(),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: snapshot.isRefreshing ? null : model.onForceFetch,
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('Force fetch'),
            ),
          ),
        ],
      ),
    );
  }
}
