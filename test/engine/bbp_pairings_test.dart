import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/engine/bbp_pairings.dart';

void main() {
  test('pairs the upstream Dutch 2025 C5 example', () {
    final dir = 'test/fixtures/bbp';
    final input = File('$dir/dutch_2025_C5.input').readAsStringSync();
    final expected = File('$dir/dutch_2025_C5.output.expected')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .skip(1)
        .map((l) => l.trim().split(' ').map(int.parse).toList())
        .map((p) => (p[0], p[1]))
        .toList();
    expect(bbpPairDutch(input), expected);
  });

  test('reports malformed input as invalid', () {
    expect(() => bbpPairDutch('nonsense'), throwsA(isA<BbpFailure>()));
  });
}
