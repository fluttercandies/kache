import 'dart:io';

import 'package:test/test.dart';
import 'package:xml/xml.dart';

const _canonicalLogoPath = 'assets/kache-logo.svg';
const _packagePaths = <String>[
  'packages/kache',
  'packages/kache_flutter',
  'packages/kache_hive_ce',
  'packages/kache_riverpod',
  'packages/kache_bloc',
  'packages/kache_connectivity_plus',
  'packages/kache_provider',
];
const _readmeLogo = '''<p align="center">
  <img src="assets/kache-logo.svg" alt="Kache logo" width="128">
</p>''';

void main() {
  test('canonical logo is an accessible self-contained vector mark', () {
    final file = File(_canonicalLogoPath);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'The canonical Kache logo must exist.',
    );

    final source = file.readAsStringSync();
    final document = XmlDocument.parse(source);
    final root = document.rootElement;

    expect(root.name.local, 'svg');
    expect(root.getAttribute('xmlns'), 'http://www.w3.org/2000/svg');
    expect(root.getAttribute('viewBox'), '0 0 256 256');
    expect(root.getAttribute('role'), 'img');
    expect(root.findElements('title').single.innerText, 'Kache logo');
    expect(
      root.findElements('desc').single.innerText,
      contains('stale-while-revalidate'),
    );

    final gradientIds = <String>{
      ...root
          .findAllElements('linearGradient')
          .map((element) => element.getAttribute('id'))
          .nonNulls,
      ...root
          .findAllElements('radialGradient')
          .map((element) => element.getAttribute('id'))
          .nonNulls,
    };
    expect(
      gradientIds,
      containsAll(<String>{
        'stale-shell',
        'stale-glass',
        'fresh-shell',
        'fresh-glass',
        'metal',
        'ground-shadow',
      }),
    );
    expect(
      root
          .findAllElements('filter')
          .map((element) => element.getAttribute('id')),
      contains('cache-shadow'),
    );
    expect(source, contains('filter="url(#cache-shadow)"'));
    expect(source, isNot(matches(RegExp(r'url\((?!#)'))));
    for (final forbidden in const <String>[
      '<script',
      '<image',
      '<foreignObject',
      '<text',
      'font-family',
      'href=',
      'data:',
    ]) {
      expect(
        source,
        isNot(contains(forbidden)),
        reason: 'The logo must not contain $forbidden.',
      );
    }
  });

  test('every published package carries the canonical logo bytes', () {
    final canonical = File(_canonicalLogoPath).readAsBytesSync();

    for (final packagePath in _packagePaths) {
      final copy = File('$packagePath/assets/kache-logo.svg');
      expect(copy.existsSync(), isTrue, reason: '$packagePath needs its logo.');
      expect(
        copy.readAsBytesSync(),
        canonical,
        reason: '$packagePath must use the canonical logo bytes.',
      );
    }
  });

  test('all bilingual READMEs embed their local published logo', () {
    for (final root in <String>['.', ..._packagePaths]) {
      for (final fileName in const <String>['README.md', 'README.zh-CN.md']) {
        final readme = File('$root/$fileName').readAsStringSync();
        expect(
          _occurrences(readme, _readmeLogo),
          1,
          reason: '$root/$fileName must contain one standard logo block.',
        );
        expect(
          readme.indexOf(_readmeLogo),
          greaterThan(readme.indexOf('\n')),
          reason: '$root/$fileName must keep its title before the logo.',
        );
      }
    }
  });
}

int _occurrences(String source, String value) =>
    value.allMatches(source).length;
