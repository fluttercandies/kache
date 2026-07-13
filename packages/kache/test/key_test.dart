import 'dart:typed_data';

import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  group('KacheKey golden vectors', () {
    test('encodes empty parts and an ASCII namespace', () {
      final key = KacheKey('users');

      expect(key.namespace, 'users');
      expect(key.storageKey, 'k1:dXNlcnM:');
    });

    test('encodes Unicode namespaces without normalization', () {
      expect(KacheKey('缓存').storageKey, 'k1:57yT5a2Y:');
      expect(KacheKey('😀').storageKey, 'k1:8J-YgA:');
    });

    test('encodes null', () {
      expect(KacheKey('n', [null]).storageKey, 'k1:bg:AA');
    });

    test('encodes false', () {
      expect(KacheKey('n', [false]).storageKey, 'k1:bg:AQ');
    });

    test('encodes true', () {
      expect(KacheKey('n', [true]).storageKey, 'k1:bg:Ag');
    });

    test('encodes zero', () {
      expect(KacheKey('n', [0]).storageKey, 'k1:bg:AwAAAAEw');
    });

    test('encodes negative integers', () {
      expect(KacheKey('n', [-42]).storageKey, 'k1:bg:AwAAAAMtNDI');
    });

    test('encodes large integers', () {
      expect(
        KacheKey('n', [9223372036854775807]).storageKey,
        'k1:bg:AwAAABM5MjIzMzcyMDM2ODU0Nzc1ODA3',
      );
    });

    test('encodes ASCII strings', () {
      expect(KacheKey('n', ['hello']).storageKey, 'k1:bg:BAAAAAVoZWxsbw');
    });

    test('encodes Unicode strings', () {
      expect(KacheKey('n', ['你好']).storageKey, 'k1:bg:BAAAAAbkvaDlpb0');
      expect(KacheKey('n', ['😀']).storageKey, 'k1:bg:BAAAAATwn5iA');
    });

    test('encodes byte lists', () {
      expect(
        KacheKey('n', [
          Uint8List.fromList([0, 255, 16]),
        ]).storageKey,
        'k1:bg:BQAAAAMA_xA',
      );
    });

    test('encodes mixed parts in order', () {
      final key = KacheKey('scope', [
        null,
        false,
        true,
        1,
        '1',
        Uint8List.fromList([1, 2]),
      ]);

      expect(key.storageKey, 'k1:c2NvcGU:AAECAwAAAAExBAAAAAExBQAAAAIBAg');
    });
  });

  group('KacheKey identity', () {
    test('keeps typed values collision-free', () {
      expect(KacheKey('n', [1]), isNot(KacheKey('n', ['1'])));
      expect(KacheKey('n', [null]), isNot(KacheKey('n', ['null'])));
      expect(KacheKey('n', [false]), isNot(KacheKey('n', [0])));
    });

    test('keeps adjacent part boundaries collision-free', () {
      final first = KacheKey('n', ['ab', 'c']);
      final second = KacheKey('n', ['a', 'bc']);

      expect(first.storageKey, 'k1:bg:BAAAAAJhYgQAAAABYw');
      expect(second.storageKey, 'k1:bg:BAAAAAFhBAAAAAJiYw');
      expect(first, isNot(second));
    });

    test('does not normalize composed and decomposed Unicode', () {
      final composed = KacheKey('n', ['é']);
      final decomposed = KacheKey('n', ['é']);

      expect(composed.storageKey, 'k1:bg:BAAAAALDqQ');
      expect(decomposed.storageKey, 'k1:bg:BAAAAANlzIE');
      expect(composed, isNot(decomposed));
    });

    test('uses the canonical storage key for equality and hash codes', () {
      final first = KacheKey('users', [7, 'profile']);
      final second = KacheKey('users', [7, 'profile']);
      final different = KacheKey('users', [7, 'settings']);

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(different));
    });
  });

  group('KacheKey namespace prefixes', () {
    test('returns the canonical namespace prefix', () {
      expect(KacheKey.namespacePrefix('foo'), 'k1:Zm9v:');
      expect(KacheKey.namespacePrefix('a:b'), 'k1:YTpi:');
    });

    test('matches only keys in the target namespace', () {
      final prefix = KacheKey.namespacePrefix('foo');

      expect(KacheKey('foo', [1]).storageKey, startsWith(prefix));
      expect(KacheKey('foobar', [1]).storageKey, isNot(startsWith(prefix)));
    });
  });

  group('KacheKey input ownership', () {
    test('copies the parts iterable and byte lists defensively', () {
      final bytes = Uint8List.fromList([1, 2]);
      final parts = <Object?>[bytes];
      final key = KacheKey('n', parts);

      bytes[0] = 9;
      parts.clear();

      expect(key.storageKey, 'k1:bg:BQAAAAIBAg');
      expect(
        key,
        KacheKey('n', [
          Uint8List.fromList([1, 2]),
        ]),
      );
    });

    test('copies byte lists before continuing iterable consumption', () {
      final bytes = Uint8List.fromList([1, 2]);

      final key = KacheKey('n', _mutateBytesDuringIteration(bytes));

      expect(bytes, orderedEquals([9, 2]));
      expect(key.storageKey, 'k1:bg:BQAAAAIBAgI');
    });
  });

  group('KacheKey validation', () {
    test('rejects an empty namespace', () {
      expect(() => KacheKey(''), throwsA(isA<KacheKeyFormatException>()));
      expect(
        () => KacheKey.namespacePrefix(''),
        throwsA(isA<KacheKeyFormatException>()),
      );
    });

    test('rejects doubles and arbitrary objects without stringifying', () {
      expect(
        () => KacheKey('n', [1.0]),
        throwsA(isA<KacheKeyFormatException>()),
      );
      expect(
        () => KacheKey('n', [_Stringifiable()]),
        throwsA(isA<KacheKeyFormatException>()),
      );
    });

    test('rejects unpaired surrogates in namespaces', () {
      for (final namespace in _invalidUnicodeStrings) {
        expect(
          () => KacheKey(namespace),
          throwsA(isA<KacheKeyFormatException>()),
        );
        expect(
          () => KacheKey.namespacePrefix(namespace),
          throwsA(isA<KacheKeyFormatException>()),
        );
      }
    });

    test('rejects unpaired surrogates in string parts', () {
      for (final part in _invalidUnicodeStrings) {
        expect(
          () => KacheKey('n', [part]),
          throwsA(isA<KacheKeyFormatException>()),
        );
      }
    });
  });
}

final _invalidUnicodeStrings = <String>[
  String.fromCharCode(0xd800),
  String.fromCharCode(0xdc00),
  String.fromCharCodes([0xd800, 0x41]),
];

Iterable<Object?> _mutateBytesDuringIteration(Uint8List bytes) sync* {
  yield bytes;
  bytes[0] = 9;
  yield true;
}

final class _Stringifiable {
  @override
  String toString() => 'accepted-by-mistake';
}
