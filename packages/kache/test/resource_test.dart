import 'dart:async';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 4, 5);

  test('replays the current snapshot to every listener', () async {
    final client = KacheClient(clock: () => now);
    final resource = client.watch(
      KacheQuery<String>.memory(
        key: KacheKey('replay'),
        fetch: (_) async => 'ready',
      ),
    );
    await resource.load();

    final first = await resource.stream.first;
    final second = await resource.stream.first;

    expect(first.requireData, 'ready');
    expect(second.requireData, 'ready');
    expect(first.revision, second.revision);

    resource.dispose();
    await client.close();
  });

  test('cancelling a listener does not dispose the resource', () async {
    final client = KacheClient(clock: () => now);
    var fetchCount = 0;
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('listener-cancel'),
        fetch: (_) async => ++fetchCount,
      ),
    );
    final subscription = resource.stream.listen((_) {});
    await resource.load();
    await subscription.cancel();

    final refreshed = await resource.refresh();

    expect(refreshed.requireData, 2);
    expect(resource.isDisposed, isFalse);

    resource.dispose();
    await client.close();
  });

  test('the first listener starts automatic load only once', () async {
    final client = KacheClient(clock: () => now);
    var fetchCount = 0;
    final resource = client.watch(
      KacheQuery<int>.memory(
        key: KacheKey('auto-load-once'),
        policy: KachePolicy.cacheFirst(freshFor: const Duration(hours: 1)),
        fetch: (_) async => ++fetchCount,
      ),
    );

    final firstReady = resource.stream.firstWhere(
      (snapshot) => snapshot.hasData,
    );
    final secondReady = resource.stream.firstWhere(
      (snapshot) => snapshot.hasData,
    );
    await Future.wait(<Future<KacheSnapshot<int>>>[firstReady, secondReady]);

    expect(fetchCount, 1);

    resource.dispose();
    await client.close();
  });

  test('dispose is idempotent and closes active resource streams', () async {
    final client = KacheClient(clock: () => now);
    final resource = client.watch(
      KacheQuery<int>.memory(key: KacheKey('dispose'), fetch: (_) async => 1),
    );
    final done = Completer<void>();
    resource.stream.listen((_) {}, onDone: done.complete);

    resource.dispose();
    resource.dispose();

    await done.future;
    expect(resource.isDisposed, isTrue);
    expect(() => resource.load(), throwsA(isA<KacheLifecycleException>()));

    await client.close();
  });

  test('two handles share data but use their own fetchers', () async {
    final client = KacheClient(clock: () => now);
    final key = KacheKey('shared-handles');
    final first = client.watch(
      KacheQuery<String>.memory(key: key, fetch: (_) async => 'first'),
    );
    final second = client.watch(
      KacheQuery<String>.memory(key: key, fetch: (_) async => 'second'),
    );

    expect((await first.refresh()).requireData, 'first');
    expect(second.snapshot.requireData, 'first');
    expect((await second.refresh()).requireData, 'second');
    expect(first.snapshot.requireData, 'second');

    first.dispose();
    second.dispose();
    await client.close();
  });
}
