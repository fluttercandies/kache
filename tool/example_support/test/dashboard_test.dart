import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache/kache.dart';
import 'package:kache_example_support/kache_example_support.dart';

void main() {
  testWidgets('shows cached data, metadata, refresh progress, and error', (
    tester,
  ) async {
    final profile = _profile();
    final failure = KacheFailure(
      kind: KacheFailureKind.fetch,
      key: KacheKey('github-repository', <Object?>['flutter/flutter']),
      cause: StateError('offline'),
      stackTrace: StackTrace.current,
    );
    final snapshot = KacheSnapshot<RepositoryProfile>.ready(
      data: profile,
      freshness: KacheFreshness.stale,
      source: KacheDataSource.persistence,
      fetchedAt: DateTime.utc(2026, 7, 14, 8, 30),
      isRefreshing: true,
      failure: failure,
      persistence: const KachePersistenceState.persisted(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RepositoryDashboard(
          adapterName: 'Flutter',
          snapshot: snapshot,
          onRefresh: () async => snapshot,
          onClear: () async => KacheSnapshot<RepositoryProfile>.idle(),
          showNetworkImage: false,
        ),
      ),
    );

    expect(find.text('flutter/flutter'), findsOneWidget);
    expect(find.text('170K'), findsOneWidget);
    expect(find.text('29K'), findsOneWidget);
    expect(find.text('12K'), findsOneWidget);
    expect(find.text('Disk cache'), findsOneWidget);
    expect(find.text('Stale'), findsOneWidget);
    expect(
      find.text('Refresh failed. Showing the last cached data.'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('refresh and clear actions call the supplied commands', (
    tester,
  ) async {
    final snapshot = KacheSnapshot<RepositoryProfile>.ready(
      data: _profile(),
      freshness: KacheFreshness.fresh,
      source: KacheDataSource.fetch,
      fetchedAt: DateTime.utc(2026, 7, 14, 8, 30),
    );
    var refreshes = 0;
    var clears = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: RepositoryDashboard(
          adapterName: 'Provider',
          snapshot: snapshot,
          onRefresh: () async {
            refreshes += 1;
            return snapshot;
          },
          onClear: () async {
            clears += 1;
            return KacheSnapshot<RepositoryProfile>.idle();
          },
          showNetworkImage: false,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Refresh repository'));
    await tester.pump();
    await tester.tap(find.byTooltip('Clear cached repository'));
    await tester.pump();

    expect(refreshes, 1);
    expect(clears, 1);
  });

  testWidgets('compact refresh progress does not shift repository content', (
    tester,
  ) async {
    final ready = KacheSnapshot<RepositoryProfile>.ready(
      data: _profile(),
      freshness: KacheFreshness.fresh,
      source: KacheDataSource.fetch,
      fetchedAt: DateTime.utc(2026, 7, 14, 8, 30),
    );
    final refreshing = KacheSnapshot<RepositoryProfile>.ready(
      data: _profile(),
      freshness: KacheFreshness.fresh,
      source: KacheDataSource.fetch,
      fetchedAt: DateTime.utc(2026, 7, 14, 8, 30),
      isRefreshing: true,
    );

    Widget app(KacheSnapshot<RepositoryProfile> snapshot) => MaterialApp(
      home: RepositoryDashboard(
        adapterName: 'Flutter',
        snapshot: snapshot,
        onRefresh: () async => snapshot,
        onClear: () async => KacheSnapshot<RepositoryProfile>.idle(),
        showNetworkImage: false,
        compact: true,
      ),
    );

    await tester.pumpWidget(app(ready));
    final readyTop = tester.getTopLeft(find.text('Flutter repository')).dy;
    await tester.pumpWidget(app(refreshing));
    final refreshingTop = tester.getTopLeft(find.text('Flutter repository')).dy;

    expect(refreshingTop, readyTop);
  });
}

RepositoryProfile _profile() => RepositoryProfile(
  fullName: 'flutter/flutter',
  description: 'Flutter makes it easy to build beautiful apps.',
  htmlUrl: 'https://github.com/flutter/flutter',
  ownerAvatarUrl: 'https://avatars.example/flutter.png',
  stars: 170000,
  forks: 29000,
  openIssues: 12000,
  language: 'Dart',
  updatedAt: DateTime.utc(2026, 7, 14, 8, 30),
);
