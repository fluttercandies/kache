import 'package:flutter/material.dart';
import 'package:kache/kache.dart';

/// A labeled value cell used across the playground tabs.
class PlaygroundStatusItem extends StatelessWidget {
  /// Creates a status cell.
  const PlaygroundStatusItem({
    required this.label,
    required this.value,
    super.key,
  });

  /// Label rendered above the value.
  final String label;

  /// Value rendered below the label.
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 136,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

/// A section header used to group playground content.
class PlaygroundSection extends StatelessWidget {
  /// Creates a section.
  const PlaygroundSection({
    required this.title,
    required this.child,
    super.key,
  });

  /// Section title.
  final String title;

  /// Section content.
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

/// Renders a human-readable label for a [KacheDataSource].
String playgroundSourceLabel(KacheDataSource? source) => switch (source) {
  KacheDataSource.persistence => 'Disk cache',
  KacheDataSource.fetch => 'GitHub',
  KacheDataSource.manual => 'Manual update',
  null => 'None',
};

/// Renders a human-readable label for a [KachePersistencePhase].
String playgroundPersistenceLabel(KachePersistencePhase? phase) =>
    switch (phase) {
      KachePersistencePhase.idle => 'Idle',
      KachePersistencePhase.reading => 'Reading',
      KachePersistencePhase.absent => 'Not cached',
      KachePersistencePhase.writing => 'Writing',
      KachePersistencePhase.persisted => 'Persisted',
      KachePersistencePhase.failed => 'Failed',
      null => 'Memory only',
    };

/// Renders a human-readable label for a [KachePhase].
String playgroundPhaseLabel(KachePhase phase) => switch (phase) {
  KachePhase.idle => 'Idle',
  KachePhase.loading => 'Loading',
  KachePhase.ready => 'Ready',
  KachePhase.failure => 'Failure',
};

/// Renders freshness without treating an empty snapshot as stale data.
String playgroundFreshnessLabel(KacheFreshness? freshness) =>
    switch (freshness) {
      KacheFreshness.fresh => 'Fresh',
      KacheFreshness.stale => 'Stale',
      null => 'None',
    };

/// Renders a human-readable label for a [KacheFailureKind], without any value.
String playgroundFailureKindLabel(KacheFailureKind? kind) {
  if (kind == null) {
    return 'None';
  }
  return switch (kind) {
    KacheFailureKind.configuration => 'Configuration',
    KacheFailureKind.cacheMiss => 'Cache miss',
    KacheFailureKind.fetchUnavailable => 'Fetch unavailable',
    KacheFailureKind.persistenceRead => 'Persistence read',
    KacheFailureKind.persistenceWrite => 'Persistence write',
    KacheFailureKind.fetch => 'Fetch',
    KacheFailureKind.delete => 'Delete',
    KacheFailureKind.clear => 'Clear',
    KacheFailureKind.connectivity => 'Connectivity',
    KacheFailureKind.lifecycle => 'Lifecycle',
  };
}

/// Formats a UTC [DateTime] compactly, or a placeholder when null.
String playgroundFormatUtc(DateTime? value) {
  if (value == null) {
    return 'Not available';
  }
  final utc = value.toUtc();
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = utc.hour.toString().padLeft(2, '0');
  final minute = utc.minute.toString().padLeft(2, '0');
  return '${months[utc.month - 1]} ${utc.day}, ${utc.year} · $hour:$minute UTC';
}
