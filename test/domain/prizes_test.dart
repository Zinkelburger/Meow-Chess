import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/prizes.dart';

/// One entrant: id, prize rating (0 = unrated) and score in half-points.
typedef Entrant = (String, int, int);

/// Scores come from byes so the fixture needs no opponents; names sort in
/// id order, which stands in for tie-break order when tie-breaks are on.
Event fixture(
  List<Entrant> entrants,
  List<Json> prizes, {
  int basedOn = 0,
  int fundCents = 0,
  bool withdrawnEligible = false,
  int unratedCapCents = 0,
  Player Function(Player)? tweak,
  bool useTiebreaks = false,
  List<Section> extraSections = const [],
}) {
  final players = [
    for (final (id, rating, _) in entrants)
      (tweak ?? (p) => p)(Player(id: id, name: 'Player $id', rating: rating)),
  ];
  final rounds = entrants.fold(0, (m, e) => e.$3 > m ? e.$3 : m);
  final count = (rounds + 1) ~/ 2;
  return Event(
    id: 'e',
    name: 'Prizes',
    date: '2026-10-09',
    useTiebreaks: useTiebreaks,
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'Open',
        players: players.map((p) => p.id).toList(),
        plannedRounds: count == 0 ? 1 : count,
        rounds: [
          for (var r = 1; r <= count; r++)
            Round(
              number: r,
              games: const [],
              byes: [
                for (final (id, _, halves) in entrants)
                  ByeAward(id, (halves - 2 * (r - 1)).clamp(0, 2), 'test'),
              ],
            ),
        ],
        prizes: {
          'basedOn': basedOn,
          'fundCents': fundCents,
          'withdrawnEligible': withdrawnEligible,
          if (unratedCapCents > 0) 'unratedCapCents': unratedCapCents,
          'list': prizes,
        },
      ),
      ...extraSections,
    ],
  );
}

Json place(
  int n,
  int dollars, {
  bool trophy = false,
  bool guaranteed = false,
}) => {
  'id': 'p$n',
  'label': '',
  'kind': 'place',
  'place': n,
  'cents': dollars * 100,
  'trophy': trophy,
  if (guaranteed) 'guaranteed': true,
};
Json classPrize(
  String id,
  int min,
  int max,
  int dollars, {
  int place = 1,
  bool trophy = false,
}) => {
  'id': id,
  'label': '',
  'kind': 'class',
  'place': place,
  'min': min,
  'max': max,
  'cents': dollars * 100,
  'trophy': trophy,
};
Json under(
  String id,
  int max,
  int dollars, {
  int place = 1,
  bool trophy = false,
}) => {
  'id': id,
  'label': '',
  'kind': 'under',
  'place': place,
  'max': max,
  'cents': dollars * 100,
  'trophy': trophy,
};

Map<String, int> cash(PrizeAllocation a) => {
  for (final w in a.awards)
    if (w.cents > 0) w.player.id: w.cents ~/ 100,
};
Map<String, List<String>> trophies(PrizeAllocation a) => {
  for (final w in a.awards)
    if (w.trophies.isNotEmpty) w.player.id: [for (final t in w.trophies) t.id],
};
PrizeAllocation run(Event e) => allocatePrizes(e, e.sections.first);

