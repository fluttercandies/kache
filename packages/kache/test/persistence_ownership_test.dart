import 'package:kache/kache.dart';
import 'package:test/test.dart';

void main() {
  test('defines borrowed and owned backend ownership', () {
    expect(KachePersistenceOwnership.values, [
      KachePersistenceOwnership.borrowed,
      KachePersistenceOwnership.owned,
    ]);
  });
}
