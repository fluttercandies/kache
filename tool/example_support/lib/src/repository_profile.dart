import 'dart:convert';
import 'dart:typed_data';

import 'package:kache_hive_ce/kache_hive_ce.dart';

/// Repository data displayed and persisted by every example application.
final class RepositoryProfile {
  /// Creates an immutable repository profile.
  const RepositoryProfile({
    required this.fullName,
    required this.description,
    required this.htmlUrl,
    required this.ownerAvatarUrl,
    required this.stars,
    required this.forks,
    required this.openIssues,
    required this.language,
    required this.updatedAt,
  });

  /// Parses the strict subset of the GitHub repository response that is used.
  factory RepositoryProfile.fromGitHubJson(Map<String, Object?> json) =>
      RepositoryProfile(
        fullName: _requiredString(json, 'full_name'),
        description: _nullableString(json, 'description'),
        htmlUrl: _requiredString(json, 'html_url'),
        ownerAvatarUrl: _requiredString(
          _requiredMap(json, 'owner'),
          'avatar_url',
        ),
        stars: _requiredInt(json, 'stargazers_count'),
        forks: _requiredInt(json, 'forks_count'),
        openIssues: _requiredInt(json, 'open_issues_count'),
        language: _nullableString(json, 'language'),
        updatedAt: _requiredDateTime(json, 'updated_at'),
      );

  factory RepositoryProfile._fromPersistedJson(Map<String, Object?> json) =>
      RepositoryProfile(
        fullName: _requiredString(json, 'fullName'),
        description: _nullableString(json, 'description'),
        htmlUrl: _requiredString(json, 'htmlUrl'),
        ownerAvatarUrl: _requiredString(json, 'ownerAvatarUrl'),
        stars: _requiredInt(json, 'stars'),
        forks: _requiredInt(json, 'forks'),
        openIssues: _requiredInt(json, 'openIssues'),
        language: _nullableString(json, 'language'),
        updatedAt: _requiredDateTime(json, 'updatedAt'),
      );

  /// GitHub repository name in `owner/name` form.
  final String fullName;

  /// Optional repository description.
  final String? description;

  /// Browser URL for the repository.
  final String htmlUrl;

  /// GitHub owner avatar URL.
  final String ownerAvatarUrl;

  /// Current stargazer count.
  final int stars;

  /// Current fork count.
  final int forks;

  /// Current open issue and pull request count reported by GitHub.
  final int openIssues;

  /// Primary language reported by GitHub.
  final String? language;

  /// Last repository update timestamp reported by GitHub.
  final DateTime updatedAt;

  Map<String, Object?> _toPersistedJson() => <String, Object?>{
    'fullName': fullName,
    'description': description,
    'htmlUrl': htmlUrl,
    'ownerAvatarUrl': ownerAvatarUrl,
    'stars': stars,
    'forks': forks,
    'openIssues': openIssues,
    'language': language,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepositoryProfile &&
          fullName == other.fullName &&
          description == other.description &&
          htmlUrl == other.htmlUrl &&
          ownerAvatarUrl == other.ownerAvatarUrl &&
          stars == other.stars &&
          forks == other.forks &&
          openIssues == other.openIssues &&
          language == other.language &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    fullName,
    description,
    htmlUrl,
    ownerAvatarUrl,
    stars,
    forks,
    openIssues,
    language,
    updatedAt,
  );
}

/// Stable JSON codec used by the example Hive CE binding.
final HiveCeCodec<RepositoryProfile>
repositoryProfileCodec = HiveCeCodec<RepositoryProfile>(
  encode: (profile) =>
      Uint8List.fromList(utf8.encode(jsonEncode(profile._toPersistedJson()))),
  decode: (bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Persisted repository must be an object.');
    }
    return RepositoryProfile._fromPersistedJson(decoded);
  },
);

Map<String, Object?> _requiredMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, Object?>) {
    return value;
  }
  throw FormatException('Repository field "$key" must be an object.');
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('Repository field "$key" must be a string.');
}

String? _nullableString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is String) {
    return value as String?;
  }
  throw FormatException('Repository field "$key" must be a string or null.');
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int && value >= 0) {
    return value;
  }
  throw FormatException('Repository field "$key" must be a non-negative int.');
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Repository field "$key" must be an ISO timestamp.');
  }
  return parsed.toUtc();
}
