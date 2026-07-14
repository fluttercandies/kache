import 'package:flutter/material.dart';

/// Slot builders for the non-repository playground tabs.
///
/// Each host adapter fills these with adapter-specific widgets that subscribe
/// to the runtime queries; the Repository tab reuses the existing dashboard so
/// the example test contracts stay unchanged. [persistence] is optional because
/// it is adapter-agnostic and may be omitted by adapters that only want the
/// core playground.
class PlaygroundSlots {
  /// Creates slot builders.
  const PlaygroundSlots({
    required this.commands,
    required this.policies,
    required this.activity,
    this.persistence,
  });

  /// Commands tab content.
  final WidgetBuilder commands;

  /// Policies tab content.
  final WidgetBuilder policies;

  /// Activity tab content.
  final WidgetBuilder activity;

  /// Optional persistence tab content (shown when non-null).
  final WidgetBuilder? persistence;
}

/// Host adapter name shown in the playground app bar.
typedef PlaygroundAdapterLabel = String;

/// Builds the Repository tab content (the existing dashboard).
typedef PlaygroundRepositoryBuilder = Widget Function(BuildContext context);

/// Multi-tab scaffold shared by all four example apps.
///
/// The Repository tab keeps its dashboard (and therefore the strings the
/// example tests assert on); the other three tabs are supplied by the host
/// adapter through [PlaygroundSlots].
class KachePlayground extends StatelessWidget {
  /// Creates the playground shell.
  const KachePlayground({
    required this.adapterName,
    required this.repository,
    required this.slots,
    super.key,
  });

  /// Adapter label, e.g. `Flutter`.
  final PlaygroundAdapterLabel adapterName;

  /// Builds the Repository tab.
  final PlaygroundRepositoryBuilder repository;

  /// Builds the other three tabs.
  final PlaygroundSlots slots;

  @override
  Widget build(BuildContext context) {
    final hasPersistence = slots.persistence != null;
    return DefaultTabController(
      length: hasPersistence ? 5 : 4,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 20,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Kache Lab'),
              Text(
                '$adapterName adapter · API playground',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          bottom: TabBar(
            tabAlignment: TabAlignment.start,
            isScrollable: true,
            tabs: <Widget>[
              const Tab(text: 'Repository'),
              if (hasPersistence) const Tab(text: 'Persistence'),
              const Tab(text: 'Commands'),
              const Tab(text: 'Policies'),
              const Tab(text: 'Activity'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            repository(context),
            if (hasPersistence) Builder(builder: slots.persistence!),
            Builder(builder: slots.commands),
            Builder(builder: slots.policies),
            Builder(builder: slots.activity),
          ],
        ),
      ),
    );
  }
}
