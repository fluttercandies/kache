import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kache/kache.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

final class BenchmarkResult {
  const BenchmarkResult({
    required this.name,
    required this.operations,
    required this.elapsed,
    this.dimensions = const <String, num>{},
  });

  final String name;
  final int operations;
  final Duration elapsed;
  final Map<String, num> dimensions;

  double get operationsPerSecond =>
      operations *
      Duration.microsecondsPerSecond /
      elapsed.inMicroseconds.clamp(1, 1 << 62);

  String format() {
    final details = dimensions.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    return '$name operations=$operations elapsed_us=${elapsed.inMicroseconds} '
        'ops_per_second=${operationsPerSecond.toStringAsFixed(1)}'
        '${details.isEmpty ? '' : ' $details'}';
  }
}

Future<Map<String, BenchmarkResult>> runKacheBenchmarks({
  int iterations = 20000,
  int keyCount = 128,
}) async {
  if (iterations <= 0 || keyCount <= 0) {
    throw ArgumentError('iterations and keyCount must be positive.');
  }
  final results = <String, BenchmarkResult>{};
  results['core.hot_peek'] = await _hotPeek(iterations);
  results['core.multi_key_peek'] = await _multiKeyPeek(iterations, keyCount);
  results['core.single_flight'] = await _singleFlight(keyCount);
  results['hive_ce.codec_round_trip'] = _codecRoundTrip(iterations);
  return results;
}

Future<BenchmarkResult> _hotPeek(int iterations) async {
  final client = KacheClient();
  final key = KacheKey('benchmark-hot');
  final resource = client.watch(
    KacheQuery<int>.memory(key: key, policy: KachePolicy.cacheOnly()),
  );
  await resource.setData(1);
  var checksum = 0;
  final stopwatch = Stopwatch()..start();
  for (var index = 0; index < iterations; index++) {
    checksum += client.peek<int>(key)!.requireData;
  }
  stopwatch.stop();
  resource.dispose();
  await client.close();
  return BenchmarkResult(
    name: 'core.hot_peek',
    operations: iterations,
    elapsed: stopwatch.elapsed,
    dimensions: <String, num>{'checksum': checksum},
  );
}

Future<BenchmarkResult> _multiKeyPeek(int iterations, int keyCount) async {
  final client = KacheClient();
  final keys = List<KacheKey>.generate(
    keyCount,
    (index) => KacheKey('benchmark-many', <Object?>[index]),
  );
  final resources = <KacheResource<int>>[];
  for (var index = 0; index < keyCount; index++) {
    final resource = client.watch(
      KacheQuery<int>.memory(key: keys[index], policy: KachePolicy.cacheOnly()),
    );
    resources.add(resource);
    await resource.setData(index);
  }
  var checksum = 0;
  final stopwatch = Stopwatch()..start();
  for (var pass = 0; pass < iterations; pass++) {
    for (final key in keys) {
      checksum += client.peek<int>(key)!.requireData;
    }
  }
  stopwatch.stop();
  for (final resource in resources) {
    resource.dispose();
  }
  await client.close();
  return BenchmarkResult(
    name: 'core.multi_key_peek',
    operations: iterations * keyCount,
    elapsed: stopwatch.elapsed,
    dimensions: <String, num>{'keys': keyCount, 'checksum': checksum},
  );
}

Future<BenchmarkResult> _singleFlight(int handleCount) async {
  final gate = Completer<int>();
  var fetchCount = 0;
  final client = KacheClient();
  final query = KacheQuery<int>.memory(
    key: KacheKey('benchmark-flight'),
    fetch: (_) {
      fetchCount += 1;
      return gate.future;
    },
  );
  final resources = List<KacheResource<int>>.generate(
    handleCount,
    (_) => client.watch(query),
  );
  final stopwatch = Stopwatch()..start();
  final refreshes = resources.map((resource) => resource.refresh()).toList();
  gate.complete(1);
  await Future.wait(refreshes);
  stopwatch.stop();
  for (final resource in resources) {
    resource.dispose();
  }
  await client.close();
  if (fetchCount != 1) {
    throw StateError('Single-flight executed $fetchCount fetches.');
  }
  return BenchmarkResult(
    name: 'core.single_flight',
    operations: handleCount,
    elapsed: stopwatch.elapsed,
    dimensions: <String, num>{'handles': handleCount, 'fetchCount': fetchCount},
  );
}

BenchmarkResult _codecRoundTrip(int iterations) {
  final codec = HiveCeCodec<_Payload>(
    encode: (value) => Uint8List.fromList(
      utf8.encode(jsonEncode(<String, Object?>{'id': value.id, 'n': value.n})),
    ),
    decode: (bytes) {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      return _Payload(json['id']! as String, json['n']! as int);
    },
  );
  const payload = _Payload('flutter/flutter', 177900);
  var checksum = 0;
  final stopwatch = Stopwatch()..start();
  for (var index = 0; index < iterations; index++) {
    checksum += codec.decode(codec.encode(payload)).n;
  }
  stopwatch.stop();
  return BenchmarkResult(
    name: 'hive_ce.codec_round_trip',
    operations: iterations,
    elapsed: stopwatch.elapsed,
    dimensions: <String, num>{'checksum': checksum},
  );
}

final class _Payload {
  const _Payload(this.id, this.n);

  final String id;
  final int n;
}

Future<void> main() async {
  stdout.writeln('kache.benchmark.v=1');
  final results = await runKacheBenchmarks();
  for (final result in results.values) {
    stdout.writeln(result.format());
  }
}
