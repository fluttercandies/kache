import 'package:flutter/material.dart';
import 'package:kache/kache.dart';

import 'repository_profile.dart';

part 'repository_dashboard_components.dart';

/// Executes a cache command for the repository query.
typedef RepositoryCommand = Future<KacheSnapshot<RepositoryProfile>> Function();

/// Shared production UI used by all four state management examples.
class RepositoryDashboard extends StatefulWidget {
  /// Creates the repository cache workbench.
  const RepositoryDashboard({
    required this.adapterName,
    required this.snapshot,
    required this.onRefresh,
    required this.onClear,
    this.showNetworkImage = true,
    this.compact = false,
    super.key,
  });

  /// Adapter name shown beneath the product name.
  final String adapterName;

  /// Complete cache state rendered by this workbench.
  final KacheSnapshot<RepositoryProfile> snapshot;

  /// Forces a repository refresh.
  final RepositoryCommand onRefresh;

  /// Removes the cached repository value.
  final RepositoryCommand onClear;

  /// Whether the real GitHub avatar should be loaded from the network.
  final bool showNetworkImage;

  /// When true, renders without its own [Scaffold]/[AppBar] so the dashboard
  /// can be embedded inside an outer scaffold (e.g. a playground tab). The
  /// refresh/clear actions become an inline control row instead of an app bar.
  final bool compact;

  @override
  State<RepositoryDashboard> createState() => _RepositoryDashboardState();
}

final class _RepositoryDashboardState extends State<RepositoryDashboard> {
  bool _commandActive = false;

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    if (widget.compact) {
      // Embedded mode: no own Scaffold/AppBar. The playground shell owns the
      // app bar and tabs; refresh/clear become an inline control row.
      return Column(
        children: <Widget>[
          SizedBox(
            height: 3,
            child: snapshot.isRefreshing
                ? const LinearProgressIndicator(minHeight: 3)
                : const SizedBox.expand(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
            child: Row(
              children: <Widget>[
                Text(
                  '${widget.adapterName} repository',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh repository',
                  onPressed: snapshot.isRefreshing || _commandActive
                      ? null
                      : () => _runCommand(
                          widget.onRefresh,
                          successMessage: 'Repository refreshed',
                        ),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Clear cached repository',
                  onPressed: _commandActive
                      ? null
                      : () => _runCommand(
                          widget.onClear,
                          successMessage: 'Cached repository cleared',
                        ),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _buildBody(context, snapshot),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Kache Lab'),
            Text(
              '${widget.adapterName} adapter',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh repository',
            onPressed: snapshot.isRefreshing || _commandActive
                ? null
                : () => _runCommand(
                    widget.onRefresh,
                    successMessage: 'Repository refreshed',
                  ),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Clear cached repository',
            onPressed: _commandActive
                ? null
                : () => _runCommand(
                    widget.onClear,
                    successMessage: 'Cached repository cleared',
                  ),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: SizedBox(
            height: 3,
            child: snapshot.isRefreshing
                ? const LinearProgressIndicator(minHeight: 3)
                : const SizedBox.expand(),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _buildBody(context, snapshot),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    KacheSnapshot<RepositoryProfile> snapshot,
  ) => snapshot.when(
    idle: () => _EmptyState(
      key: const ValueKey<String>('idle'),
      icon: Icons.inventory_2_outlined,
      title: 'No cached repository',
      message: 'Refresh to load the current repository state.',
      actionLabel: 'Load repository',
      onAction: _commandActive
          ? null
          : () => _runCommand(
              widget.onRefresh,
              successMessage: 'Repository refreshed',
            ),
    ),
    loading: () => const _EmptyState(
      key: ValueKey<String>('loading'),
      icon: Icons.downloading_rounded,
      title: 'Loading repository',
      message: 'Checking memory, disk cache, and GitHub.',
    ),
    failed: (_) => _EmptyState(
      key: const ValueKey<String>('failure'),
      icon: Icons.cloud_off_rounded,
      title: 'Repository unavailable',
      message: 'Check the connection and retry.',
      actionLabel: 'Retry refresh',
      onAction: _commandActive
          ? null
          : () => _runCommand(
              widget.onRefresh,
              successMessage: 'Repository refreshed',
            ),
    ),
    ready: (profile) => _RepositoryBody(
      key: ValueKey<int>(snapshot.revision),
      profile: profile,
      snapshot: snapshot,
      showNetworkImage: widget.showNetworkImage,
    ),
    refreshError: (profile, _) => _RepositoryBody(
      key: ValueKey<int>(snapshot.revision),
      profile: profile,
      snapshot: snapshot,
      showNetworkImage: widget.showNetworkImage,
    ),
  );

  Future<void> _runCommand(
    RepositoryCommand command, {
    required String successMessage,
  }) async {
    if (_commandActive) {
      return;
    }
    setState(() => _commandActive = true);
    try {
      final result = await command();
      if (!mounted) {
        return;
      }
      final message = result.failure == null
          ? successMessage
          : result.hasData
          ? 'Refresh failed. Cached data remains available.'
          : 'Repository request failed.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('The command could not be completed.'),
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _commandActive = false);
      }
    }
  }
}
