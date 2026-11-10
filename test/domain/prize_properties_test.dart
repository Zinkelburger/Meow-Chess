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

  // A tie is examined by the kinds of eligibility in it, not by the ways
  // to hand its prizes out, so its size does not matter.
  group('large ties', () {
    /// [count] players, all on [halves] half-points from one bye, every
    /// eighth unrated, with ten place prizes and a spread of class, Under,
    /// unrated and junior prizes.
    Event field(int count, {int halves = 0, int places = 10}) {
      final players = [
        for (var i = 0; i < count; i++)
          Player(
            id: 'p$i',
            name: 'Player ${'$i'.padLeft(3, '0')}',
            rating: i % 8 == 7 ? 0 : 900 + 37 * (i % 40),
          ),
      ];
      return Event(
        id: 'large',
        name: 'Large tie',
        date: '2026-10-09',
        players: players,
        sections: [
          Section(
            id: 's',
            name: 'Open',
            players: [for (final p in players) p.id],
            plannedRounds: 5,
            rounds: [
              if (halves > 0)
                Round(
                  number: 1,
                  games: const [],
                  byes: [for (final p in players) ByeAward(p.id, halves, 't')],
                ),
            ],
            prizes: {
              'list': [
                for (var n = 1; n <= places; n++)
                  {
                    'id': 'place$n',
                    'kind': 'place',
                    'place': n,
                    'cents': 100000 - 9000 * n,
                    'trophy': n <= 3,
                  },
                for (final max in [2200, 2000, 1800, 1600, 1400, 1200])
                  for (final n in [1, 2])
                    {
                      'id': 'u$max-$n',
                      'kind': 'under',
                      'place': n,
                      'max': max,
                      'cents': (max ~/ 10 + 100 - 60 * n) * 100,
                    },
                for (final min in [1000, 1400, 1800])
                  {
                    'id': 'class$min',
                    'kind': 'class',
                    'min': min,
                    'max': min + 199,
                    'cents': 7500,
                  },
                {'id': 'unr', 'kind': 'unrated', 'cents': 5000},
                {
                  'id': 'junior',
                  'kind': 'junior',
                  'cents': 4000,
                  'eligible': [
                    for (final (i, p) in players.indexed)
                      if (i % 5 == 0) p.id,
                  ],
                },
              ],
            },
          ),
        ],
      );
    }

    PrizeAllocation timed(Event e, {int withinMs = 1000}) {
      final watch = Stopwatch()..start();
      final a = allocatePrizes(e, e.sections.single);
      expect(
        watch.elapsedMilliseconds,
        lessThan(withinMs),
        reason: '${e.players.length} players took ${watch.elapsed}',
      );
      return a;
    }

    void conserved(PrizeAllocation a) {
      final pooled = a.lines
          .where((l) => l.cash.isNotEmpty)
          .fold(0, (s, l) => s + l.paidCents);
      expect(a.paidCents, pooled);
      for (final w in a.awards) {
        expect(w.cents, greaterThanOrEqualTo(0));
      }
    }

    test('300 players tied before round 1, 10 places and class prizes', () {
      final a = timed(field(300));
      conserved(a);
      // Every prize with an eligible player is in someone's pool.
      expect(a.lines.where((l) => l.cash.isEmpty), isEmpty);
      // Nobody takes more than the top prize they could win alone.
      expect(
        a.awards.every((w) => w.cents <= 91000),
        isTrue,
        reason: 'first place pays \$910',
      );
    });

    test('300 players all on one point after round 1', () {
      conserved(timed(field(300, halves: 2)));
    });

    test('the sizes that used to run for minutes', () {
      for (final (count, places) in [(24, 5), (40, 6), (64, 8), (150, 10)]) {
        conserved(timed(field(count, places: places)));
      }
    });

    test('a tie of all-eligible players pools the top prizes equally', () {
      final players = [
        for (var i = 0; i < 40; i++)
          Player(id: 'p$i', name: 'Player $i', rating: 2000),
      ];
      final e = Event(
        id: 'pool',
        name: 'Pool',
        date: '2026-10-09',
        players: players,
        sections: [
          Section(
            id: 's',
            name: 'Open',
            players: [for (final p in players) p.id],
            prizes: {
              'list': [
                for (var n = 1; n <= 6; n++)
                  {'id': 'p$n', 'kind': 'place', 'place': n, 'cents': 4000 * n},
              ],
            },
          ),
        ],
      );
      final a = timed(e);
      // $40 + … + $240 = $840 among 40.
      expect(a.paidCents, 84000);
      expect({for (final w in a.awards) w.cents}, {2100});
      expect(a.awards, hasLength(40));
    });
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
