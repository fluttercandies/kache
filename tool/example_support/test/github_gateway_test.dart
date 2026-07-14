import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kache/kache.dart';
import 'package:kache_example_support/kache_example_support.dart';

void main() {
  test('fetches and validates the real GitHub response shape', () async {
    final client = MockClient((request) async {
      expect(
        request.url,
        Uri.https('api.github.com', '/repos/flutter/flutter'),
      );
      expect(request.headers['Accept'], 'application/vnd.github+json');
      return http.Response(
        jsonEncode(_githubJson()),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final gateway = GitHubRepositoryGateway(client: client);
    addTearDown(client.close);

    final profile = await gateway.fetch(const KacheFetchContext());

    expect(profile.fullName, 'flutter/flutter');
  });

  test('reports status without retaining the response body', () async {
    final client = MockClient(
      (request) async => http.Response('sensitive upstream body', 503),
    );
    final gateway = GitHubRepositoryGateway(client: client);
    addTearDown(client.close);

    expect(
      () => gateway.fetch(const KacheFetchContext()),
      throwsA(
        isA<RepositoryRequestException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having(
              (error) => error.toString(),
              'message',
              isNot(contains('sensitive upstream body')),
            ),
      ),
    );
  });

  test('checks cooperative cancellation before issuing a request', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      return http.Response('{}', 200);
    });
    final cancellation = KacheCancellationController()..cancel();
    final gateway = GitHubRepositoryGateway(client: client);
    addTearDown(client.close);

    expect(
      () => gateway.fetch(KacheFetchContext(cancellation: cancellation.token)),
      throwsA(isA<KacheCancelledException>()),
    );
    expect(requests, 0);
  });
}

Map<String, Object?> _githubJson() => <String, Object?>{
  'full_name': 'flutter/flutter',
  'description': 'Flutter makes it easy to build beautiful apps.',
  'html_url': 'https://github.com/flutter/flutter',
  'stargazers_count': 170000,
  'forks_count': 29000,
  'open_issues_count': 12000,
  'language': 'Dart',
  'updated_at': '2026-07-14T08:30:00Z',
  'owner': <String, Object?>{
    'avatar_url': 'https://avatars.example/flutter.png',
  },
};
