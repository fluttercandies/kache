import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kache/kache.dart';

import 'playground_components.dart';
import 'repository_profile.dart';

/// One captured cache event for the activity log.
final class PlaygroundEventEntry {
  /// Creates an entry.
  PlaygroundEventEntry(this.event);

  /// The captured event.
  final KacheEvent event;

  @override
  String toString() {
    final parts = <String>[event.kind.name];
    final debug = event.debugName;
    if (debug != null) {
      parts.add(debug);
    }
    if (event.layer != null) {
      parts.add(event.layer!.name);
    }
    final failure = event.failure;
    if (failure != null) {
      parts.add(failure.kind.name);
    }
    return parts.join(' · ');
  }
}

/// Demonstrates client-level cache operations and the live event stream.
///
/// This tab is identical across all four adapters because it talks directly to
/// [KacheClient], independent of any state management library.
class ActivityPlayground extends StatefulWidget {
  /// Creates the activity playground.
  const ActivityPlayground({
    required this.client,
    required this.peekQuery,
    super.key,
  });

  /// Client whose events and commands are demonstrated.
  final KacheClient client;

  /// Query used for peek/prefetch demonstrations.
  final KacheQuery<RepositoryProfile> peekQuery;

  @override
  State<ActivityPlayground> createState() => _ActivityPlaygroundState();
}

final class _ActivityPlaygroundState extends State<ActivityPlayground> {
  StreamSubscription<KacheEvent>? _subscription;
  final List<PlaygroundEventEntry> _entries = <PlaygroundEventEntry>[];
  String _peekResult = 'Not inspected yet';
  String _lastClientOp = 'No client operation run yet';

  @override
  void initState() {
    super.initState();
    _subscription = widget.client.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onEvent(KacheEvent event) {
    if (!mounted) {
      return;
    }
    setState(() {
      _entries.insert(0, PlaygroundEventEntry(event));
      if (_entries.length > 40) {
        _entries.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
    children: <Widget>[
      PlaygroundSection(
        title: 'Client commands',
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _CommandChip(
              tooltip: 'client.peek(key): synchronous memory read, no I/O',
              label: 'Peek',
              icon: Icons.visibility_outlined,
              onTap: _peek,
            ),
            _CommandChip(
              tooltip: 'client.prefetch(query): load without a handle',
              label: 'Prefetch',
              icon: Icons.download_for_offline_outlined,
              onTap: _prefetch,
            ),
            _CommandChip(
              tooltip: 'client.refreshActive(): refresh all active resources',
              label: 'Refresh active',
              icon: Icons.refresh_rounded,
              onTap: () => _clientOp(
                () => widget.client.refreshActive(),
                'refreshActive',
              ),
            ),
            _CommandChip(
              tooltip: 'client.clearNamespace(...): clear one namespace',
              label: 'Clear namespace',
              icon: Icons.cleaning_services_outlined,
              onTap: () => _clientOp(
                () => widget.client.clearNamespace(
                  KacheNamespace('github-repository'),
                ),
                'clearNamespace',
              ),
            ),
            _CommandChip(
              tooltip: 'client.clear(): clear the whole client',
              label: 'Clear all',
              icon: Icons.delete_sweep_outlined,
              onTap: () => _clientOp(() => widget.client.clear(), 'clear'),
            ),
          ],
        ),
      ),
      PlaygroundSection(
        title: 'Lifecycle toggles',
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _CommandChip(
              tooltip: 'client.pausePolling()',
              label: 'Pause polling',
              icon: Icons.pause_circle_outline,
              onTap: () => _toggle('pausePolling', widget.client.pausePolling),
            ),
            _CommandChip(
              tooltip: 'client.resumePolling()',
              label: 'Resume polling',
              icon: Icons.play_circle_outline,
              onTap: () =>
                  _toggle('resumePolling', widget.client.resumePolling),
            ),
            _CommandChip(
              tooltip: 'client.pauseReconnect()',
              label: 'Pause reconnect',
              icon: Icons.wifi_off_rounded,
              onTap: () =>
                  _toggle('pauseReconnect', widget.client.pauseReconnect),
            ),
            _CommandChip(
              tooltip: 'client.resumeReconnect()',
              label: 'Resume reconnect',
              icon: Icons.wifi_rounded,
              onTap: () =>
                  _toggle('resumeReconnect', widget.client.resumeReconnect),
            ),
          ],
        ),
      ),
      PlaygroundSection(
        title: 'Status',
        child: Wrap(
          spacing: 28,
          runSpacing: 18,
          children: <Widget>[
            PlaygroundStatusItem(
              label: 'Network',
              value: widget.client.networkState == KacheNetworkState.available
                  ? 'Available'
                  : widget.client.networkState == KacheNetworkState.unavailable
                  ? 'Unavailable'
                  : 'Unknown',
            ),
            PlaygroundStatusItem(
              label: 'Client closed',
              value: widget.client.isClosed ? 'Yes' : 'No',
            ),
            PlaygroundStatusItem(label: 'Peek', value: _peekResult),
            PlaygroundStatusItem(label: 'Last op', value: _lastClientOp),
          ],
        ),
      ),
      PlaygroundSection(
        title: 'Events (${_entries.length})',
        child: Container(
          constraints: const BoxConstraints(maxHeight: 280),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _entries.isEmpty
              ? const Center(child: Text('Waiting for events…'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  itemCount: _entries.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, indent: 4),
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            playgroundFormatUtc(entry.event.occurredAt),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(entry.toString())),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    ],
  );

  Future<void> _peek() async {
    final snapshot = widget.client.peek<RepositoryProfile>(
      widget.peekQuery.key,
    );
    setState(() {
      _peekResult = snapshot == null
          ? 'No active entry'
          : '${playgroundPhaseLabel(snapshot.phase)}'
                '${snapshot.hasData ? ' · ${snapshot.requireData.stars} stars' : ''}';
    });
    _snack('peek → $_peekResult');
  }

  Future<void> _prefetch() async {
    await _clientOp(
      () => widget.client.prefetch<RepositoryProfile>(widget.peekQuery),
      'prefetch',
    );
  }

  Future<void> _clientOp(Future<Object?> Function() op, String label) async {
    try {
      final result = await op();
      String detail = 'ok';
      if (result is KacheSnapshot<RepositoryProfile>) {
        detail = playgroundPhaseLabel(result.phase);
      } else if (result is KacheClearResult) {
        detail = result.isSuccess
            ? 'cleared'
            : '${result.failures.length} failure(s)';
      }
      if (!mounted) {
        return;
      }
      setState(() => _lastClientOp = '$label → $detail');
      _snack('$label → $detail');
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _lastClientOp = '$label → error');
      _snack('$label failed: $error');
    }
  }

  void _toggle(String label, void Function() action) {
    action();
    setState(() => _lastClientOp = '$label → ok');
    _snack('$label → ok');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
  final VoidCallback onTap;

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
