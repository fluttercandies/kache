import 'package:flutter/material.dart';

import 'playground_components.dart';

/// One demonstrated persistence capability, rendered as an info card.
final class PersistenceCapabilityModel {
  /// Creates a capability card model.
  const PersistenceCapabilityModel({
    required this.title,
    required this.description,
    required this.api,
    required this.status,
    this.detail,
  });

  /// Short title, e.g. `fromBox + borrowed`.
  final String title;

  /// One-line description of the demonstrated behaviour.
  final String description;

  /// The API surface demonstrated.
  final String api;

  /// Current observable status.
  final String status;

  /// Optional extra detail line.
  final String? detail;
}

/// Demonstrates persistence-layer API surfaces that are shared across every
/// example adapter.
///
/// This tab is adapter-agnostic because it talks directly to the persistence
/// backends via the host runtime; it renders one card per demonstrated
/// capability so users can see how to wire Hive CE, schema migration, encrypted
/// boxes, and the in-memory backend.
class PersistencePlayground extends StatelessWidget {
  /// Creates the persistence playground.
  const PersistencePlayground({required this.capabilities, super.key});

  /// One card per demonstrated persistence capability.
  final List<PersistenceCapabilityModel> capabilities;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
    children: <Widget>[
      Text(
        'These cards exercise the persistence API surface directly: Hive CE box '
        'ownership, schema migration, encrypted boxes, and the SDK-only in-memory '
        'backend. They are identical across all four example adapters.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: <Widget>[
          for (final c in capabilities) _CapabilityCard(model: c),
        ],
      ),
    ],
  );
}

final class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.model});

  final PersistenceCapabilityModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
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
            model.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            model.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              model.api,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: <Widget>[
              PlaygroundStatusItem(label: 'Status', value: model.status),
              if (model.detail != null)
                PlaygroundStatusItem(label: 'Detail', value: model.detail!),
            ],
          ),
        ],
      ),
    );
  }
}
