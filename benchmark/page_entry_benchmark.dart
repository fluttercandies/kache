import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kache/kache.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

import 'kache_benchmark.dart';

/// Payload tiers measured by the page-entry benchmarks, in encoded bytes.
const Map<String, int> pageEntryTiers = <String, int>{
  '4k': 4 * 1024,
  '256k': 256 * 1024,
  '2m': 2 * 1024 * 1024,
};

/// Measures the persistence and page-entry paths that run while a page opens.
///
/// Synchronous figures are the time spent before the first `await` returns
/// control to the caller, which is the work a widget build pays for directly.
Future<Map<String, BenchmarkResult>> runPageEntryBenchmarks({
  required int samples,
}) async {
  if (samples <= 0) {
    throw ArgumentError.value(samples, 'samples', 'Must be positive.');
  }
  final directory = await Directory.systemTemp.createTemp('kache_bench_');
  try {
    final results = <String, BenchmarkResult>{};
    var boxIndex = 0;
    for (final tier in pageEntryTiers.entries) {
      final data = _itemsOfSize(tier.value);
      final store = await HiveCeKacheStore.open(
        boxName: 'bench_${boxIndex++}',
        path: directory.path,
      );
      try {
        final binding = store.bind<List<BenchmarkItem>>(
          codecId: 'benchmark.items.v1',
          codec: benchmarkItemsCodec,
        );
        results['hive_ce.write_sync.${tier.key}'] = await _writeSync(
          store,
          binding,
          data,
          samples,
          tier.key,
        );
        results['hive_ce.read_sync.${tier.key}'] = await _readSync(
          store,
          binding,
          samples,
          tier.key,
        );
        results['core.listen_sync.${tier.key}'] = await _listenSync(
          store,
          binding,
          samples,
          tier.key,
        );
      } finally {
        await store.close();
      }
    }
    results['core.page_entry_emissions'] = await _pageEntryEmissions(
      directory,
      'bench_${boxIndex++}',
    );
    for (final tier in pageEntryTiers.entries) {
      results['hive_ce.box_open.${tier.key}'] = await _boxOpen(
        directory,
        'bench_${boxIndex++}',
        tier.value,
        samples,
      );
    }
    return results;
  } finally {
    await directory.delete(recursive: true);
  }
}

final KacheKey _pageKey = KacheKey('benchmark-page', <Object?>[1]);

KachePersistedEntry<List<BenchmarkItem>> _entryOf(List<BenchmarkItem> data) =>
    KachePersistedEntry<List<BenchmarkItem>>(
      data: data,
      metadata: KachePersistedMetadata(fetchedAt: DateTime.now()),
    );

Future<BenchmarkResult> _writeSync(
  HiveCeKacheStore store,
  HiveCeBinding<List<BenchmarkItem>> binding,
  List<BenchmarkItem> data,
  int samples,
  String tier,
) async {
  final entry = _entryOf(data);
  // The first write creates the record; later samples overwrite it the way a
  // background refresh does.
  await store.write(key: _pageKey, binding: binding, entry: entry);
  final timings = await _sample(
    samples,
    () => store.write(key: _pageKey, binding: binding, entry: entry),
  );
  return timings.toResult('hive_ce.write_sync.$tier', <String, num>{
    'record_bytes': _recordBytes(store),
  });
}

Future<BenchmarkResult> _readSync(
  HiveCeKacheStore store,
  HiveCeBinding<List<BenchmarkItem>> binding,
  int samples,
  String tier,
) async {
  final timings = await _sample(
    samples,
    () => store.read(key: _pageKey, binding: binding),
  );
  return timings.toResult('hive_ce.read_sync.$tier', <String, num>{
    'record_bytes': _recordBytes(store),
  });
}

