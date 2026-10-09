import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/us_chess.dart';

void main() {
  test('28D1c: FIDE ratings use the two-part general conversion', () {
    // -1073 + 1.5667 × 1800 = 1747.06
    expect(convertForeignRating('FIDE', 1800).rating, 1747);
    expect(convertForeignRating('FIDE', 2000).rating, 2060);
    // 20 + 1.02 × 2400 = 2468
    expect(convertForeignRating('FIDE', 2400).rating, 2468);
    expect(convertForeignRating('fide', 2400).note, contains('28D1c'));
  });

  test('28D1a/b/f/g: fixed offsets', () {
    expect(convertForeignRating('CAN', 1700).rating, 1700);
    expect(convertForeignRating('BER', 1700).rating, 1700);
    expect(convertForeignRating('JAM', 1700).rating, 1700);
    expect(convertForeignRating('QUICK', 1700).rating, 1700);
    expect(convertForeignRating('FQE', 1700).rating, 1800);
    expect(convertForeignRating('OTHER', 1700).rating, 1900);
    expect(convertForeignRating('USSR', 2100).rating, 2350);
    expect(convertForeignRating('PHI', 2100).rating, 2350);
  });

  test('28D1d/e: England and Germany formulas', () {
    expect(convertForeignRating('ENG', 150).rating, 1900);
    expect(convertForeignRating('ENG', 1900).rating, isNull);
    expect(convertForeignRating('GER', 100).rating, 2140);
  });

  test('28D1h and unknown federations give no number, with a reason', () {
    final brazil = convertForeignRating('BRA', 2000);
    expect(brazil.rating, isNull);
    expect(brazil.note, contains('2200'));
    final unknown = convertForeignRating('ATLANTIS', 2000);
    expect(unknown.rating, isNull);
    expect(unknown.note, contains('No conversion'));
    expect(convertForeignRating('FIDE', 0).rating, isNull);
  });

  test('5E2: a time control without a delay gets the 5E minimum', () {
    expect(delayHint('G/60'), contains('d5'));
    expect(delayHint('G/25'), contains('d3'));
    expect(delayHint('G/5'), contains('d2'));
    expect(delayHint('40/90, SD/30'), contains('d5'));
    expect(delayHint('G/60 d5'), isNull);
    expect(delayHint('G/90 inc/30'), isNull);
    expect(delayHint('G/60 d0'), isNull);
    expect(delayHint('nonsense'), isNull);
    expect(delayHint(''), isNull);
  });
}
