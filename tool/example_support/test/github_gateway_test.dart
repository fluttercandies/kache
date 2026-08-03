import 'dart:async';
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

  test('aborts a request when Kache cancellation arrives', () async {
    final client = _AbortUntilTriggeredClient();
    final cancellation = KacheCancellationController();
    final gateway = GitHubRepositoryGateway(client: client);
    addTearDown(client.close);

    final fetch = gateway.fetch(
      KacheFetchContext(cancellation: cancellation.token),
    );
    await client.started.future;
    cancellation.cancel(KacheCancelReason.remove);

    await expectLater(
      fetch,
      throwsA(
        isA<KacheCancelledException>().having(
          (error) => error.reason,
          'reason',
          KacheCancelReason.remove,
        ),
      ),
    );
    expect(client.request, isA<http.AbortableRequest>());
  });

  test(
    'cancels an active response body stream on Kache cancellation',
    () async {
      final listening = Completer<void>();
      var streamCancelled = false;
      final responseBody = StreamController<List<int>>(
        onListen: listening.complete,
        onCancel: () => streamCancelled = true,
      );
      addTearDown(responseBody.close);
      final client = _StreamingClient(
        (request) => http.StreamedResponse(responseBody.stream, 200),
      );
      final cancellation = KacheCancellationController();
      final gateway = GitHubRepositoryGateway(client: client);
      addTearDown(client.close);

      final fetch = gateway.fetch(
        KacheFetchContext(cancellation: cancellation.token),
      );
      await listening.future;
      cancellation.cancel(KacheCancelReason.manual);

      await expectLater(fetch, throwsA(isA<KacheCancelledException>()));
      expect(streamCancelled, isTrue);
      expect(client.request, isA<http.AbortableRequest>());
    },
  );

  test('cancellation does not wait for stalled body cleanup', () async {
    final listening = Completer<void>();
    final cancelStarted = Completer<void>();
    final cleanupGate = Completer<void>();
    final responseBody = StreamController<List<int>>(
      onListen: listening.complete,
      onCancel: () {
        cancelStarted.complete();
        return cleanupGate.future;
      },
    );
    addTearDown(() async {
      if (!cleanupGate.isCompleted) {
        cleanupGate.complete();
      }
      await responseBody.close();
    });
    final client = _StreamingClient(
      (request) => http.StreamedResponse(responseBody.stream, 200),
    );
    final cancellation = KacheCancellationController();
    final gateway = GitHubRepositoryGateway(client: client);
    addTearDown(client.close);

    final fetch = gateway.fetch(
      KacheFetchContext(cancellation: cancellation.token),
    );
    await listening.future;
    cancellation.cancel(KacheCancelReason.manual);

    await expectLater(
      fetch.timeout(const Duration(seconds: 1)),
      throwsA(isA<KacheCancelledException>()),
    );
    expect(cancelStarted.isCompleted, isTrue);
    cleanupGate.complete();
  });

  test('one deadline aborts and cancels a stalled response body', () async {
    final listening = Completer<void>();
    var streamCancelled = false;
    final responseBody = StreamController<List<int>>(
      onListen: listening.complete,
      onCancel: () => streamCancelled = true,
    );
    addTearDown(responseBody.close);
    final client = _StreamingClient(
      (request) => http.StreamedResponse(responseBody.stream, 200),
    );
    final gateway = GitHubRepositoryGateway(
      client: client,
      requestTimeout: Duration.zero,
    );
    addTearDown(client.close);

    final fetch = gateway.fetch(const KacheFetchContext());
    await listening.future;
    await expectLater(fetch, throwsA(isA<TimeoutException>()));
    expect(streamCancelled, isTrue);
    expect(client.request, isA<http.AbortableRequest>());
    await (client.request! as http.AbortableRequest).abortTrigger!;
  });

  test('cancels a declared oversized body without consuming it', () async {
    var listened = false;
    var cancelled = false;
    final responseBody = StreamController<List<int>>(
      onListen: () => listened = true,
      onCancel: () => cancelled = true,
    );
    addTearDown(responseBody.close);
    final client = _StreamingClient(
      (request) =>
          http.StreamedResponse(responseBody.stream, 200, contentLength: 1024),
    );
    final gateway = GitHubRepositoryGateway(
      client: client,
      maxResponseBytes: 128,
    );
    addTearDown(client.close);

    await expectLater(
      gateway.fetch(const KacheFetchContext()),
      throwsA(
        isA<RepositoryRequestException>().having(
          (error) => error.failure,
          'failure',
          RepositoryRequestFailure.responseTooLarge,
        ),
      ),
    );
    expect(listened, isTrue);
    expect(cancelled, isTrue);
  });
  test('cancels non-success response bodies without retaining them', () async {
    var listened = false;
    var cancelled = false;
    final responseBody = StreamController<List<int>>(
      onListen: () => listened = true,
      onCancel: () => cancelled = true,
    );
    addTearDown(responseBody.close);
    final client = _StreamingClient(
      (request) => http.StreamedResponse(responseBody.stream, 503),
    );
    final gateway = GitHubRepositoryGateway(client: client);
    addTearDown(client.close);

    await expectLater(
      gateway.fetch(const KacheFetchContext()),
      throwsA(
        isA<RepositoryRequestException>().having(
          (error) => error.statusCode,
          'statusCode',
          503,
        ),
      ),
    );
    expect(listened, isTrue);
    expect(cancelled, isTrue);
  });

  test(
    'stops streaming as soon as the actual body exceeds its limit',
    () async {
      var emittedChunks = 0;
      final client = _StreamingClient(
        (request) => http.StreamedResponse(
          _countedChunks(() => emittedChunks += 1),
          200,
        ),
      );
      final gateway = GitHubRepositoryGateway(
        client: client,
        maxResponseBytes: 8,
      );
      addTearDown(client.close);

      await expectLater(
        gateway.fetch(const KacheFetchContext()),
        throwsA(
          isA<RepositoryRequestException>().having(
            (error) => error.failure,
            'failure',
            RepositoryRequestFailure.responseTooLarge,
          ),
        ),
      );
      expect(emittedChunks, 2);
    },
  );

  test('sanitizes malformed JSON without retaining its source', () async {
    const sensitivePayload = '{"token":"secret-value",';
    final client = MockClient(
      (request) async => http.Response(sensitivePayload, 200),
    );
    final gateway = GitHubRepositoryGateway(client: client);
    addTearDown(client.close);

    try {
      await gateway.fetch(const KacheFetchContext());
      fail('Expected malformed JSON to fail.');
    } on RepositoryRequestException catch (error) {
      expect(error.failure, RepositoryRequestFailure.invalidPayload);
      expect(error.toString(), isNot(contains('secret-value')));
      final cause = error.cause;
      expect(cause, isA<FormatException>());
      expect((cause! as FormatException).source, isNull);
    }
  });

  test('accepts a valid response exactly at the byte limit', () async {
    final body = utf8.encode(jsonEncode(_githubJson()));
    final client = _StreamingClient(
      (request) => http.StreamedResponse(
        Stream<List<int>>.value(body),
        200,
        contentLength: body.length,
      ),
    );
    final gateway = GitHubRepositoryGateway(
      client: client,
      maxResponseBytes: body.length,
    );
    addTearDown(client.close);

    final profile = await gateway.fetch(const KacheFetchContext());

    expect(profile.fullName, 'flutter/flutter');
  });

  test('validates timeout and response limits at construction', () {
    final client = MockClient((request) async => http.Response('{}', 200));
    addTearDown(client.close);

    expect(
      () => GitHubRepositoryGateway(
        client: client,
        requestTimeout: const Duration(microseconds: -1),
      ),
      throwsArgumentError,
    );
    expect(
      () => GitHubRepositoryGateway(client: client, maxResponseBytes: 0),
      throwsArgumentError,
    );
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

Stream<List<int>> _countedChunks(void Function() onEmit) async* {
  onEmit();
  yield const <int>[1, 2, 3, 4, 5];
  onEmit();
  yield const <int>[6, 7, 8, 9, 10];
  onEmit();
  yield List<int>.filled(1024, 11);
}

final class _StreamingClient extends http.BaseClient {
  _StreamingClient(this._send);

  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request)
  _send;
  http.BaseRequest? request;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    return _send(request);
  }
}

final class _AbortUntilTriggeredClient extends http.BaseClient {
  final Completer<void> started = Completer<void>();
  http.BaseRequest? request;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    started.complete();
    final abortable = request as http.AbortableRequest;
    await abortable.abortTrigger!;
    throw http.RequestAbortedException(request.url);
  }
}