void main() {
  group('32B ties (rulebook examples under 32B5)', () {
    test('Example 1: pooled places split equally', () {
      final e = fixture(
        [
          ('1', 2200, 9),
          ('2', 2200, 9),
          ('3', 2000, 8),
          ('4', 2000, 8),
          ('5', 2000, 8),
        ],
        [place(1, 200), place(2, 100), place(3, 75)],
      );
      final a = run(e);
      expect(cash(a), {'1': 150, '2': 150, '3': 25, '4': 25, '5': 25});
      expect(
        a.explanations,
        contains(
          '2 players tied at 4.5 (Player 1, Player 2) for 1st + 2nd: '
          '\$200 + \$100 = \$300 pooled, \$150 each.',
        ),
      );
      expect(
        a.explanations,
        contains(
          '3 players tied at 4 (Player 3, Player 4, Player 5) for 3rd (\$75) split, \$25 each.',
        ),
      );
    });

    test('Example 2: class prizes stay with their class', () {
      final e = fixture(
        [
          ('1', 2300, 10),
          ('2', 2300, 10),
          ('3', 2300, 10),
          ('4', 2050, 8),
          ('5', 1900, 8),
          ('6', 1700, 8),
        ],
        [
          place(1, 400),
          place(2, 200),
          classPrize('a', 1800, 1999, 100),
          classPrize('b', 1600, 1799, 50),
        ],
      );
      expect(cash(run(e)), {'1': 200, '2': 200, '3': 200, '5': 100, '6': 50});
    });

    test('Example 2 note: Under prizes pool across the tie', () {
      final e = fixture(
        [
          ('1', 2300, 10),
          ('2', 2300, 10),
          ('3', 2300, 10),
          ('4', 2050, 8),
          ('5', 1900, 8),
          ('6', 1700, 8),
        ],
        [
          place(1, 400),
          place(2, 200),
          under('u2000', 2000, 100),
          under('u1800', 1800, 50),
        ],
      );
      expect(cash(run(e)), {'1': 200, '2': 200, '3': 200, '5': 75, '6': 75});
    });

    test('Example 3: one prize per player goes into the pool', () {
      final e = fixture(
        [
          ('1', 2300, 10),
          ('2', 2300, 10),
          ('3', 2300, 9),
          ('4', 1900, 9),
          ('5', 1850, 9),
          ('6', 1700, 9),
          ('7', 1950, 8),
        ],
        [
          place(1, 250),
          place(2, 200),
          place(3, 150),
          place(4, 100),
          classPrize('a1', 1800, 1999, 75),
          classPrize('a2', 1800, 1999, 50, place: 2),
          classPrize('b1', 1600, 1799, 75),
        ],
      );
      final a = run(e);
      expect(cash(a), {
        '1': 225,
        '2': 225,
        '3': 100,
        '4': 100,
        '5': 100,
        '6': 100,
        '7': 50,
      });
      // A pooled prize names every sharer and what it was pooled with.
      final third = a.lines.firstWhere((l) => l.prize.id == 'p3');
      expect(third.cash, {'3': 10000, '4': 10000, '5': 10000, '6': 10000});
      expect(third.pooledWith, ['p4', 'a1', 'b1']);
      expect(a.lines.firstWhere((l) => l.prize.id == 'a2').cash, {'7': 5000});
    });

    test('32B3: a player takes a prize the rest of the tie cannot win', () {
      // 33D2 Example 5, cash part.
      final e = fixture(
        [('1', 1900, 9), ('2', 2100, 9), ('3', 2150, 9), ('4', 1900, 7)],
        [
          under('u2200a', 2200, 100),
          under('u2200b', 2200, 50, place: 2),
          under('u2000', 2000, 80),
        ],
      );
      final a = run(e);
      expect(cash(a), {'1': 80, '2': 75, '3': 75});
      expect(
        a.explanations.any(
          (x) => x.contains('Player 1 does better from 1st Under 2000'),
        ),
        isTrue,
      );
    });

    test('32B3: no one gets more than the prize they would win alone', () {
      final e = fixture(
        [('h', 2000, 10), ('c', 2000, 10)],
        [
          place(1, 300),
          {'id': 'comp', 'kind': 'computer', 'cents': 2000},
        ],
        tweak: (p) => p.id == 'c' ? p.copy(computer: true) : p,
      );
      expect(cash(run(e)), {'h': 300, 'c': 20});
    });

    test('34C: tie-break rankings never split cash', () {
      final e = fixture(
        [('1', 2200, 9), ('2', 2200, 9)],
        [place(1, 200), place(2, 100)],
        useTiebreaks: true,
      );
      expect(cash(run(e)), {'1': 150, '2': 150});
    });
  });

  group('32B4 equal amounts', () {
    test('place beats class; the class prize stays for the next player', () {
      final e = fixture(
        [('1', 1900, 10), ('2', 1850, 8)],
        [place(1, 100), classPrize('a', 1800, 1999, 100)],
      );
      final a = run(e);
      expect(cash(a), {'1': 100, '2': 100});
      expect(a.lines.first.cash, {'1': 10000});
    });

    test('a higher class beats a lower one', () {
      final e = fixture(
        [('1', 1900, 10), ('2', 1700, 8)],
        [classPrize('a', 1800, 1999, 100), under('u2000', 2000, 100)],
      );
      final a = run(e);
      expect(a.lines.firstWhere((l) => l.prize.id == 'a').cash, {'1': 10000});
      expect(cash(a), {'1': 100, '2': 100});
    });

    test('a rating class beats a junior prize', () {
      final e = fixture(
        [('1', 1900, 10), ('2', 2100, 8)],
        [
          classPrize('a', 1800, 1999, 50),
          {
            'id': 'jr',
            'kind': 'junior',
            'cents': 5000,
            'eligible': ['1', '2'],
          },
        ],
      );
      final a = run(e);
      expect(a.lines.firstWhere((l) => l.prize.id == 'a').cash, {'1': 5000});
      expect(cash(a), {'1': 50, '2': 50});
    });
  });

  group('32C payment', () {
    test('32C1: withdrawn players are ineligible unless the TD allows it', () {
      final e = fixture(
        [('1', 2000, 10), ('2', 2000, 8)],
        [place(1, 100)],
        tweak: (p) => p.id == '1' ? p.copy(withdrawn: true) : p,
      );
      final a = run(e);
      expect(cash(a), {'2': 100});
      expect(a.explanations.first, contains('withdrew'));
      final allowed = fixture(
        [('1', 2000, 10), ('2', 2000, 8)],
        [place(1, 100)],
        withdrawnEligible: true,
        tweak: (p) => p.id == '1' ? p.copy(withdrawn: true) : p,
      );
      expect(cash(run(allowed)), {'1': 100});
    });

    test(
      '32C2 / 32C3: one finisher takes the class prize; none means none',
      () {
        final e = fixture(
          [('1', 2200, 10), ('2', 1850, 2)],
          [
            place(1, 100),
            classPrize('a', 1800, 1999, 40),
            classPrize('b', 1600, 1799, 30),
          ],
        );
        final a = run(e);
        expect(cash(a), {'1': 100, '2': 40});
        final b = a.lines.firstWhere((l) => l.prize.id == 'b');
        expect(b.cash, isEmpty);
        expect(b.note, 'No eligible player (32C3)');
      },
    );

    test('32C4: proportional payout with the 50% minimum above \$500', () {
      Event based(int entries, int fund, int basedOn) => fixture(
        [for (var i = 0; i < entries; i++) ('$i', 2000, i == 0 ? 2 : 0)],
        [place(1, fund)],
        basedOn: basedOn,
      );
      expect(run(based(30, 1000, 100)).payoutPercent, 50);
      expect(cash(run(based(30, 1000, 100))), {'0': 500});
      expect(run(based(70, 1000, 100)).payoutPercent, 70);
      expect(run(based(10, 400, 40)).payoutPercent, 25);
      expect(cash(run(based(10, 400, 40))), {'0': 100});
      expect(run(based(40, 400, 40)).payoutPercent, 100);
    });

    test('32E: a guaranteed prize is never reduced', () {
      final e = fixture(
        [for (var i = 0; i < 30; i++) ('$i', 2000, i < 2 ? 4 - 2 * i : 0)],
        [place(1, 500, guaranteed: true), place(2, 300)],
        basedOn: 60,
        fundCents: 200000,
      );
      final a = run(e);
      expect(cash(a), {'0': 500, '1': 150});
      expect(a.explanations.first, contains('guaranteed prizes pay in full'));
    });

    test('32C5: an entry replaced by a re-entry wins nothing', () {
      final e = fixture(
        [('1', 2000, 10), ('1re', 2000, 6), ('2', 2000, 8)],
        [place(1, 100), place(2, 50)],
        tweak: (p) => p.id == '1re' ? p.copy(reentryOf: '1') : p,
      );
      expect(cash(run(e)), {'2': 100, '1re': 50});
    });

    test('32C6: an unrated limit leaves the remainder in the point group', () {
      final e = fixture(
        [('u', 0, 10), ('r', 2000, 10)],
        [place(1, 300), place(2, 100)],
        unratedCapCents: 10000,
      );
      expect(cash(run(e)), {'u': 100, 'r': 300});
    });

    test(
      '32C6: a clear unrated winner leaves the remainder to the next group',
      () {
        final e = fixture(
          [('u', 0, 10), ('r', 2000, 8), ('s', 2000, 8)],
          [place(1, 300), place(2, 100)],
          unratedCapCents: 10000,
        );
        final a = run(e);
        expect(cash(a), {'u': 100, 'r': 150, 's': 150});
        expect(
          a.explanations.any((x) => x.contains('remaining \$200 of 1st')),
          isTrue,
        );
      },
    );
  });

  group('33C–33F', () {
    test('33C: Under prizes take every class below; Class prizes do not', () {
      // 33D2 Example 3, cash part.
      final players = <Entrant>[
        ('1', 1650, 10),
        ('2', 1750, 10),
        ('3', 2020, 9),
        ('4', 1675, 9),
        ('5', 1920, 9),
        ('6', 1700, 9),
        ('7', 1845, 9),
      ];
      final underPrizes = fixture(players, [
        under('u2000a', 2000, 200),
        under('u2000b', 2000, 100, place: 2),
        under('u1800a', 1800, 200),
        under('u1800b', 1800, 100, place: 2),
      ]);
      expect(cash(run(underPrizes)), {
        '1': 200,
        '2': 200,
        '4': 50,
        '5': 50,
        '6': 50,
        '7': 50,
      });
      final classPrizes = fixture(players, [
        classPrize('a1', 1800, 1999, 200),
        classPrize('a2', 1800, 1999, 100, place: 2),
        under('u1800a', 1800, 200),
        under('u1800b', 1800, 100, place: 2),
      ]);
      // Players 1 and 2 share both Under 1800 prizes; the Class A prizes go
      // to players 5 and 7, the only A players, and the B players at 4.5
      // find nothing left.
      expect(cash(run(classPrizes)), {'1': 150, '2': 150, '5': 150, '7': 150});
    });

    test('33E: prizes by points go to every player at that score', () {
      final e = fixture(
        [
          ('1', 2000, 10),
          ('2', 2000, 10),
          ('3', 2000, 9),
          ('4', 2000, 8),
          ('5', 2000, 6),
        ],
        [
          {'id': 'five', 'kind': 'points', 'points': 10, 'cents': 10000},
          {'id': 'fourhalf', 'kind': 'points', 'points': 9, 'cents': 5000},
          {'id': 'four', 'kind': 'points', 'points': 8, 'cents': 3000},
        ],
      );
      expect(cash(run(e)), {'1': 100, '2': 100, '3': 50, '4': 30});
    });

    test('33F: unrateds win only place and unrated prizes', () {
      final e = fixture(
        [('u', 0, 10), ('v', 0, 8), ('b', 1700, 6)],
        [
          place(1, 100),
          under('u1800', 1800, 50),
          {'id': 'unr', 'kind': 'unrated', 'cents': 2000},
        ],
      );
      final a = run(e);
      expect(cash(a), {'u': 100, 'v': 20, 'b': 50});
    });

    test('house players and computers only win what is designated', () {
      final e = fixture(
        [('h', 2000, 10), ('c', 2000, 10), ('p', 2000, 8)],
        [
          place(1, 100),
          {'id': 'comp', 'kind': 'computer', 'cents': 2000},
        ],
        tweak: (p) => p.id == 'h'
            ? p.copy(house: true)
            : p.id == 'c'
            ? p.copy(computer: true)
            : p,
      );
      expect(cash(run(e)), {'p': 100, 'c': 20});
    });
  });

  group('32F / 33D trophies', () {
    test('33D2 Example 1: money pooled, trophies by tie-break', () {
      final e = fixture(
        [
          ('1', 2250, 10),
          ('2', 2225, 9),
          ('3', 1940, 9),
          ('4', 1865, 8),
          ('5', 1990, 8),
        ],
        [
          place(1, 200, trophy: true),
          place(2, 100, trophy: true),
          place(3, 50, trophy: true),
          classPrize('a', 1800, 1999, 40, trophy: true),
        ],
        useTiebreaks: true,
      );
      final a = run(e);
      expect(cash(a), {'1': 200, '2': 75, '3': 75, '4': 20, '5': 20});
      expect(trophies(a), {
        '1': ['p1'],
        '2': ['p2'],
        '3': ['p3'],
        '4': ['a'],
      });
    });

    test('33D2 Example 2: a player takes the higher-ranked Under trophy', () {
      final e = fixture(
        [
          ('1', 2250, 10),
          ('2', 2225, 9),
          ('3', 1940, 9),
          ('4', 2375, 8),
          ('5', 1990, 8),
          ('6', 2125, 7),
          ('7', 1865, 7),
        ],
        [
          place(1, 200, trophy: true),
          place(2, 100, trophy: true),
          place(3, 50, trophy: true),
          under('u2200', 2200, 40, trophy: true),
          under('u2000', 2000, 30, trophy: true),
        ],
        useTiebreaks: true,
      );
      final a = run(e);
      expect(cash(a), {'1': 200, '2': 75, '3': 75, '5': 40, '7': 30});
      expect(trophies(a), {
        '1': ['p1'],
        '2': ['p2'],
        '3': ['p3'],
        '5': ['u2200'],
        '7': ['u2000'],
      });
    });

    test('33D2 Example 5: trophies are calculated separately from money', () {
      final e = fixture(
        [('1', 1900, 9), ('2', 2100, 9), ('3', 2150, 9), ('4', 1900, 7)],
        [
          under('u2200a', 2200, 100, trophy: true),
          under('u2200b', 2200, 50, place: 2, trophy: true),
          under('u2000', 2000, 80, trophy: true),
        ],
        useTiebreaks: true,
      );
      final a = run(e);
      expect(cash(a), {'1': 80, '2': 75, '3': 75});
      expect(trophies(a), {
        '1': ['u2200a'],
        '2': ['u2200b'],
        '4': ['u2000'],
      });
    });
  });

  group('table parsing', () {
    test('round-trips and reports the announced fund', () {
      final table = PrizeTable.fromJson({
        'basedOn': 40,
        'list': [place(1, 100), classPrize('a', 1800, 1999, 50)],
      });
      expect(table.announcedCents, 15000);
      expect(PrizeTable.fromJson(table.toJson()).toJson(), table.toJson());
      expect(table.list.last.title, '1st 1800–1999');
      expect(dollars(123456), '\$1,234.56');
      expect(dollars(20000), '\$200');
    });

    test('rejects unknown kinds, duplicate ids and reversed ranges', () {
      expect(
        () => PrizeTable.fromJson({
          'list': [
            {'id': 'x', 'kind': 'best-game'},
          ],
        }),
        throwsA(isA<TournamentException>()),
      );
      expect(
        () => PrizeTable.fromJson({
          'list': [place(1, 10), place(1, 10)],
        }),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'message',
            contains('used twice'),
          ),
        ),
      );
      expect(
        () => PrizeTable.fromJson({
          'list': [classPrize('a', 2000, 1800, 10)],
        }),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'message',
            contains('reversed'),
          ),
        ),
      );
    });

    test('an empty table explains itself', () {
      final e = fixture([('1', 2000, 2)], []);
      final a = run(e);
      expect(a.awards, isEmpty);
      expect(a.explanations, ['No prizes are announced for this section.']);
    });
  });
}