Future<BenchmarkResult> _listenSync(
  HiveCeKacheStore store,
  HiveCeBinding<List<BenchmarkItem>> binding,
  int samples,
  String tier,
) async {
  final syncTimes = <int>[];
  final totalTimes = <int>[];
  for (var index = 0; index < samples; index++) {
    final client = KacheClient(persistence: store);
    final gate = Completer<List<BenchmarkItem>>();
    final resource = client.watch(
      KacheQuery<List<BenchmarkItem>>.persisted(
        key: _pageKey,
        binding: binding,
        policy: KachePolicy.staleWhileRevalidate(),
        fetch: (_) => gate.future,
      ),
    );
    final cached = Completer<void>();
    final stopwatch = Stopwatch()..start();
    final subscription = resource.stream.listen((snapshot) {
      if (snapshot.source == KacheDataSource.persistence &&
          !cached.isCompleted) {
        cached.complete();
      }
    });
    syncTimes.add(stopwatch.elapsedMicroseconds);
    await cached.future;
    totalTimes.add(stopwatch.elapsedMicroseconds);
    await subscription.cancel();
    resource.dispose();
    await client.close(drainWrites: false);
  }
  return _Timings(syncTimes, totalTimes).toResult('core.listen_sync.$tier');
}

Future<BenchmarkResult> _pageEntryEmissions(
  Directory directory,
  String boxName,
) async {
  final store = await HiveCeKacheStore.open(
    boxName: boxName,
    path: directory.path,
  );
  try {
    final binding = store.bind<List<BenchmarkItem>>(
      codecId: 'benchmark.items.v1',
      codec: benchmarkItemsCodec,
    );
    final data = _itemsOfSize(pageEntryTiers['4k']!);
    await store.write(key: _pageKey, binding: binding, entry: _entryOf(data));
    final client = KacheClient(persistence: store);
    final gate = Completer<List<BenchmarkItem>>();
    final resource = client.watch(
      KacheQuery<List<BenchmarkItem>>.persisted(
        key: _pageKey,
        binding: binding,
        policy: KachePolicy.staleWhileRevalidate(),
        fetch: (_) => gate.future,
      ),
    );
    final revisions = <int>[];
    final persisted = Completer<void>();
    final stopwatch = Stopwatch()..start();
    final subscription = resource.stream.listen((snapshot) {
      revisions.add(snapshot.revision);
      if (snapshot.source == KacheDataSource.fetch &&
          snapshot.persistence?.phase == KachePersistencePhase.persisted &&
          !persisted.isCompleted) {
        persisted.complete();
      }
    });
    // A ValueListenable adapter starts from this synchronously available
    // snapshot; delivered events at or below it are stale replays.
    final initialRevision = resource.snapshot.revision;
    await Future<void>.delayed(Duration.zero);
    gate.complete(data);
    await persisted.future;
    stopwatch.stop();
    await subscription.cancel();
    resource.dispose();
    await client.close();
    return BenchmarkResult(
      name: 'core.page_entry_emissions',
      operations: revisions.length,
      elapsed: stopwatch.elapsed,
      dimensions: <String, num>{
        'emissions': revisions.length,
        'stale_replays': revisions
            .where((revision) => revision <= initialRevision)
            .length,
      },
    );
  } finally {
    await store.close();
  }
}

Future<BenchmarkResult> _boxOpen(
  Directory directory,
  String boxName,
  int totalBytes,
  int samples,
) async {
  const recordCount = 16;
  final seed = await HiveCeKacheStore.open(
    boxName: boxName,
    path: directory.path,
  );
  final binding = seed.bind<List<BenchmarkItem>>(
    codecId: 'benchmark.items.v1',
    codec: benchmarkItemsCodec,
  );
  final entry = _entryOf(_itemsOfSize(totalBytes ~/ recordCount));
  for (var index = 0; index < recordCount; index++) {
    await seed.write(
      key: KacheKey('benchmark-open', <Object?>[index]),
      binding: binding,
      entry: entry,
    );
  }
  await seed.close();
  final times = <int>[];
  for (var index = 0; index < samples; index++) {
    final stopwatch = Stopwatch()..start();
    final store = await HiveCeKacheStore.open(
      boxName: boxName,
      path: directory.path,
    );
    times.add(stopwatch.elapsedMicroseconds);
    await store.close();
  }
  final fileBytes = File('${directory.path}/$boxName.hive').lengthSync();
  return _Timings(times, times).toResult(
    'hive_ce.box_open.${_tierOf(totalBytes)}',
    <String, num>{'file_bytes': fileBytes},
  );
}

