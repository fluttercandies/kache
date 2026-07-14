part of 'repository_dashboard.dart';

final class _RepositoryBody extends StatelessWidget {
  const _RepositoryBody({
    required this.profile,
    required this.snapshot,
    required this.showNetworkImage,
    super.key,
  });

  final RepositoryProfile profile;
  final KacheSnapshot<RepositoryProfile> snapshot;
  final bool showNetworkImage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _RepositoryAvatar(
              url: profile.ownerAvatarUrl,
              showNetworkImage: showNetworkImage,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    profile.fullName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.description ?? 'No repository description.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _StateLabel(snapshot: snapshot),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Divider(height: 1),
        const SizedBox(height: 20),
        _MetricStrip(profile: profile),
        const SizedBox(height: 20),
        const Divider(height: 1),
        if (snapshot.failure != null) ...<Widget>[
          const SizedBox(height: 20),
          const _ErrorBand(),
        ],
        const SizedBox(height: 28),
        Text('Cache status', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        _StatusGrid(snapshot: snapshot, profile: profile),
        const SizedBox(height: 28),
        Text('Repository', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        SelectableText(
          profile.htmlUrl,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

final class _RepositoryAvatar extends StatelessWidget {
  const _RepositoryAvatar({required this.url, required this.showNetworkImage});

  final String url;
  final bool showNetworkImage;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.flutter_dash_rounded,
      size: 38,
      color: Theme.of(context).colorScheme.primary,
    );
    return Semantics(
      image: true,
      label: 'Flutter repository owner avatar',
      child: ClipOval(
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SizedBox.square(
            dimension: 72,
            child: showNetworkImage
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) => fallback,
                  )
                : fallback,
          ),
        ),
      ),
    );
  }
}

final class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.profile});

  final RepositoryProfile profile;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth < 520
          ? constraints.maxWidth / 2
          : constraints.maxWidth / 4;
      return Wrap(
        runSpacing: 18,
        children: <Widget>[
          _Metric(width: width, label: 'Stars', value: _compact(profile.stars)),
          _Metric(width: width, label: 'Forks', value: _compact(profile.forks)),
          _Metric(
            width: width,
            label: 'Open issues',
            value: _compact(profile.openIssues),
          ),
          _Metric(
            width: width,
            label: 'Language',
            value: profile.language ?? 'Mixed',
          ),
        ],
      );
    },
  );
}

final class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

final class _StatusGrid extends StatelessWidget {
  const _StatusGrid({required this.snapshot, required this.profile});

  final KacheSnapshot<RepositoryProfile> snapshot;
  final RepositoryProfile profile;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 28,
    runSpacing: 18,
    children: <Widget>[
      _StatusItem(label: 'Source', value: _sourceLabel(snapshot.source)),
      _StatusItem(
        label: 'Freshness',
        value: snapshot.freshness == KacheFreshness.fresh ? 'Fresh' : 'Stale',
      ),
      _StatusItem(
        label: 'Persistence',
        value: _persistenceLabel(snapshot.persistence?.phase),
      ),
      _StatusItem(label: 'Cached at', value: _formatUtc(snapshot.fetchedAt)),
      _StatusItem(
        label: 'GitHub updated',
        value: _formatUtc(profile.updatedAt),
      ),
    ],
  );
}

final class _StatusItem extends StatelessWidget {
  const _StatusItem({required this.label, required this.value});

  final String label;
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

final class _StateLabel extends StatelessWidget {
  const _StateLabel({required this.snapshot});

  final KacheSnapshot<RepositoryProfile> snapshot;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = snapshot.isRefreshing
        ? (Icons.sync_rounded, 'Refreshing', Colors.teal)
        : snapshot.failure != null
        ? (Icons.cloud_off_rounded, 'Cached copy', Colors.amber.shade800)
        : snapshot.source == KacheDataSource.persistence
        ? (Icons.storage_rounded, 'Disk cache', Colors.amber.shade800)
        : (Icons.cloud_done_rounded, 'Live data', Colors.green.shade700);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
        ),
      ],
    );
  }
}

final class _ErrorBand extends StatelessWidget {
  const _ErrorBand();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.wifi_off_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Refresh failed. Showing the last cached data.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, minHeight: 300),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

String _compact(int value) {
  if (value >= 1000000) {
    return '${_trim(value / 1000000)}M';
  }
  if (value >= 1000) {
    return '${_trim(value / 1000)}K';
  }
  return value.toString();
}

String _trim(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

String _sourceLabel(KacheDataSource? source) => switch (source) {
  KacheDataSource.persistence => 'Disk cache',
  KacheDataSource.fetch => 'GitHub',
  KacheDataSource.manual => 'Manual update',
  null => 'None',
};

String _persistenceLabel(KachePersistencePhase? phase) => switch (phase) {
  KachePersistencePhase.idle => 'Idle',
  KachePersistencePhase.reading => 'Reading',
  KachePersistencePhase.absent => 'Not cached',
  KachePersistencePhase.writing => 'Writing',
  KachePersistencePhase.persisted => 'Persisted',
  KachePersistencePhase.failed => 'Failed',
  null => 'Memory only',
};

String _formatUtc(DateTime? value) {
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
