import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:kache/kache.dart';

import 'repository_profile.dart';

/// Fetches a repository profile for a Kache query.
abstract interface class RepositoryGateway {
  /// Fetches the current repository profile.
  Future<RepositoryProfile> fetch(KacheFetchContext context);
}

/// Classifies sanitized GitHub repository request failures.
enum RepositoryRequestFailure {
  /// The server returned a non-success status.
  httpStatus,

  /// The response did not match the required JSON schema.
  invalidPayload,

  /// The response body exceeded the configured byte limit.
  responseTooLarge,
}

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

  /// Sanitized parsing failure for [RepositoryRequestFailure.invalidPayload].
  final Object? cause;

  @override
  String toString() => switch (failure) {
    RepositoryRequestFailure.httpStatus =>
      'Repository request failed with HTTP status $statusCode.',
    RepositoryRequestFailure.invalidPayload =>
      'Repository response did not match the expected schema.',
    RepositoryRequestFailure.responseTooLarge =>
      'Repository response exceeded the configured byte limit.',
  };
}

/// Fetches the Flutter repository from GitHub's public REST API.
final class GitHubRepositoryGateway implements RepositoryGateway {
  /// Creates a gateway with an owned-by-caller HTTP [client].
  GitHubRepositoryGateway({
    required this.client,
    this.requestTimeout = const Duration(seconds: 15),
    this.maxResponseBytes = 256 * 1024,
    Uri? repositoryUri,
  }) : repositoryUri =
           repositoryUri ??
           Uri.https('api.github.com', '/repos/flutter/flutter') {
    if (requestTimeout.isNegative) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'Must not be negative.',
      );
    }
    if (maxResponseBytes <= 0) {
      throw ArgumentError.value(
        maxResponseBytes,
        'maxResponseBytes',
        'Must be positive.',
      );
    }
  }

  /// HTTP client whose lifecycle is managed by the caller.
  final http.Client client;

  /// Maximum duration from starting the request through reading its body.
  final Duration requestTimeout;

  /// Maximum accepted response body size in bytes.
  final int maxResponseBytes;

  /// GitHub repository API endpoint.
  final Uri repositoryUri;

  /// Fetches and validates the current repository profile.
  @override
  Future<RepositoryProfile> fetch(KacheFetchContext context) async {
    context.throwIfCancelled();
    final abort = _RepositoryAbortSignal();
    final timeout = Timer(
      requestTimeout,
      () => abort.abort(_RepositoryAbortReason.timeout),
    );
    unawaited(
      context.cancellation.whenCancelled.then<void>(
        (_) => abort.abort(_RepositoryAbortReason.cancellation),
      ),
    );
    final request =
        http.AbortableRequest('GET', repositoryUri, abortTrigger: abort.future)
          ..headers.addAll(const <String, String>{
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          });

    late final Uint8List bodyBytes;
    http.StreamedResponse? unconsumedResponse;
    try {
      final response = await _awaitOrAbort(
        Future<http.StreamedResponse>.sync(() => client.send(request)),
        abort: abort,
        context: context,
        requestTimeout: requestTimeout,
        repositoryUri: repositoryUri,
      );
      unconsumedResponse = response;
      if (context.isCancelled) {
        _cancelUnconsumedBody(response.stream);
        unconsumedResponse = null;
        context.throwIfCancelled();
      }
      if (response.statusCode != 200) {
        _cancelUnconsumedBody(response.stream);
        unconsumedResponse = null;
        throw RepositoryRequestException(
          failure: RepositoryRequestFailure.httpStatus,
          statusCode: response.statusCode,
        );
      }
      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > maxResponseBytes) {
        _cancelUnconsumedBody(response.stream);
        unconsumedResponse = null;
        abort.abort(_RepositoryAbortReason.responseTooLarge);
        throw const RepositoryRequestException(
          failure: RepositoryRequestFailure.responseTooLarge,
        );
      }
      unconsumedResponse = null;
      bodyBytes = await _readBoundedBody(
        response.stream,
        maxResponseBytes: maxResponseBytes,
        abort: abort,
        context: context,
        requestTimeout: requestTimeout,
        repositoryUri: repositoryUri,
      );
    } on http.RequestAbortedException catch (error, stackTrace) {
      _throwMappedAbort(
        error,
        stackTrace,
        abort: abort,
        context: context,
        requestTimeout: requestTimeout,
      );
    } finally {
      final response = unconsumedResponse;
      if (response != null) {
        _cancelUnconsumedBody(response.stream);
      }
      timeout.cancel();
      abort.finish();
    }

    context.throwIfCancelled();
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes));
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Repository response must be an object.');
      }
      final profile = RepositoryProfile.fromGitHubJson(decoded);
      context.throwIfCancelled();
      return profile;
    } on KacheCancelledException {
      rethrow;
    } on Object catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const RepositoryRequestException(
          failure: RepositoryRequestFailure.invalidPayload,
          cause: FormatException('Repository payload parsing failed.'),
        ),
        stackTrace,
      );
    }
  }
}

