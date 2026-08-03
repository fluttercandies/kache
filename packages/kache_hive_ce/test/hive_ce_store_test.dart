import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:kache/kache.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';
import 'package:kache_hive_ce/src/adapter_envelope.dart';
import 'package:test/test.dart';

void main() {
  test('persists typed data across a real box restart', () async {
    final directory = await Directory.systemTemp.createTemp('kache_hive_');
    addTearDown(() => directory.delete(recursive: true));
    final boxName = _boxName('restart');
    final key = KacheKey('profile', [1]);

    final first = await HiveCeKacheStore.open(
      boxName: boxName,
      path: directory.path,
    );
    final firstBinding = _stringBinding(first);
    await first.write<String>(
      key: key,
      binding: firstBinding,
      entry: KachePersistedEntry<String>(
        data: 'Ada',
        metadata: KachePersistedMetadata(
          fetchedAt: DateTime.utc(2026, 2, 3),
          isInvalidated: true,
        ),
      ),
    );
    expect(
      first.box.get(_findFirstPhysicalKey(first.box)),
      isA<Uint8List>(),
    );
    await first.close();

    final second = await HiveCeKacheStore.open(
      boxName: boxName,
      path: directory.path,
    );
    final read = await second.read<String>(
      key: key,
      binding: _stringBinding(second),
    );

    expect(read?.entry.data, 'Ada');
    expect(read?.entry.metadata.isInvalidated, isTrue);
    await second.close();
  });

  test('shared open leases close the box after the final store', () async {
    final first = await HiveCeKacheStore.open(
      boxName: _boxName('shared'),
      bytes: Uint8List(0),
    );
    final second = await HiveCeKacheStore.open(
      boxName: first.box.name,
      bytes: Uint8List(0),
    );

    await first.close();
    expect(second.box.isOpen, isTrue);

    await second.close();
    expect(second.box.isOpen, isFalse);
  });
  test('a pending shared lease prevents the box from closing', () async {
    final first = await HiveCeKacheStore.open(
      boxName: _boxName('pending-shared'),
      bytes: Uint8List(0),
    );
    final pendingSecond = HiveCeKacheStore.open(
      boxName: first.box.name,
      bytes: Uint8List(0),
    );

    await first.close();
    final second = await pendingSecond;

    expect(second.box.isOpen, isTrue);
    await second.close();
    expect(second.box.isOpen, isFalse);
  });

  test('concurrent reopen waits for the final managed lease to close',
      () async {
    final boxName = _boxName('close-reopen');
    final first = await HiveCeKacheStore.open(
      boxName: boxName,
      bytes: Uint8List(0),
    );
    final firstBox = first.box;

    final close = first.close();
    final reopened = await HiveCeKacheStore.open(
      boxName: boxName,
      bytes: Uint8List(0),
    );
    await close;

    expect(reopened.box, isNot(same(firstBox)));
    expect(reopened.box.isOpen, isTrue);
    await reopened.close();
  });

  test('an externally opened box is borrowed by open factory', () async {
    final boxName = _boxName('borrowed-open');
    final box = await Hive.openBox<Object?>(boxName, bytes: Uint8List(0));
    final store = await HiveCeKacheStore.open(boxName: boxName);

    await store.close();

    expect(box.isOpen, isTrue);
    await box.close();
  });

  test('fromBox ownership controls whether close releases the box', () async {
    final borrowedBox = await Hive.openBox<Object?>(
      _boxName('borrowed-box'),
      bytes: Uint8List(0),
    );
    final borrowed = HiveCeKacheStore.fromBox(borrowedBox);
    await borrowed.close();
    expect(borrowedBox.isOpen, isTrue);
    await borrowedBox.close();

    final ownedBox = await Hive.openBox<Object?>(
      _boxName('owned-box'),
      bytes: Uint8List(0),
    );
    final owned = HiveCeKacheStore.fromBox(
      ownedBox,
      ownership: HiveCeBoxOwnership.owned,
    );
    await owned.close();
    expect(ownedBox.isOpen, isFalse);
  });

  test('supports a Hive encrypted box without owning key material', () async {
    final directory = await Directory.systemTemp.createTemp('kache_cipher_');
    addTearDown(() => directory.delete(recursive: true));
    final boxName = _boxName('encrypted');
    final cipher = HiveAesCipher(List<int>.generate(32, (index) => index));
    final first = await HiveCeKacheStore.open(
      boxName: boxName,
      path: directory.path,
      encryptionCipher: cipher,
    );
    final key = KacheKey('encrypted');
    await first.write<String>(
      key: key,
      binding: _stringBinding(first),
      entry: KachePersistedEntry<String>(
        data: 'secret-data',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );
    await first.close();

    final second = await HiveCeKacheStore.open(
      boxName: boxName,
      path: directory.path,
      encryptionCipher: cipher,
    );
    final read = await second.read<String>(
      key: key,
      binding: _stringBinding(second),
    );

    expect(read?.entry.data, 'secret-data');
    await second.close();
  });

  test('classifies a non-byte box value as decode corruption', () async {
    final box = await Hive.openBox<Object?>(
      _boxName('corrupt-value'),
      bytes: Uint8List(0),
    );
    final store = HiveCeKacheStore.fromBox(
      box,
      ownership: HiveCeBoxOwnership.owned,
    );
    final key = KacheKey('corrupt');
    final binding = _stringBinding(store);
    await store.write<String>(
      key: key,
      binding: binding,
      entry: KachePersistedEntry<String>(
        data: 'valid',
        metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
      ),
    );
    await box.put(_findFirstPhysicalKey(box), 'not-bytes');

    await expectLater(
      store.read<String>(key: key, binding: binding),
      throwsA(
        isA<KachePersistenceException>()
            .having(
              (error) => error.operation,
              'operation',
              KachePersistenceOperation.read,
            )
            .having(
              (error) => error.stage,
              'stage',
              KachePersistenceStage.decode,
            ),
      ),
    );
    await store.close();
  });

  test('post-close operations fail before binding validation', () async {
    final first = await HiveCeKacheStore.open(
      boxName: _boxName('closed-first'),
      bytes: Uint8List(0),
    );
    final second = await HiveCeKacheStore.open(
      boxName: _boxName('closed-second'),
      bytes: Uint8List(0),
    );
    final foreign = _stringBinding(second);
    await first.close();

    await expectLater(
      first.read<String>(key: KacheKey('closed'), binding: foreign),
      throwsA(isA<KachePersistenceException>()),
    );
    await second.close();
  });

  group('registered TypeAdapter bindings', () {
    setUpAll(() {
      if (!Hive.isAdapterRegistered(_ProfileAdapter.typeIdValue)) {
        Hive.registerAdapter<_Profile>(const _ProfileAdapter());
      }
      if (!Hive.isAdapterRegistered(_OtherAdapter.typeIdValue)) {
        Hive.registerAdapter<_Other>(const _OtherAdapter());
      }
      if (!Hive.isAdapterRegistered(_ExtendedAdapter.typeIdValue)) {
        Hive.registerAdapter<_Extended>(const _ExtendedAdapter());
      }
      if (!Hive.isAdapterRegistered(_MaximumAdapter.typeIdValue)) {
        Hive.registerAdapter<_Maximum>(const _MaximumAdapter());
      }
    });

    test('round-trips an adapter value across a real box restart', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kache_hive_adapter_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final boxName = _boxName('adapter-restart');
      final key = KacheKey('profile', <Object?>[7]);
      final first = await HiveCeKacheStore.open(
        boxName: boxName,
        path: directory.path,
      );
      final binding = first.bindAdapter<_Profile>(const _ProfileAdapter());

      await first.write<_Profile>(
        key: key,
        binding: binding,
        entry: KachePersistedEntry<_Profile>(
          data: const _Profile(7, 'Ada'),
          metadata: KachePersistedMetadata(
            fetchedAt: DateTime.utc(2026, 2, 3),
            isInvalidated: true,
          ),
        ),
      );

      expect(
        first.box.get(_findFirstPhysicalKey(first.box)),
        isA<List<Object?>>(),
      );
      await first.close();

      final second = await HiveCeKacheStore.open(
        boxName: boxName,
        path: directory.path,
      );
      final read = await second.read<_Profile>(
        key: key,
        binding: second.bindAdapter<_Profile>(const _ProfileAdapter()),
      );

      expect(read?.entry.data, const _Profile(7, 'Ada'));
      expect(read?.entry.metadata.isInvalidated, isTrue);
      await second.close();
    });

    test('round-trips extended adapter type id boundaries after restart',
        () async {
      final directory = await Directory.systemTemp.createTemp(
        'kache_hive_extended_adapter_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final boxName = _boxName('extended-adapter-restart');
      final first = await HiveCeKacheStore.open(
        boxName: boxName,
        path: directory.path,
      );
      final extendedKey = KacheKey('extended-adapter', <Object?>[224]);
      final maximumKey = KacheKey('extended-adapter', <Object?>[65439]);

      await first.write<_Extended>(
        key: extendedKey,
        binding: first.bindAdapter<_Extended>(const _ExtendedAdapter()),
        entry: KachePersistedEntry<_Extended>(
          data: const _Extended(224),
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      );
      await first.write<_Maximum>(
        key: maximumKey,
        binding: first.bindAdapter<_Maximum>(const _MaximumAdapter()),
        entry: KachePersistedEntry<_Maximum>(
          data: const _Maximum(65439),
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      );
      await first.close();

      final second = await HiveCeKacheStore.open(
        boxName: boxName,
        path: directory.path,
      );
      final extended = await second.read<_Extended>(
        key: extendedKey,
        binding: second.bindAdapter<_Extended>(const _ExtendedAdapter()),
      );
      final maximum = await second.read<_Maximum>(
        key: maximumKey,
        binding: second.bindAdapter<_Maximum>(const _MaximumAdapter()),
      );

      expect(extended?.entry.data.value, 224);
      expect(maximum?.entry.data.value, 65439);
      await second.close();
    });

    test('distinguishes adapter-backed nullable null from a miss', () async {
      final store = await HiveCeKacheStore.open(
        boxName: _boxName('adapter-null'),
        bytes: Uint8List(0),
      );
      final binding = store.bindAdapter<_Profile?>(const _ProfileAdapter());
      final key = KacheKey('nullable-profile');

      await store.write<_Profile?>(
        key: key,
        binding: binding,
        entry: KachePersistedEntry<_Profile?>(
          data: null,
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      );
      final nullableRead = await store.read<_Profile?>(
        key: key,
        binding: binding,
      );

      expect(nullableRead, isNotNull);
      expect(nullableRead?.entry.data, isNull);
      await expectLater(
        store.read<_Profile>(
          key: key,
          binding: store.bindAdapter<_Profile>(const _ProfileAdapter()),
        ),
        throwsA(
          isA<KachePersistenceException>().having(
            (error) => error.stage,
            'stage',
            KachePersistenceStage.decode,
          ),
        ),
      );
      await store.close();
    });
    test('rejects an adapter whose value type cannot encode the binding',
        () async {
      final store = await HiveCeKacheStore.open(
        boxName: _boxName('adapter-value-type'),
        bytes: Uint8List(0),
      );

      expect(
        () => store.bindAdapter<String>(const _ProfileAdapter()),
        throwsArgumentError,
      );
      await store.close();
    });

    test('rejects an adapter that is not registered with the store Hive',
        () async {
      final storeFuture = HiveCeKacheStore.open(
        boxName: _boxName('adapter-unregistered'),
        bytes: Uint8List(0),
      );

      await expectLater(
        storeFuture.then(
          (store) => store.bindAdapter<_Unregistered>(
            const _UnregisteredAdapter(),
          ),
        ),
        throwsArgumentError,
      );
      addTearDown(() async => (await storeFuture).close());
    });

    test('rejects codec and adapter records crossing binding modes', () async {
      final store = await HiveCeKacheStore.open(
        boxName: _boxName('adapter-mode-conflict'),
        bytes: Uint8List(0),
      );
      final key = KacheKey('mode-conflict');
      await store.write<_Profile>(
        key: key,
        binding: store.bindAdapter<_Profile>(const _ProfileAdapter()),
        entry: KachePersistedEntry<_Profile>(
          data: const _Profile(1, 'Ada'),
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      );

      await expectLater(
        store.read<String>(key: key, binding: _stringBinding(store)),
        throwsA(isA<KachePersistenceException>()),
      );

      final codecKey = KacheKey('codec-mode');
      await store.write<String>(
        key: codecKey,
        binding: _stringBinding(store),
        entry: KachePersistedEntry<String>(
          data: 'Ada',
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      );
      await expectLater(
        store.read<_Profile>(
          key: codecKey,
          binding: store.bindAdapter<_Profile>(const _ProfileAdapter()),
        ),
        throwsA(isA<KachePersistenceException>()),
      );
      await store.close();
    });

    test('rejects an adapter binding with another registered type id',
        () async {
      final store = await HiveCeKacheStore.open(
        boxName: _boxName('adapter-type-conflict'),
        bytes: Uint8List(0),
      );
      final key = KacheKey('adapter-type-conflict');
      await store.write<_Profile>(
        key: key,
        binding: store.bindAdapter<_Profile>(const _ProfileAdapter()),
        entry: KachePersistedEntry<_Profile>(
          data: const _Profile(1, 'Ada'),
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      );
      await store.box.put(
        _findFirstPhysicalKey(store.box),
        HiveCeAdapterEnvelope.encode(
          fetchedAt: DateTime.utc(2026),
          isInvalidated: false,
          typeId: _OtherAdapter.typeIdValue,
          data: const _Other(),
        ),
      );

      await expectLater(
        store.read<_Profile>(
          key: key,
          binding: store.bindAdapter<_Profile>(const _ProfileAdapter()),
        ),
        throwsA(isA<KachePersistenceException>()),
      );
      await store.close();
    });

    test('classifies a malformed adapter envelope as decode corruption',
        () async {
      final store = await HiveCeKacheStore.open(
        boxName: _boxName('adapter-corrupt'),
        bytes: Uint8List(0),
      );
      final key = KacheKey('adapter-corrupt');
      final binding = store.bindAdapter<_Profile>(const _ProfileAdapter());
      await store.write<_Profile>(
        key: key,
        binding: binding,
        entry: KachePersistedEntry<_Profile>(
          data: const _Profile(1, 'valid'),
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      );
      await store.box.put(
        _findFirstPhysicalKey(store.box),
        <Object?>['invalid'],
      );

      await expectLater(
        store.read<_Profile>(
          key: key,
          binding: binding,
        ),
        throwsA(
          isA<KachePersistenceException>().having(
            (error) => error.stage,
            'stage',
            KachePersistenceStage.decode,
          ),
        ),
      );
      await store.close();
    });
  });

  group('hashed physical keys', () {
    test('long logical key round-trips across close and reopen', () async {
      final directory = await Directory.systemTemp.createTemp('kache_long_');
      addTearDown(() => directory.delete(recursive: true));
      final boxName = _boxName('long-key');
      final longPart = 'x' * 300;
      final key = KacheKey('long-namespace', [longPart]);
      expect(key.storageKey.length, greaterThan(255));

      final first = await HiveCeKacheStore.open(
        boxName: boxName,
        path: directory.path,
      );
      await first.write<String>(
        key: key,
        binding: _stringBinding(first),
        entry: KachePersistedEntry<String>(
          data: 'long-value',
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      );
      final physicalKey = _findFirstPhysicalKey(first.box);
      expect(physicalKey.length, lessThan(255));
      await first.close();

      final second = await HiveCeKacheStore.open(
        boxName: boxName,
        path: directory.path,
      );
      final read = await second.read<String>(
        key: key,
        binding: _stringBinding(second),
      );
      expect(read?.entry.data, 'long-value');
      await second.close();
    });

    test('SHA and HMAC strategies produce different physical keys', () async {
      final shaStore = await HiveCeKacheStore.open(
        boxName: _boxName('sha-strategy'),
        bytes: Uint8List(0),
      );
      final hmacStore = await HiveCeKacheStore.open(
        boxName: _boxName('hmac-strategy'),
        bytes: Uint8List(0),
        keyStrategy: HiveCeKeyStrategy.hmacSha256(
          List<int>.generate(32, (i) => i + 1),
        ),
      );
      final key = KacheKey('test', ['value']);

      await shaStore.write<String>(
        key: key,
        binding: _stringBinding(shaStore),
        entry: KachePersistedEntry<String>(
          data: 'sha',
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      );
      await hmacStore.write<String>(
        key: key,
        binding: _stringBinding(hmacStore),
        entry: KachePersistedEntry<String>(
          data: 'hmac',
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      );

      final shaPhysical = _findFirstPhysicalKey(shaStore.box);
      final hmacPhysical = _findFirstPhysicalKey(hmacStore.box);
      expect(shaPhysical.startsWith('kache:3:s:'), isTrue);
      expect(hmacPhysical.startsWith('kache:3:h:'), isTrue);
      expect(shaPhysical, isNot(equals(hmacPhysical)));

      await shaStore.close();
      await hmacStore.close();
    });

    test('HMAC physical key does not contain canonical key material', () async {
      final store = await HiveCeKacheStore.open(
        boxName: _boxName('hmac-opaque'),
        bytes: Uint8List(0),
        keyStrategy: HiveCeKeyStrategy.hmacSha256(
          List<int>.generate(32, (i) => i + 7),
        ),
      );
      final key = KacheKey('sensitive-namespace', ['secret-data', 42]);
      await store.write<String>(
        key: key,
        binding: _stringBinding(store),
        entry: KachePersistedEntry<String>(
          data: 'v',
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      );
      final physicalKey = _findFirstPhysicalKey(store.box);
      expect(physicalKey.contains('sensitive-namespace'), isFalse);
      expect(physicalKey.contains('secret-data'), isFalse);
      await store.close();
    });

    test('HMAC strategy rejects a secret shorter than 32 bytes', () {
      expect(
        () => HiveCeKeyStrategy.hmacSha256(List.filled(31, 0)),
        throwsArgumentError,
      );
    });

    test('does not read or clear records from removed key formats', () async {
      final store = await HiveCeKacheStore.open(
        boxName: _boxName('removed-key-formats'),
        bytes: Uint8List(0),
      );
      final key = KacheKey('profile');
      final binding = _stringBinding(store);
      await store.write<String>(
        key: key,
        binding: binding,
        entry: KachePersistedEntry<String>(
          data: 'current',
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      );
      final currentKey = _findFirstPhysicalKey(store.box);
      final record = store.box.get(currentKey)!;
      final oldHashedKey = _retiredV2PhysicalKey(key);
      await store.box.delete(currentKey);
      await store.box.put(oldHashedKey, record);
      await store.box.put(key.storageKey, record);

      expect(await store.read<String>(key: key, binding: binding), isNull);
      await store.clear();
      expect(store.box.get(oldHashedKey), same(record));
      expect(store.box.get(key.storageKey), same(record));

      await store.close();
    });

    test('clear preserves non-kache and pseudo-prefix host data', () async {
      final box = await Hive.openBox<Object?>(
        _boxName('borrowed-clear'),
        bytes: Uint8List(0),
      );
      final store = HiveCeKacheStore.fromBox(
        box,
        ownership: HiveCeBoxOwnership.owned,
      );
      final key = KacheKey('managed');
      await store.write<String>(
        key: key,
        binding: _stringBinding(store),
        entry: KachePersistedEntry<String>(
          data: 'managed-data',
          metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
        ),
      );
      await box.put(42, 'int-data');
      await box.put('foreign-key', 'foreign-data');
      await box.put('kache:2:evil', 'pseudo-prefix-1');
      await box.put('kache:2:s:short', 'pseudo-prefix-2');
      final retiredKey = 'kache:2:s:${'a' * 43}:${'b' * 43}';
      final retiredCanonicalKey = KacheKey('retired', [1]).storageKey;
      await box.put(retiredKey, 'retired-v2');
      await box.put(retiredCanonicalKey, 'retired-canonical');
      await box.put(
        'kache:2:s:${'a' * 43}:${'b' * 10}',
        'pseudo-prefix-short-suffix',
      );
      await box.put('k1fake-key', 'pseudo-prefix-3');
      await box.put('k1:', 'pseudo-prefix-empty-ns');

      await store.clear();

      expect(
        await store.read<String>(key: key, binding: _stringBinding(store)),
        isNull,
      );
      expect(box.get(42), 'int-data');
      expect(box.get('foreign-key'), 'foreign-data');
      expect(box.get('kache:2:evil'), 'pseudo-prefix-1');
      expect(box.get('kache:2:s:short'), 'pseudo-prefix-2');
      expect(
        box.get('kache:2:s:${'a' * 43}:${'b' * 10}'),
        'pseudo-prefix-short-suffix',
      );
      expect(box.get(retiredKey), 'retired-v2');
      expect(box.get(retiredCanonicalKey), 'retired-canonical');
      expect(box.get('k1fake-key'), 'pseudo-prefix-3');
      expect(box.get('k1:'), 'pseudo-prefix-empty-ns');
      await store.close();
    });

    test(
      'clearNamespace preserves pseudo-prefix and foreign namespace keys',
      () async {
        final store = await HiveCeKacheStore.open(
          boxName: _boxName('ns-clear'),
          bytes: Uint8List(0),
        );
        final binding = _stringBinding(store);
        final nsKey = KacheKey('accounts', [1]);
        final otherKey = KacheKey('account-settings', [1]);
        await store.write<String>(
          key: nsKey,
          binding: binding,
          entry: KachePersistedEntry<String>(
            data: 'ns-data',
            metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
          ),
        );
        await store.write<String>(
          key: otherKey,
          binding: binding,
          entry: KachePersistedEntry<String>(
            data: 'other-data',
            metadata: KachePersistedMetadata(fetchedAt: DateTime.utc(2026)),
          ),
        );
        await store.box.put('foreign-key', 'foreign-data');

        await store.clearNamespace(namespace: KacheNamespace('accounts'));

        expect(
          await store.read<String>(key: nsKey, binding: binding),
          isNull,
        );
        expect(
          (await store.read<String>(key: otherKey, binding: binding))
              ?.entry
              .data,
          'other-data',
        );
        expect(store.box.get('foreign-key'), 'foreign-data');
        await store.close();
      },
    );
  });

  group('open exception and cipher lease', () {
    test('strategy lease mismatch fails open', () async {
      final boxName = _boxName('strategy-mismatch');
      final first = await HiveCeKacheStore.open(
        boxName: boxName,
        bytes: Uint8List(0),
      );
      await expectLater(
        HiveCeKacheStore.open(
          boxName: boxName,
          keyStrategy: HiveCeKeyStrategy.hmacSha256(
            List<int>.generate(32, (i) => i + 1),
          ),
        ),
        throwsA(isA<HiveCeOpenException>()),
      );
      await first.close();
    });

    test('cipher mismatch fails open for a managed lease', () async {
      final boxName = _boxName('cipher-mismatch');
      final cipher = HiveAesCipher(List<int>.generate(32, (i) => i));
      final first = await HiveCeKacheStore.open(
        boxName: boxName,
        bytes: Uint8List(0),
        encryptionCipher: cipher,
      );
      final otherCipher = HiveAesCipher(
        List<int>.generate(32, (i) => i + 1),
      );
      await expectLater(
        HiveCeKacheStore.open(
          boxName: boxName,
          encryptionCipher: otherCipher,
        ),
        throwsA(isA<HiveCeOpenException>()),
      );
      await first.close();
    });

    test('cipher downgrade fails open for a managed lease', () async {
      final boxName = _boxName('cipher-downgrade');
      final cipher = HiveAesCipher(List<int>.generate(32, (i) => i));
      final first = await HiveCeKacheStore.open(
        boxName: boxName,
        bytes: Uint8List(0),
        encryptionCipher: cipher,
      );
      await expectLater(
        HiveCeKacheStore.open(boxName: boxName),
        throwsA(isA<HiveCeOpenException>()),
      );
      await first.close();
    });

    test('cipher provided for a borrowed box fails open', () async {
      final boxName = _boxName('borrowed-cipher');
      final box = await Hive.openBox<Object?>(boxName, bytes: Uint8List(0));
      final cipher = HiveAesCipher(List<int>.generate(32, (i) => i));
      await expectLater(
        HiveCeKacheStore.open(
          boxName: boxName,
          encryptionCipher: cipher,
        ),
        throwsA(isA<HiveCeOpenException>()),
      );
      await box.close();
    });

    test('async Hive I/O failure wraps as HiveCeOpenException', () async {
      await expectLater(
        HiveCeKacheStore.open(
          boxName: _boxName('corrupt-bytes'),
          bytes: Uint8List.fromList(List.generate(50, (i) => i)),
        ),
        throwsA(isA<HiveCeOpenException>()),
      );
    });

    test('HiveCeOpenException toString is sanitized', () async {
      final boxName = _boxName('sanitized');
      final box = await Hive.openBox<Object?>(boxName, bytes: Uint8List(0));
      final cipher = HiveAesCipher(List<int>.generate(32, (i) => i));
      HiveCeOpenException? caught;
      try {
        await HiveCeKacheStore.open(
          boxName: boxName,
          encryptionCipher: cipher,
        );
      } on HiveCeOpenException catch (error) {
        caught = error;
      }
      await box.close();
      expect(caught, isNotNull);
      final str = caught.toString();
      expect(str.contains(boxName), isFalse);
      expect(str.contains('cipher'), isFalse);
    });
  });

  group('lease descriptor', () {
    test(
      'same CRC but different cipher object fails open',
      () async {
        final boxName = _boxName('same-crc-diff-obj');
        final key = List<int>.generate(32, (i) => i);
        final cipherA = HiveAesCipher(key);
        final first = await HiveCeKacheStore.open(
          boxName: boxName,
          bytes: Uint8List(0),
          encryptionCipher: cipherA,
        );
        final cipherB = HiveAesCipher(key);
        // Same key material → same CRC, but different object.
        await expectLater(
          HiveCeKacheStore.open(
            boxName: boxName,
            bytes: Uint8List(0),
            encryptionCipher: cipherB,
          ),
          throwsA(isA<HiveCeOpenException>()),
        );
        await first.close();
      },
    );

    test('same cipher object allows shared managed lease', () async {
      final boxName = _boxName('same-cipher-shared');
      final cipher = HiveAesCipher(List<int>.generate(32, (i) => i));
      final first = await HiveCeKacheStore.open(
        boxName: boxName,
        bytes: Uint8List(0),
        encryptionCipher: cipher,
      );
      final second = await HiveCeKacheStore.open(
        boxName: boxName,
        bytes: Uint8List(0),
        encryptionCipher: cipher,
      );
      await first.close();
      expect(second.box.isOpen, isTrue);
      await second.close();
    });

    test('path mismatch fails open for a managed lease', () async {
      final directory = await Directory.systemTemp.createTemp('kache_path_');
      addTearDown(() => directory.delete(recursive: true));
      final boxName = _boxName('path-mismatch');
      final first = await HiveCeKacheStore.open(
        boxName: boxName,
        path: directory.path,
      );
      await expectLater(
        HiveCeKacheStore.open(boxName: boxName),
        throwsA(isA<HiveCeOpenException>()),
      );
      await first.close();
    });

    test('bytes mode mismatch fails open for a managed lease', () async {
      final boxName = _boxName('bytes-mismatch');
      final first = await HiveCeKacheStore.open(
        boxName: boxName,
        bytes: Uint8List(0),
      );
      await expectLater(
        HiveCeKacheStore.open(boxName: boxName),
        throwsA(isA<HiveCeOpenException>()),
      );
      await first.close();
    });

    test('bytes content mismatch fails open for a managed lease', () async {
      final boxName = _boxName('bytes-content-mismatch');
      final first = await HiveCeKacheStore.open(
        boxName: boxName,
        bytes: Uint8List(0),
      );
      await expectLater(
        HiveCeKacheStore.open(
          boxName: boxName,
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<HiveCeOpenException>()),
      );
      await first.close();
    });

    test('crash recovery mismatch fails open for a managed lease', () async {
      final boxName = _boxName('crash-mismatch');
      final first = await HiveCeKacheStore.open(
        boxName: boxName,
        bytes: Uint8List(0),
        crashRecovery: false,
      );
      await expectLater(
        HiveCeKacheStore.open(
          boxName: boxName,
          bytes: Uint8List(0),
        ),
        throwsA(isA<HiveCeOpenException>()),
      );
      await first.close();
    });

    test('path and bytes both non-null throws ArgumentError', () async {
      final directory = await Directory.systemTemp.createTemp('kache_both_');
      addTearDown(() => directory.delete(recursive: true));
      await expectLater(
        HiveCeKacheStore.open(
          boxName: _boxName('path-bytes-both'),
          path: directory.path,
          bytes: Uint8List(0),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'sanitized message',
            isNot(contains(directory.path)),
          ),
        ),
      );
    });

    test('borrowed box rejects path, bytes, crashRecovery=false', () async {
      final boxName = _boxName('borrowed-config');
      final box = await Hive.openBox<Object?>(boxName, bytes: Uint8List(0));
      final directory = await Directory.systemTemp.createTemp('kache_bp_');
      addTearDown(() async {
        await box.close();
        await directory.delete(recursive: true);
      });

      await expectLater(
        HiveCeKacheStore.open(
          boxName: boxName,
          path: directory.path,
        ),
        throwsA(isA<HiveCeOpenException>()),
      );
      await expectLater(
        HiveCeKacheStore.open(
          boxName: boxName,
          bytes: Uint8List(0),
        ),
        throwsA(isA<HiveCeOpenException>()),
      );
      await expectLater(
        HiveCeKacheStore.open(
          boxName: boxName,
          crashRecovery: false,
        ),
        throwsA(isA<HiveCeOpenException>()),
      );
    });
    test('borrowed box pins the strategy while a lease is active', () async {
      final boxName = _boxName('borrowed-strategy');
      final box = await Hive.openBox<Object?>(boxName, bytes: Uint8List(0));
      addTearDown(() async {
        if (box.isOpen) {
          await box.close();
        }
      });
      final first = await HiveCeKacheStore.open(boxName: boxName);

      await expectLater(
        HiveCeKacheStore.open(
          boxName: boxName,
          keyStrategy: HiveCeKeyStrategy.hmacSha256(
            List<int>.generate(32, (index) => index),
          ),
        ),
        throwsA(isA<HiveCeOpenException>()),
      );

      await first.close();
    });
  });

  group('cipher safety', () {
    test('throwing calculateKeyCrc wraps as HiveCeOpenException', () async {
      final boxName = _boxName('throwing-cipher');
      final cipher = _ThrowingCipher();
      await expectLater(
        HiveCeKacheStore.open(
          boxName: boxName,
          bytes: Uint8List(0),
          encryptionCipher: cipher,
        ),
        throwsA(isA<HiveCeOpenException>()),
      );
      // No lease state should have been registered.
      expect(Hive.isBoxOpen(boxName), isFalse);
    });

    test(
      'throwing calculateKeyCrc on second open wraps without orphaning',
      () async {
        final boxName = _boxName('throwing-second');
        final cipher = _ThrowingCipher(throwAfterFirstCall: true);
        final first = await HiveCeKacheStore.open(
          boxName: boxName,
          bytes: Uint8List(0),
          encryptionCipher: cipher,
        );
        // Second open re-evaluates cipher identity; it throws again.
        await expectLater(
          HiveCeKacheStore.open(
            boxName: boxName,
            bytes: Uint8List(0),
            encryptionCipher: cipher,
          ),
          throwsA(isA<HiveCeOpenException>()),
        );
        // The first lease must still be usable.
        expect(first.box.isOpen, isTrue);
        await first.close();
      },
    );
  });

  group('HMAC secret validation', () {
    test('rejects secret with negative byte value', () {
      expect(
        () => HiveCeKeyStrategy.hmacSha256(
          List<int>.filled(32, -1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects secret with byte value above 255', () {
      expect(
        () => HiveCeKeyStrategy.hmacSha256(
          List<int>.filled(32, 256),
        ),
        throwsArgumentError,
      );
    });
  });
}

HiveCeBinding<String> _stringBinding(HiveCeKacheStore store) => store.bind(
      codecId: 'utf8-string',
      codec: HiveCeCodec<String>(
        encode: (value) => Uint8List.fromList(utf8.encode(value)),
        decode: (bytes) => utf8.decode(bytes),
      ),
    );

String _findFirstPhysicalKey(Box<Object?> box) =>
    box.keys.whereType<String>().firstWhere((k) => k.startsWith('kache:3:'));

String _retiredV2PhysicalKey(KacheKey key) {
  String digest(String domain, String value) => base64Url
      .encode(sha256.convert(utf8.encode('$domain\x00$value')).bytes)
      .replaceAll('=', '');

  final namespace = KacheNamespace(key.namespace);
  return 'kache:2:s:'
      '${digest('kache-hive-ce:v2:namespace', namespace.storagePrefix)}:'
      '${digest('kache-hive-ce:v2:key', key.storageKey)}';
}

String _boxName(String label) =>
    'kache_${label}_${DateTime.now().microsecondsSinceEpoch}';

final class _Profile {
  const _Profile(this.id, this.name);

  final int id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is _Profile && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

final class _ProfileAdapter extends TypeAdapter<_Profile> {
  const _ProfileAdapter();

  static const typeIdValue = 210;

  @override
  int get typeId => typeIdValue;

  @override
  _Profile read(BinaryReader reader) =>
      _Profile(reader.readInt(), reader.readString());

  @override
  void write(BinaryWriter writer, _Profile obj) {
    writer
      ..writeInt(obj.id)
      ..writeString(obj.name);
  }
}

final class _Unregistered {
  const _Unregistered();
}

final class _UnregisteredAdapter extends TypeAdapter<_Unregistered> {
  const _UnregisteredAdapter();

  @override
  int get typeId => 211;

  @override
  _Unregistered read(BinaryReader reader) => const _Unregistered();

  @override
  void write(BinaryWriter writer, _Unregistered obj) {}
}

final class _Other {
  const _Other();
}

final class _OtherAdapter extends TypeAdapter<_Other> {
  const _OtherAdapter();

  static const typeIdValue = 212;

  @override
  int get typeId => typeIdValue;

  @override
  _Other read(BinaryReader reader) => const _Other();

  @override
  void write(BinaryWriter writer, _Other obj) {}
}

final class _Extended {
  const _Extended(this.value);

  final int value;
}

final class _ExtendedAdapter extends TypeAdapter<_Extended> {
  const _ExtendedAdapter();

  static const typeIdValue = 224;

  @override
  int get typeId => typeIdValue;

  @override
  _Extended read(BinaryReader reader) => _Extended(reader.readInt());

  @override
  void write(BinaryWriter writer, _Extended obj) => writer.writeInt(obj.value);
}

final class _Maximum {
  const _Maximum(this.value);

  final int value;
}

final class _MaximumAdapter extends TypeAdapter<_Maximum> {
  const _MaximumAdapter();

  static const typeIdValue = 65439;

  @override
  int get typeId => typeIdValue;

  @override
  _Maximum read(BinaryReader reader) => _Maximum(reader.readInt());

  @override
  void write(BinaryWriter writer, _Maximum obj) => writer.writeInt(obj.value);
}

final class _ThrowingCipher implements HiveCipher {
  _ThrowingCipher({this.throwAfterFirstCall = false});

  final bool throwAfterFirstCall;
  var _callCount = 0;
  @override
  int calculateKeyCrc() {
    _callCount++;
    if (!throwAfterFirstCall || _callCount > 1) {
      throw StateError('cipher crc computation failed');
    }
    return 42;
  }

  @override
  int maxEncryptedSize(Uint8List inp) =>
      throw StateError('should not be called');

  @override
  int encrypt(
    Uint8List inp,
    int inpOff,
    int inpLength,
    Uint8List out,
    int outOff,
  ) =>
      throw StateError('should not be called');

  @override
  int decrypt(
    Uint8List inp,
    int inpOff,
    int inpLength,
    Uint8List out,
    int outOff,
  ) =>
      throw StateError('should not be called');
}
