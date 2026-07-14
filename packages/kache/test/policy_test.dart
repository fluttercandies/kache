import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  group('KachePolicy.staleWhileRevalidate', () {
    test('uses safe stale-while-revalidate defaults', () {
      final policy = KachePolicy.staleWhileRevalidate();

      expect(policy.staleAfter, Duration.zero);
      expect(policy.expireAfter, isNull);
      expect(policy.refreshOnLoad, KacheRevalidation.always);
      expect(policy.refreshOnResume, KacheRevalidation.always);
      expect(policy.refreshInterval, isNull);
      expect(policy.retainDataOnError, isTrue);
      expect(policy.gcAfter, const Duration(minutes: 5));
      expect(policy.isCacheOnly, isFalse);
    });

    test('accepts an explicit refresh interval', () {
      final policy = KachePolicy.staleWhileRevalidate(
        refreshInterval: const Duration(minutes: 5),
      );

      expect(policy.refreshInterval, const Duration(minutes: 5));
    });
  });

  group('KachePolicy.cacheFirst', () {
    test('maps freshFor to the shared freshness model', () {
      final policy = KachePolicy.cacheFirst(
        freshFor: Duration(minutes: 10),
        expireAfter: Duration(hours: 1),
      );

      expect(policy.staleAfter, const Duration(minutes: 10));
      expect(policy.expireAfter, const Duration(hours: 1));
      expect(policy.refreshOnLoad, KacheRevalidation.ifStale);
      expect(policy.refreshOnResume, KacheRevalidation.ifStale);
      expect(policy.retainDataOnError, isTrue);
      expect(policy.isCacheOnly, isFalse);
    });
  });

  group('KachePolicy.cacheOnly', () {
    test('never performs automatic network revalidation', () {
      final policy = KachePolicy.cacheOnly(
        staleAfter: Duration(minutes: 2),
        expireAfter: Duration(minutes: 30),
      );

      expect(policy.refreshOnLoad, KacheRevalidation.never);
      expect(policy.refreshOnResume, KacheRevalidation.never);
      expect(policy.isCacheOnly, isTrue);
    });
  });

  group('KachePolicy freshness', () {
    final fetchedAt = DateTime.utc(2026, 1, 1, 12);
    final policy = KachePolicy.cacheFirst(
      freshFor: Duration(minutes: 10),
      expireAfter: Duration(minutes: 30),
    );

    test('is fresh strictly before staleAfter', () {
      expect(
        policy.freshnessAt(
          fetchedAt: fetchedAt,
          now: fetchedAt.add(const Duration(minutes: 9, seconds: 59)),
        ),
        KacheFreshness.fresh,
      );
    });

    test('is stale at staleAfter and before expireAfter', () {
      expect(
        policy.freshnessAt(
          fetchedAt: fetchedAt,
          now: fetchedAt.add(const Duration(minutes: 10)),
        ),
        KacheFreshness.stale,
      );
      expect(
        policy.freshnessAt(
          fetchedAt: fetchedAt,
          now: fetchedAt.add(const Duration(minutes: 29, seconds: 59)),
        ),
        KacheFreshness.stale,
      );
    });

    test('returns null at hard expiry and later', () {
      expect(
        policy.freshnessAt(
          fetchedAt: fetchedAt,
          now: fetchedAt.add(const Duration(minutes: 30)),
        ),
        isNull,
      );
    });

    test('treats invalidated data as stale before hard expiry', () {
      expect(
        policy.freshnessAt(
          fetchedAt: fetchedAt,
          now: fetchedAt.add(const Duration(minutes: 1)),
          isInvalidated: true,
        ),
        KacheFreshness.stale,
      );
    });

    test('normalizes local DateTime values before comparison', () {
      final localFetchedAt = fetchedAt.toLocal();
      final localNow = fetchedAt.add(const Duration(minutes: 10)).toLocal();

      expect(
        policy.freshnessAt(fetchedAt: localFetchedAt, now: localNow),
        KacheFreshness.stale,
      );
    });
  });

  group('KachePolicy validation', () {
    test('rejects negative durations', () {
      expect(
        () => KachePolicy(
          staleAfter: const Duration(microseconds: -1),
          refreshOnLoad: KacheRevalidation.ifStale,
          refreshOnResume: KacheRevalidation.ifStale,
        ),
        throwsArgumentError,
      );
      expect(
        () => KachePolicy(
          staleAfter: Duration.zero,
          gcAfter: const Duration(microseconds: -1),
          refreshOnLoad: KacheRevalidation.ifStale,
          refreshOnResume: KacheRevalidation.ifStale,
        ),
        throwsArgumentError,
      );
    });

    test('rejects expiry before staleness', () {
      expect(
        () => KachePolicy.cacheFirst(
          freshFor: const Duration(minutes: 10),
          expireAfter: const Duration(minutes: 9),
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-positive refresh intervals', () {
      expect(
        () => KachePolicy.staleWhileRevalidate(refreshInterval: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => KachePolicy.cacheFirst(
          freshFor: Duration.zero,
          refreshInterval: const Duration(microseconds: -1),
        ),
        throwsArgumentError,
      );
    });
  });

  test('systemKacheClock returns UTC time', () {
    expect(systemKacheClock().isUtc, isTrue);
  });
}
