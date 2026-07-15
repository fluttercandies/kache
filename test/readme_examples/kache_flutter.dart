import 'package:flutter/material.dart';
import 'package:kache_flutter/kache_flutter.dart';

typedef Profile = ({String name});

Widget createProfileApp({required Future<Profile> Function() fetchProfile}) =>
    KacheScope(
      client: KacheClient(),
      ownership: KacheScopeOwnership.owned,
      child: MaterialApp(
        home: Scaffold(
          body: KacheBuilder<Profile>(
            query: KacheQuery<Profile>.memory(
              key: KacheKey('profile'),
              fetch: (_) => fetchProfile(),
            ),
            builder: (context, snapshot, controller) => snapshot.when(
              idle: () => const SizedBox.shrink(),
              loading: () => const Center(child: CircularProgressIndicator()),
              failed: (_) => Center(
                child: FilledButton(
                  onPressed: controller.load,
                  child: const Text('Try again'),
                ),
              ),
              ready: (profile) => _profileList(
                profile,
                controller,
                refreshing: snapshot.isRefreshing,
              ),
              refreshError: (profile, _) =>
                  _profileList(profile, controller, refreshFailed: true),
            ),
          ),
        ),
      ),
    );

Widget _profileList(
  Profile profile,
  KacheController<Profile> controller, {
  bool refreshing = false,
  bool refreshFailed = false,
}) => RefreshIndicator(
  onRefresh: () async => controller.refresh(),
  child: ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: <Widget>[
      ListTile(
        title: Text(profile.name),
        subtitle: refreshFailed
            ? const Text('Refresh failed - showing cached data')
            : null,
        trailing: refreshing
            ? const CircularProgressIndicator()
            : const Icon(Icons.cloud_done),
      ),
    ],
  ),
);