String _tierOf(int bytes) =>
    pageEntryTiers.entries.firstWhere((tier) => tier.value == bytes).key;

int _recordBytes(HiveCeKacheStore store) =>
    store.box.values.whereType<Uint8List>().fold<int>(0, (largest, record) {
      return record.length > largest ? record.length : largest;
    });

Future<_Timings> _sample(int samples, Future<Object?> Function() run) async {
  final syncTimes = <int>[];
  final totalTimes = <int>[];
  for (var index = 0; index < samples; index++) {
    final stopwatch = Stopwatch()..start();
    final future = run();
    syncTimes.add(stopwatch.elapsedMicroseconds);
    await future;
    totalTimes.add(stopwatch.elapsedMicroseconds);
  }
  return _Timings(syncTimes, totalTimes);
}

final class _Timings {
  _Timings(this.sync, this.total);

  final List<int> sync;
  final List<int> total;

  BenchmarkResult toResult(
    String name, [
    Map<String, num> dimensions = const <String, num>{},
  ]) => BenchmarkResult(
    name: name,
    operations: sync.length,
    elapsed: Duration(
      microseconds: total.fold<int>(0, (sum, value) => sum + value),
    ),
    dimensions: <String, num>{
      'sync_us_median': _median(sync),
      'sync_us_max': sync.reduce((a, b) => a > b ? a : b),
      'total_us_median': _median(total),
      ...dimensions,
    },
  );
}

int _median(List<int> values) {
  final sorted = values.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

/// A representative list row with mixed field types.
final class BenchmarkItem {
  /// Creates a row.
  const BenchmarkItem(this.id, this.name, this.tags, this.score);

  /// Stable identifier.
  final int id;

  /// Display name.
  final String name;

  /// Short labels.
  final List<String> tags;

  /// Ranking score.
  final double score;
}

/// JSON codec built from top-level functions so it can run on any isolate.
const HiveCeCodec<List<BenchmarkItem>> benchmarkItemsCodec =
    HiveCeCodec<List<BenchmarkItem>>(
      encode: _encodeItems,
      decode: _decodeItems,
    );

Uint8List _encodeItems(List<BenchmarkItem> items) => utf8.encode(
  jsonEncode(<Object?>[
    for (final item in items)
      <String, Object?>{
        'id': item.id,
        'name': item.name,
        'tags': item.tags,
        'score': item.score,
      },
  ]),
);

List<BenchmarkItem> _decodeItems(Uint8List bytes) => <BenchmarkItem>[
  for (final row in jsonDecode(utf8.decode(bytes)) as List<Object?>)
    if (row case final Map<String, Object?> json)
      BenchmarkItem(
        json['id']! as int,
        json['name']! as String,
        (json['tags']! as List<Object?>).cast<String>(),
        (json['score']! as num).toDouble(),
      ),
];

List<BenchmarkItem> _itemsOfSize(int targetBytes) {
  // Each row encodes to roughly 90 bytes; refine with one measurement.
  const sampleRows = 64;
  final sample = _rows(sampleRows);
  final bytesPerRow = _encodeItems(sample).length / sampleRows;
  final count = (targetBytes / bytesPerRow).ceil().clamp(1, 1 << 24);
  return _rows(count);
}

List<BenchmarkItem> _rows(int count) => List<BenchmarkItem>.generate(
  count,
  (index) => BenchmarkItem(index, 'repository-name-$index', const <String>[
    'dart',
    'flutter',
    'cache',
  ], index * 0.5),
  growable: false,
);