void _cancelUnconsumedBody(Stream<List<int>> stream) {
  try {
    final subscription = stream.listen(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    final cancellation = subscription.cancel();
    unawaited(
      cancellation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  } on Object {
    // The status, size, cancellation, or transport failure remains primary.
  }
}

enum _RepositoryAbortReason { cancellation, timeout, responseTooLarge }

final class _RepositoryAbortSignal {
  final Completer<void> _completer = Completer<void>();
  _RepositoryAbortReason? reason;

  Future<void> get future => _completer.future;

  void abort(_RepositoryAbortReason nextReason) {
    if (_completer.isCompleted) {
      return;
    }
    reason = nextReason;
    _completer.complete();
  }

  void finish() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

Future<T> _awaitOrAbort<T>(
  Future<T> operation, {
  required _RepositoryAbortSignal abort,
  required KacheFetchContext context,
  required Duration requestTimeout,
  required Uri repositoryUri,
}) => Future.any<T>(<Future<T>>[
  operation,
  abort.future.then<T>((_) {
    context.throwIfCancelled();
    return switch (abort.reason) {
      _RepositoryAbortReason.timeout => throw TimeoutException(
        'Repository request timed out.',
        requestTimeout,
      ),
      _RepositoryAbortReason.responseTooLarge =>
        throw const RepositoryRequestException(
          failure: RepositoryRequestFailure.responseTooLarge,
        ),
      _RepositoryAbortReason.cancellation => throw KacheCancelledException(
        context.cancellation.reason!,
      ),
      null => throw http.RequestAbortedException(repositoryUri),
    };
  }),
]);

Future<Uint8List> _readBoundedBody(
  Stream<List<int>> stream, {
  required int maxResponseBytes,
  required _RepositoryAbortSignal abort,
  required KacheFetchContext context,
  required Duration requestTimeout,
  required Uri repositoryUri,
}) async {
  final bytes = BytesBuilder(copy: false);
  final iterator = StreamIterator<List<int>>(stream);
  try {
    while (await _awaitOrAbort(
      iterator.moveNext(),
      abort: abort,
      context: context,
      requestTimeout: requestTimeout,
      repositoryUri: repositoryUri,
    )) {
      final chunk = iterator.current;
      if (chunk.length > maxResponseBytes - bytes.length) {
        abort.abort(_RepositoryAbortReason.responseTooLarge);
        throw const RepositoryRequestException(
          failure: RepositoryRequestFailure.responseTooLarge,
        );
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  } finally {
    if (abort.reason == null) {
      await iterator.cancel();
    } else {
      try {
        final cancellation = iterator.cancel();
        unawaited(
          cancellation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        );
      } on Object {
        // The selected cancellation, timeout, or size failure remains primary.
      }
    }
  }
}

Never _throwMappedAbort(
  http.RequestAbortedException error,
  StackTrace stackTrace, {
  required _RepositoryAbortSignal abort,
  required KacheFetchContext context,
  required Duration requestTimeout,
}) {
  context.throwIfCancelled();
  switch (abort.reason) {
    case _RepositoryAbortReason.timeout:
      throw TimeoutException('Repository request timed out.', requestTimeout);
    case _RepositoryAbortReason.responseTooLarge:
      throw const RepositoryRequestException(
        failure: RepositoryRequestFailure.responseTooLarge,
      );
    case _RepositoryAbortReason.cancellation:
      context.throwIfCancelled();
      throw StateError('Cancellation token did not expose its reason.');
    case null:
      Error.throwWithStackTrace(error, stackTrace);
  }
}
