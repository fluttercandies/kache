import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kache_example_support/kache_example_support.dart';

void main() {
  test('parses the required GitHub repository fields', () {
    final profile = RepositoryProfile.fromGitHubJson(_githubJson());

    expect(profile.fullName, 'flutter/flutter');
    expect(profile.ownerAvatarUrl, 'https://avatars.example/flutter.png');
    expect(profile.stars, 170000);
    expect(profile.forks, 29000);
    expect(profile.openIssues, 12000);
    expect(profile.updatedAt, DateTime.utc(2026, 7, 14, 8, 30));
  });

  test('rejects a payload with missing or invalid fields', () {
    final payload = _githubJson()..['stargazers_count'] = 'many';

    expect(
      () => RepositoryProfile.fromGitHubJson(payload),
      throwsA(isA<FormatException>()),
    );
  });

  test('Hive codec round-trips the stable persisted representation', () {
    final profile = RepositoryProfile.fromGitHubJson(_githubJson());

    final bytes = repositoryProfileCodec.encode(profile);
    final decoded = repositoryProfileCodec.decode(bytes);

    expect(decoded, profile);
    expect(jsonDecode(utf8.decode(bytes)), isA<Map<String, Object?>>());
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
