import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kache/kache.dart';

import 'repository_profile.dart';

/// Fetches a repository profile for a Kache query.
abstract interface class RepositoryGateway {
  /// Fetches the current repository profile.
  Future<RepositoryProfile> fetch(KacheFetchContext context);
}

/// Classifies sanitized GitHub repository request failures.
enum RepositoryRequestFailure { httpStatus, invalidPayload }

/// A sanitized repository request failure that never retains response bodies.
final class RepositoryRequestException implements Exception {
  /// Creates a request failure.
  const RepositoryRequestException({
    required this.failure,
    this.statusCode,
    this.cause,
  });

  /// Failure category.
  final RepositoryRequestFailure failure;

  /// HTTP status for [RepositoryRequestFailure.httpStatus].
  final int? statusCode;

  /// Parsing failure for [RepositoryRequestFailure.invalidPayload].
  final Object? cause;

  @override
  String toString() => switch (failure) {
    RepositoryRequestFailure.httpStatus =>
      'Repository request failed with HTTP status $statusCode.',
    RepositoryRequestFailure.invalidPayload =>
      'Repository response did not match the expected schema.',
  };
}

/// Fetches the Flutter repository from GitHub's public REST API.
final class GitHubRepositoryGateway implements RepositoryGateway {
  /// Creates a gateway with an owned-by-caller HTTP [client].
  GitHubRepositoryGateway({
    required this.client,
    this.requestTimeout = const Duration(seconds: 15),
    Uri? repositoryUri,
  }) : repositoryUri =
           repositoryUri ??
           Uri.https('api.github.com', '/repos/flutter/flutter');

  /// HTTP client whose lifecycle is managed by the caller.
  final http.Client client;

  /// Maximum duration of one request.
  final Duration requestTimeout;

  /// GitHub repository API endpoint.
  final Uri repositoryUri;

  /// Fetches and validates the current repository profile.
  @override
  Future<RepositoryProfile> fetch(KacheFetchContext context) async {
    context.throwIfCancelled();
    final response = await client
        .get(
          repositoryUri,
          headers: const <String, String>{
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(requestTimeout);
    context.throwIfCancelled();
    if (response.statusCode != 200) {
      throw RepositoryRequestException(
        failure: RepositoryRequestFailure.httpStatus,
        statusCode: response.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Repository response must be an object.');
      }
      final profile = RepositoryProfile.fromGitHubJson(decoded);
      context.throwIfCancelled();
      return profile;
    } on KacheCancelledException {
      rethrow;
    } on Object catch (error) {
      throw RepositoryRequestException(
        failure: RepositoryRequestFailure.invalidPayload,
        cause: error,
      );
    }
  }
}
