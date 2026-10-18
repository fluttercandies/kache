import 'package:test/test.dart';

import '../benchmark/kache_benchmark.dart';
import '../benchmark/page_entry_benchmark.dart';

void main() {
  test('benchmark suite reports every required production baseline', () async {
    final results = await runKacheBenchmarks(
      iterations: 100,
      keyCount: 8,
      pageEntrySamples: 2,
    );

    expect(
      results.keys,
      containsAll(<String>[
        'core.hot_peek',
        'core.multi_key_peek',
        'core.single_flight',
        'hive_ce.codec_round_trip',
        for (final tier in pageEntryTiers.keys) ...<String>[
          'core.listen_sync.$tier',
          'hive_ce.read_sync.$tier',
          'hive_ce.write_sync.$tier',
          'hive_ce.box_open.$tier',
        ],
        'core.page_entry_emissions',
      ]),
    );
    for (final result in results.values) {
      expect(result.operations, greaterThan(0));
      expect(result.elapsed, isNot(Duration.zero));
    }
    expect(results['core.single_flight']!.dimensions['fetchCount'], 1);
    for (final result in results.values) {
      if (result.name.contains('_sync.')) {
        expect(result.dimensions['sync_us_median'], isNotNull);
        expect(result.dimensions['total_us_median'], isNotNull);
      }
    }
    final emissions = results['core.page_entry_emissions']!.dimensions;
    expect(emissions['emissions'], greaterThan(0));
    expect(emissions['stale_replays'], isNotNull);
  });
}
