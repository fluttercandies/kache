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
            builder: (context, snapshot, controller) {
              if (!snapshot.hasData) {
                return Center(
                  child: snapshot.isFailed
                      ? FilledButton(
                          onPressed: controller.load,
                          child: const Text('Try again'),
                        )
                      : const CircularProgressIndicator(),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => controller.refresh(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: <Widget>[
                    ListTile(
                      title: Text(snapshot.requireData.name),
                      subtitle: snapshot.hasFailure
                          ? const Text('Refresh failed - showing cached data')
                          : null,
                      trailing: snapshot.isRefreshing
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.cloud_done),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
