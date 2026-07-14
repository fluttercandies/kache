import 'package:flutter/material.dart';
import 'package:kache/kache.dart';

import 'playground_components.dart';
import 'repository_profile.dart';

/// Signature for a cache command that returns the resulting snapshot.
typedef PlaygroundCommand = Future<KacheSnapshot<RepositoryProfile>> Function();

/// All command callbacks wired by the host adapter (Flutter/Riverpod/...).
///
/// Each adapter forwards the same core command set through its own controller,
/// so this stays adapter-agnostic while exercising the full command surface.
final class PlaygroundCommandSet {
  /// Creates a command set.
  const PlaygroundCommandSet({
    required this.load,
    required this.refresh,
    required this.setData,
    required this.updateData,
    required this.invalidate,
    required this.invalidateNoRefetch,
    required this.remove,
  });

  /// Loads the query following its policy.
  final PlaygroundCommand load;

  /// Forces a network refresh ignoring freshness.
  final PlaygroundCommand refresh;

  /// Atomically replaces the value (write-through).
  final PlaygroundCommand setData;

  /// Atomically transforms the current snapshot value.
  final PlaygroundCommand updateData;

  /// Marks data stale and refetches active resources.
  final PlaygroundCommand invalidate;

  /// Marks data stale without an automatic refetch.
  final PlaygroundCommand invalidateNoRefetch;

  /// Clears the in-memory and persisted value.
  final PlaygroundCommand remove;
}

/// Demonstrates the full command surface against one shared snapshot.
///
/// The host adapter subscribes to its query and forwards the snapshot plus a
/// [PlaygroundCommandSet]; this widget renders a live inspector plus a row of
/// command buttons, so every adapter exposes identical behaviour.
class CommandPlayground extends StatefulWidget {
  /// Creates the command playground.
  const CommandPlayground({
    required this.snapshot,
    required this.commands,
    this.leading,
    super.key,
  });

  /// Current cache snapshot rendered by the inspector.
  final KacheSnapshot<RepositoryProfile> snapshot;

  /// Command callbacks forwarded by the host adapter.
  final PlaygroundCommandSet commands;

  /// Optional adapter-specific widget rendered above the snapshot section.
  final Widget? leading;

  @override
  State<CommandPlayground> createState() => _CommandPlaygroundState();
}

final class _CommandPlaygroundState extends State<CommandPlayground> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: <Widget>[
        if (widget.leading case final leading?)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: leading,
          ),
        PlaygroundSection(
          title: 'Snapshot',
          child: _SnapshotInspector(snapshot: snapshot),
        ),
        PlaygroundSection(
          title: 'Commands',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _CommandChip(
                tooltip: 'resource.load(): read persistence, fetch by policy',
                label: 'Load',
                icon: Icons.download_rounded,
                onTap: _busy
                    ? null
                    : () => _run(widget.commands.load, 'Loaded'),
              ),
              _CommandChip(
                tooltip: 'resource.refresh(): force fetch, keep data on error',
                label: 'Refresh',
                icon: Icons.sync_rounded,
                onTap: _busy
                    ? null
                    : () => _run(widget.commands.refresh, 'Refreshed'),
              ),
              _CommandChip(
                tooltip: 'resource.setData(+1 star): atomic write-through',
                label: 'Set +1 star',
                icon: Icons.star_rounded,
                onTap: _busy || !snapshot.hasData
                    ? null
                    : () => _run(widget.commands.setData, 'Set'),
              ),
              _CommandChip(
                tooltip:
                    'resource.updateData(+1 star): transform current value',
                label: 'Update value',
                icon: Icons.edit_rounded,
                onTap: _busy || !snapshot.hasData
                    ? null
                    : () => _run(widget.commands.updateData, 'Updated'),
              ),
              _CommandChip(
                tooltip:
                    'resource.invalidate(refetch: true): mark stale + refetch',
                label: 'Invalidate',
                icon: Icons.cached_rounded,
                onTap: _busy
                    ? null
                    : () => _run(widget.commands.invalidate, 'Invalidated'),
              ),
              _CommandChip(
                tooltip: 'resource.invalidate(refetch: false): mark stale only',
                label: 'Invalidate (no refetch)',
                icon: Icons.history_rounded,
                onTap: _busy
                    ? null
                    : () => _run(
                        widget.commands.invalidateNoRefetch,
                        'Invalidated',
                      ),
              ),
              _CommandChip(
                tooltip: 'resource.remove(): clear memory + persistence',
                label: 'Remove',
                icon: Icons.delete_outline_rounded,
                onTap: _busy
                    ? null
                    : () => _run(widget.commands.remove, 'Removed'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _run(PlaygroundCommand command, String label) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await command();
      if (!mounted) {
        return;
      }
      final message = result.failure == null
          ? '$label: ${playgroundPhaseLabel(result.phase)}'
          : result.hasData
          ? '$label failed. Cached data remains.'
          : '$label failed (${playgroundFailureKindLabel(result.failure!.kind)}).';
      _snack(message);
    } on Object {
      if (mounted) {
        _snack('The command could not be completed.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

final class _SnapshotInspector extends StatelessWidget {
  const _SnapshotInspector({required this.snapshot});

  final KacheSnapshot<RepositoryProfile> snapshot;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 28,
      runSpacing: 18,
      children: <Widget>[
        PlaygroundStatusItem(
          label: 'Phase',
          value: playgroundPhaseLabel(snapshot.phase),
        ),
        PlaygroundStatusItem(
          label: 'Has data',
          value: snapshot.hasData ? 'Yes' : 'No',
        ),
        PlaygroundStatusItem(
          label: 'Refreshing',
          value: snapshot.isRefreshing ? 'Yes' : 'No',
        ),
        PlaygroundStatusItem(
          label: 'Stale',
          value: snapshot.isStale ? 'Yes' : 'No',
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
          label: 'Persistence',
          value: playgroundPersistenceLabel(snapshot.persistence?.phase),
        ),
        PlaygroundStatusItem(label: 'Revision', value: 'r${snapshot.revision}'),
        PlaygroundStatusItem(
          label: 'Fetched at',
          value: playgroundFormatUtc(snapshot.fetchedAt),
        ),
        PlaygroundStatusItem(
          label: 'Failure',
          value: playgroundFailureKindLabel(snapshot.failure?.kind),
        ),
        if (snapshot.hasData)
          PlaygroundStatusItem(
            label: 'Stars',
            value: snapshot.requireData.stars.toString(),
          ),
      ],
    );
  }
}

final class _CommandChip extends StatelessWidget {
  const _CommandChip({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
    ),
  );
}
