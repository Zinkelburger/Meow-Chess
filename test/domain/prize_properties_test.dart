import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/prizes.dart';

/// A random prize scenario: scores come from byes (as in prizes_test.dart),
/// drawn from a narrow range so ties are common, with a random table of
/// every prize kind. [pointPrizes] and [unratedCap] switch on the two
/// features that legitimately pay more or less than the pooled cash.
Event randomPrizeEvent(
  int seed, {
  bool pointPrizes = true,
  bool unratedCap = true,
}) {
  final rng = Random(seed);
  bool chance(int percent) => rng.nextInt(100) < percent;
  final count = 1 + rng.nextInt(12);
  final players = [
    for (var i = 0; i < count; i++)
      Player(
        id: 'p$i',
        name: 'Player $i',
        rating: chance(20) ? 0 : 800 + rng.nextInt(1600),
        prizeRating: chance(10) ? 900 + rng.nextInt(1000) : 0,
        withdrawn: chance(8),
        computer: chance(5),
      ),
  ];
  final scores = [for (final _ in players) rng.nextInt(7)];
  final rounds = (scores.fold(0, max) + 1) ~/ 2;
  final ids = [for (final p in players) p.id];
  Json prize(int i) {
    final kind = const [
      'place',
      'place',
      'place',
      'class',
      'under',
      'unrated',
      'junior',
      'senior',
      'points',
      'computer',
    ][rng.nextInt(10)];
    if (kind == 'points' && !pointPrizes) return prize(i);
    final low = 800 + 100 * rng.nextInt(12);
    return {
      'id': 'z$i',
      'kind': kind,
      'place': 1 + rng.nextInt(3),
      if (kind == 'class') 'min': chance(20) ? 0 : low,
      if (kind == 'class' || kind == 'under')
        'max': chance(10) ? 0 : low + 100 * (1 + rng.nextInt(6)),
      if (kind == 'points') 'points': 1 + rng.nextInt(6),
      // Odd cents make every split and reduction leave a remainder.
      'cents': chance(10) ? 0 : 1 + rng.nextInt(40000),
      'trophy': chance(30),
      'guaranteed': chance(15),
      if (kind == 'junior' || kind == 'senior' || chance(5))
        'eligible': [
          for (final id in ids)
            if (chance(40)) id,
        ],
    };
  }

  return Event(
    id: 'e$seed',
    name: 'Random prizes',
    date: '2026-10-09',
    useTiebreaks: chance(50),
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'Open',
        players: ids,
        plannedRounds: rounds == 0 ? 1 : rounds,
        rounds: [
          for (var r = 1; r <= rounds; r++)
            Round(
              number: r,
              games: const [],
              byes: [
                for (var i = 0; i < count; i++)
                  ByeAward(ids[i], (scores[i] - 2 * (r - 1)).clamp(0, 2), 't'),
              ],
            ),
        ],
        prizes: {
          'basedOn': chance(30) ? 1 + rng.nextInt(30) : 0,
          'fundCents': chance(20) ? rng.nextInt(100000) : 0,
          'withdrawnEligible': chance(30),
          if (unratedCap && chance(40))
            'unratedCapCents': 1 + rng.nextInt(10000),
          'list': [for (var i = 0, n = rng.nextInt(9); i < n; i++) prize(i)],
        },
      ),
    ],
  );
}

void main() {
  const scenarios = 3000;

  test('no cash amount is negative and every line agrees with the awards', () {
    for (var seed = 0; seed < scenarios; seed++) {
      final e = randomPrizeEvent(seed);
      final a = allocatePrizes(e, e.sections.single);
      final awarded = {for (final w in a.awards) w.player.id: w.cents};
      final reason = 'seed $seed';
      expect(a.payoutPercent, inInclusiveRange(0, 100), reason: reason);
      for (final w in a.awards) {
        expect(w.cents, greaterThanOrEqualTo(0), reason: reason);
        expect(w.cents > 0 || w.trophies.isNotEmpty, true, reason: reason);
      }
      for (final line in a.lines) {
        expect(line.paidCents, greaterThanOrEqualTo(0), reason: reason);
        expect(line.paidCents, lessThanOrEqualTo(line.prize.cents));
        // Every sharer appears with their whole take-home amount.
        for (final MapEntry(:key, :value) in line.cash.entries) {
          expect(value, greaterThanOrEqualTo(0), reason: reason);
          expect(value, awarded[key] ?? 0, reason: reason);
        }
        if (line.trophyWinner != null) {
          expect(
            a.awards.any(
              (w) =>
                  w.player.id == line.trophyWinner &&
                  w.trophies.contains(line.prize),
            ),
            true,
            reason: reason,
          );
        }
      }
      expect(a.paidCents, awarded.values.fold(0, (s, c) => s + c));
    }
  });

  test('pooled money is conserved to the cent', () {
    for (var seed = 0; seed < scenarios; seed++) {
      final e = randomPrizeEvent(seed, pointPrizes: false, unratedCap: false);
      final a = allocatePrizes(e, e.sections.single);
      // Without point prizes or an unrated limit, every cent of a prize that
      // is awarded reaches someone, and nothing else is paid.
      final pooled = a.lines
          .where((l) => l.cash.isNotEmpty)
          .fold(0, (s, l) => s + l.paidCents);
      expect(a.paidCents, pooled, reason: 'seed $seed');
    }
  });

  test('an unrated limit never creates money', () {
    for (var seed = 0; seed < scenarios; seed++) {
      final e = randomPrizeEvent(seed, pointPrizes: false);
      final a = allocatePrizes(e, e.sections.single);
      final pooled = a.lines
          .where((l) => l.cash.isNotEmpty)
          .fold(0, (s, l) => s + l.paidCents);
      expect(a.paidCents, lessThanOrEqualTo(pooled), reason: 'seed $seed');
    }
  });
}
