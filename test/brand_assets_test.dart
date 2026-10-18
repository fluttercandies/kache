import 'dart:io';

import 'package:test/test.dart';
import 'package:xml/xml.dart';

const _canonicalLogoPath = 'assets/kache-logo.svg';
const _packagePaths = <String>[
  'packages/kache',
  'packages/kache_flutter',
  'packages/kache_flutter_hooks',
  'packages/kache_hive_ce',
  'packages/kache_hooks_riverpod',
  'packages/kache_riverpod',
  'packages/kache_bloc',
  'packages/kache_connectivity_plus',
  'packages/kache_provider',
];
const _repository = 'https://github.com/fluttercandies/kache';
const _rawMain = 'https://raw.githubusercontent.com/fluttercandies/kache/main';
const _ciBadge =
    '[![CI]($_repository/actions/workflows/ci.yaml/badge.svg?branch=main)]'
    '($_repository/actions/workflows/ci.yaml)';

/// pub.dev drops relative README images, so published READMEs reference the
/// package's own published asset through an absolute URL. The repository
/// README is rendered by GitHub and keeps the relative path.
String _readmeLogo(String root) {
  final source = root == '.'
      ? _canonicalLogoPath
      : '$_rawMain/$root/$_canonicalLogoPath';
  return '<p align="center">\n'
      '  <img src="$source" alt="Kache logo" width="128">\n'
      '</p>';
}

String _packageName(String root) => root.split('/').last;

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
        final logo = _readmeLogo(root);
        expect(
          _occurrences(readme, logo),
          1,
          reason: '$root/$fileName must contain one standard logo block.',
        );
        expect(
          readme.indexOf(logo),
          greaterThan(readme.indexOf('\n')),
          reason: '$root/$fileName must keep its title before the logo.',
        );
        if (root != '.') {
          expect(
            readme,
            isNot(contains('src="assets/')),
            reason:
                '$root/$fileName renders on pub.dev, which drops '
                'relative images.',
          );
        }
      }
    }
  });

  test('every README carries the release badges after its logo', () {
    for (final root in <String>['.', ..._packagePaths]) {
      final license = root == '.' ? 'LICENSE' : '$root/LICENSE';
      final badges = <String>[
        if (root != '.')
          '[![pub package](https://img.shields.io/pub/v/'
              '${_packageName(root)}.svg)]'
              '(https://pub.dev/packages/${_packageName(root)})',
        _ciBadge,
        '[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)]'
            '($_repository/blob/main/$license)',
      ].join('\n');
      expect(File(license).existsSync(), isTrue, reason: license);
      for (final fileName in const <String>['README.md', 'README.zh-CN.md']) {
        final readme = File('$root/$fileName').readAsStringSync();
        expect(
          readme,
          contains('${_readmeLogo(root)}\n\n$badges\n'),
          reason: '$root/$fileName must place its badges after the logo.',
        );
      }
    }
  });

  test('the root package tables link every published package', () {
    for (final fileName in const <String>['README.md', 'README.zh-CN.md']) {
      final readme = File(fileName).readAsStringSync();
      for (final root in _packagePaths) {
        final name = _packageName(root);
        expect(
          readme,
          contains('| [`$name`](https://pub.dev/packages/$name) |'),
          reason: '$fileName must link $name to pub.dev.',
        );
      }
    }
  });
}

int _occurrences(String source, String value) =>
    value.allMatches(source).length;
