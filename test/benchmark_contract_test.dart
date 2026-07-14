import 'package:test/test.dart';

import '../benchmark/kache_benchmark.dart';

void main() {
  test('benchmark suite reports every required production baseline', () async {
    final results = await runKacheBenchmarks(iterations: 100, keyCount: 8);

    expect(
      results.keys,
      containsAll(<String>[
        'core.hot_peek',
        'core.multi_key_peek',
        'core.single_flight',
        'hive_ce.codec_round_trip',
      ]),
    );
    for (final result in results.values) {
      expect(result.operations, greaterThan(0));
      expect(result.elapsed, isNot(Duration.zero));
    }
    expect(results['core.single_flight']!.dimensions['fetchCount'], 1);
  });
}
