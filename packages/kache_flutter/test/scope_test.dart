import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kache/kache.dart';
import 'package:kache_flutter/kache_flutter.dart';

void main() {
  testWidgets('provides the client to descendants', (tester) async {
    final client = KacheClient();
    late KacheClient resolved;

    await tester.pumpWidget(
      KacheScope(
        client: client,
        child: Builder(
          builder: (context) {
            resolved = KacheScope.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved, same(client));
    await client.close();
  });

  testWidgets('borrowed scope never closes the client', (tester) async {
    final client = KacheClient();
    await tester.pumpWidget(
      KacheScope(client: client, child: const SizedBox()),
    );

    await tester.pumpWidget(const SizedBox());

    expect(client.isClosed, isFalse);
    await client.close();
  });

  testWidgets('owned scope closes the client on dispose', (tester) async {
    final client = KacheClient();
    await tester.pumpWidget(
      KacheScope(
        client: client,
        ownership: KacheScopeOwnership.owned,
        child: const SizedBox(),
      ),
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(client.isClosed, isTrue);
  });

  testWidgets('maybeOf returns null outside a scope', (tester) async {
    KacheClient? resolved;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          resolved = KacheScope.maybeOf(context);
          return const SizedBox();
        },
      ),
    );

    expect(resolved, isNull);
  });
}
