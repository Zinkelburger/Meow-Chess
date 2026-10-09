import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';

/// Rule-linked fixtures for the US Chess Swiss engine, built from the
/// rulebook's own worked examples (7th edition, rules 28–29).
///
/// [scenario] builds an event one round before the round under test. Each
/// entrant has a rating, a color history (`W`, `B`, or `x` for a half-point
/// bye) and a score in half points. Colors are realized against filler
/// opponents who then withdraw, so only the named players are paired.
typedef Entrant = ({String id, int rating, String colors, int points});

String Function() ids(String prefix) {
  var next = 0;
  return () => '$prefix${next++}';
}

Event scenario(
  List<Entrant> entrants, {
  int plannedRounds = 8,
  Set<String> variations = const {},
  String colorToss = '',
  List<(String, String)> met = const [],
  Map<String, Player Function(Player)> adjust = const {},
}) {
  final rounds = entrants.first.colors.length;
  final players = <Player>[
    for (final e in entrants)
      Player(id: e.id, name: 'P${e.id}', rating: e.rating, checkedIn: true),
  ];
  final fillers = <Player>[];
  final roundList = <Round>[];
  var board = 1;
  for (var r = 1; r <= rounds; r++) {
    final games = <Game>[];
    final byes = <ByeAward>[];
    for (final e in entrants) {
      final c = e.colors[r - 1];
      if (c == 'x') {
        byes.add(ByeAward(e.id, 1, 'Requested bye'));
        continue;
      }
      final filler = Player(
        id: 'f${e.id}r$r',
        name: 'Filler',
        rating: 1000,
        withdrawn: true,
      );
      fillers.add(filler);
      // Points accrue as wins first, then a draw, then losses; a bye
      // round consumes a half point.
      final before = e.colors.substring(0, r - 1);
      final spent =
          before.replaceAll('x', '').length * 2 + before.split('x').length - 1;
      final remaining = e.points - spent;
      final outcome = remaining >= 2
          ? (c == 'W' ? Outcome.whiteWin : Outcome.blackWin)
          : remaining == 1
          ? Outcome.draw
          : (c == 'W' ? Outcome.blackWin : Outcome.whiteWin);
      games.add(
        Game(
          id: 'g${e.id}r$r',
          white: c == 'W' ? e.id : filler.id,
          black: c == 'W' ? filler.id : e.id,
          board: board++,
          outcome: outcome,
        ),
      );
    }
    roundList.add(Round(number: r, games: games, byes: byes));
  }
  // Prior meetings between named players replace one filler game each.
  var extra = 1;
  for (final (a, b) in met) {
    roundList[0] = roundList[0].copy(
      games: [
        ...roundList[0].games.where(
          (g) => g.white != a && g.black != a && g.white != b && g.black != b,
        ),
        Game(
          id: 'met${extra++}',
          white: a,
          black: b,
          board: 900 + extra,
          outcome: Outcome.draw,
        ),
      ],
    );
  }
  var event = Event(
    id: 'fixture',
    name: 'Fixture',
    date: '2026-10-09',
    colorToss: colorToss,
    players: [for (final p in players) adjust[p.id]?.call(p) ?? p, ...fillers],
    sections: [
      Section(
        id: 's',
        name: 'Open',
        players: [for (final p in players) p.id, for (final f in fillers) f.id],
        plannedRounds: plannedRounds,
        rounds: roundList,
        variations: variations,
      ),
    ],
  );
  return event;
}

/// Scores as the engine sees them, to check the fixture itself.
Map<String, int> fixtureScores(Event e) => {
  for (final p in e.players.where((p) => !p.withdrawn))
    p.id: e.sections.single.rounds.fold(0, (sum, r) {
      var s = sum;
      for (final g in r.games) {
        if (g.white == p.id) s += g.outcome.whiteScore;
        if (g.black == p.id) s += g.outcome.blackScore;
      }
      for (final b in r.byes) {
        if (b.player == p.id) s += b.points;
      }
      return s;
    }),
};

List<(String, String)> games(Round r) => [
  for (final g in r.games) (g.white, g.black),
];

void main() {
  group('29E5 transpositions and interchanges', () {
    test('29E5c: a transposition counts the smaller difference', () {
      // 2000 WB vs 1800 WB / 1980 BW vs 1500 BW: trading 2000 for 1980 is
      // a 20-point switch, so the pairings become 2000-1500 and 1800-1980.
      final e = scenario([
        (id: 'a', rating: 2000, colors: 'WB', points: 4),
        (id: 'b', rating: 1980, colors: 'BW', points: 4),
        (id: 'c', rating: 1800, colors: 'WB', points: 4),
        (id: 'd', rating: 1500, colors: 'BW', points: 4),
      ]);
      final r = proposeRound(e, e.sections.single, ids('x'));
      expect(games(r), [('a', 'd'), ('c', 'b')]);
      expect(r.explanations.join('\n'), contains('29E5c'));
    });

    test('29E5e example 1: a transposition within 80 beats an interchange', () {
      final e = scenario([
        (id: 'a', rating: 2050, colors: 'WBW', points: 6),
        (id: 'b', rating: 1870, colors: 'BWB', points: 6),
        (id: 'c', rating: 1850, colors: 'WBW', points: 6),
        (id: 'd', rating: 1780, colors: 'BWB', points: 6),
      ]);
      final r = proposeRound(e, e.sections.single, ids('x'));
      expect(games(r), [('d', 'a'), ('b', 'c')]);
    });

    test(
      '29E5e example 2: a 100-point transposition yields to a 20-point interchange',
      () {
        final e = scenario([
          (id: 'a', rating: 2050, colors: 'WBW', points: 6),
          (id: 'b', rating: 1870, colors: 'BWB', points: 6),
          (id: 'c', rating: 1850, colors: 'WBW', points: 6),
          (id: 'd', rating: 1750, colors: 'BWB', points: 6),
        ]);
        final r = proposeRound(e, e.sections.single, ids('x'));
        expect(games(r), [('b', 'a'), ('d', 'c')]);
        expect(r.explanations.join('\n'), contains('interchanged'));
      },
    );

    test('29E7 example 1: pairings stand when no switch reduces conflicts', () {
      final e = scenario([
        (id: 'a', rating: 2300, colors: 'BWB', points: 6),
        (id: 'b', rating: 2220, colors: 'BWB', points: 6),
        (id: 'c', rating: 2180, colors: 'BBW', points: 6),
        (id: 'd', rating: 2050, colors: 'BWB', points: 6),
        (id: 'e', rating: 2040, colors: 'BWB', points: 6),
        (id: 'f', rating: 1990, colors: 'WBW', points: 6),
        (id: 'g', rating: 1980, colors: 'WBW', points: 6),
        (id: 'h', rating: 1950, colors: 'WBW', points: 6),
      ]);
      final r = proposeRound(e, e.sections.single, ids('x'));
      final pairs = games(r).map((g) => {g.$1, g.$2}).toList();
      expect(pairs, [
        {'a', 'e'},
        {'b', 'f'},
        {'c', 'g'},
        {'d', 'h'},
      ]);
      expect(games(r).skip(1), [('b', 'f'), ('c', 'g'), ('d', 'h')]);
    });

    test('29E7 example 2: the cheaper transposition (34 points) is chosen', () {
      final e = scenario([
        (id: 'a', rating: 2320, colors: 'WBWB', points: 8),
        (id: 'b', rating: 2278, colors: 'BWBW', points: 8),
        (id: 'c', rating: 2212, colors: 'BWBW', points: 8),
        (id: 'd', rating: 2199, colors: 'WBWB', points: 8),
        (id: 'e', rating: 2178, colors: 'WBWB', points: 8),
        (id: 'f', rating: 1980, colors: 'WBWB', points: 8),
        (id: 'g', rating: 1951, colors: 'WBWB', points: 8),
        (id: 'h', rating: 1910, colors: 'BWBW', points: 8),
        (id: 'i', rating: 1896, colors: 'BWBW', points: 8),
        (id: 'j', rating: 1800, colors: 'WBWB', points: 8),
      ]);
      final r = proposeRound(e, e.sections.single, ids('x'));
      expect(games(r), [
        ('a', 'f'),
        ('g', 'b'),
        ('j', 'c'),
        ('d', 'i'),
        ('e', 'h'),
      ]);
    });

    test(
      '29E7 example 4: transposition first, then an interchange of 20 points',
      () {
        final e = scenario([
          (id: 'a', rating: 2210, colors: 'B', points: 2),
          (id: 'b', rating: 2200, colors: 'B', points: 2),
          (id: 'c', rating: 2150, colors: 'W', points: 2),
          (id: 'd', rating: 2120, colors: 'B', points: 2),
          (id: 'e', rating: 2080, colors: 'B', points: 2),
          (id: 'f', rating: 1920, colors: 'W', points: 2),
          (id: 'g', rating: 1900, colors: 'B', points: 2),
          (id: 'h', rating: 1830, colors: 'B', points: 2),
          (id: 'i', rating: 1820, colors: 'W', points: 2),
          (id: 'j', rating: 1790, colors: 'B', points: 2),
          (id: 'k', rating: 1500, colors: 'B', points: 2),
          (id: 'l', rating: 1350, colors: 'x', points: 2),
        ]);
        // The 1350 had a full-point bye, not a half-point one.
        final s = e.sections.single;
        final fixed = e.copy(
          sections: [
            s.copy(
              rounds: [
                s.rounds.single.copy(
                  byes: [const ByeAward('l', 2, 'Bye', allocated: true)],
                ),
              ],
            ),
          ],
        );
        final r = proposeRound(fixed, fixed.sections.single, ids('x'));
        expect(games(r), [
          ('a', 'f'),
          ('b', 'i'),
          ('h', 'c'),
          ('d', 'j'),
          ('e', 'k'),
          ('g', 'l'),
        ]);
      },
    );

    test('29E7 example 5: a different odd player when it costs less', () {
      final e = scenario([
        (id: 'a', rating: 2100, colors: 'BWB', points: 6),
        (id: 'b', rating: 2080, colors: 'BWB', points: 6),
        (id: 'c', rating: 1990, colors: 'WBW', points: 6),
        (id: 'd', rating: 2050, colors: 'WBW', points: 5),
        (id: 'e', rating: 1980, colors: 'BWB', points: 5),
        (id: 'f', rating: 1800, colors: 'BWB', points: 5),
      ]);
      final r = proposeRound(e, e.sections.single, ids('x'));
      expect(games(r), [('a', 'c'), ('b', 'd'), ('e', 'f')]);
      expect(r.explanations.join('\n'), contains('odd player'));
    });
  });

  group('29E4 color priority', () {
    (String, String) decide(
      String ca,
      String cb, {
      Set<String> variations = const {},
    }) {
      final e = scenario([
        (id: 'a', rating: 1600, colors: ca, points: 2),
        (id: 'b', rating: 1500, colors: cb, points: 2),
      ], variations: variations);
      return games(proposeRound(e, e.sections.single, ids('x'))).single;
    }

    test('rule 1: unequal colors beat equal colors', () {
      expect(decide('WBW', 'BxW'), ('b', 'a')); // WBW gets black.
    });
    test('rule 2: the greater imbalance takes its due color', () {
      expect(decide('WWBW', 'xWBW'), ('b', 'a'));
    });
    test('rule 3: opposite to the previous round', () {
      expect(decide('WWB', 'WBW'), ('a', 'b')); // WWB gets white.
    });
    test('rule 4: the latest round in which colors differed', () {
      expect(decide('WBWB', 'BWWB'), ('a', 'b'));
      expect(decide('BWxBW', 'BWBxW'), ('a', 'b'));
    });
    test('rule 5: the higher-ranked player takes the due color', () {
      expect(decide('WB', 'WB'), ('a', 'b'));
      expect(decide('BW', 'BW'), ('b', 'a'));
    });
    test('29E4a: in minus groups the lower-ranked player has priority', () {
      final e = scenario(
        [
          (id: 'a', rating: 1600, colors: 'WB', points: 0),
          (id: 'b', rating: 1500, colors: 'WB', points: 0),
        ],
        variations: {'29E4a'},
      );
      expect(games(proposeRound(e, e.sections.single, ids('x'))).single, (
        'b',
        'a',
      ));
    });
  });

  group('28J and 29E2 first round', () {
    Event firstRound(int n, {int unrated = 0, String toss = ''}) => Event(
      id: 'r1',
      name: 'Round one',
      date: '2026-10-09',
      colorToss: toss,
      players: [
        for (var i = 0; i < n; i++)
          Player(
            id: 'p$i',
            name: 'Player $i',
            rating: i >= n - unrated ? 0 : 2000 - i * 17,
            memberId: i >= n - unrated ? '' : '1234567$i',
          ),
      ],
      sections: [
        Section(
          id: 's',
          name: 'Open',
          players: [for (var i = 0; i < n; i++) 'p$i'],
          plannedRounds: 4,
        ),
      ],
    );

    test(
      'upper half plays lower half with colors alternating after the toss',
      () {
        final e = firstRound(8, toss: 'higherWhite');
        final r = proposeRound(e, e.sections.single, ids('x'));
        expect(games(r), [
          ('p0', 'p4'),
          ('p5', 'p1'),
          ('p2', 'p6'),
          ('p7', 'p3'),
        ]);
        final flipped = firstRound(8, toss: 'higherBlack');
        expect(
          games(proposeRound(flipped, flipped.sections.single, ids('x'))),
          [('p4', 'p0'), ('p1', 'p5'), ('p6', 'p2'), ('p3', 'p7')],
        );
      },
    );

    test('the default toss is fixed by the event, so sections agree', () {
      final e = firstRound(8);
      expect(effectiveColorToss(e), isIn(['higherWhite', 'higherBlack']));
      expect(effectiveColorToss(e), effectiveColorToss(e.copy(name: 'other')));
    });

    test('28L2: the bye never goes to an unrated player', () {
      final e = firstRound(7, unrated: 1);
      final r = proposeRound(e, e.sections.single, ids('x'));
      final bye = r.byes.singleWhere((b) => b.allocated);
      expect(bye.player, 'p5');
      expect(bye.reason, contains('28L2'));
    });

    test('28R1: accelerated pairings pair quarters in round 1', () {
      final e = firstRound(8);
      final accelerated = e.copy(
        sections: [e.sections.single.copy(accelerated: 'addedScore')],
      );
      final r = proposeRound(
        accelerated,
        accelerated.sections.single,
        ids('x'),
      );
      final pairs = games(r).map((g) => {g.$1, g.$2}).toList();
      expect(pairs, [
        {'p0', 'p2'},
        {'p1', 'p3'},
        {'p4', 'p6'},
        {'p5', 'p7'},
      ]);
      expect(r.explanations.join('\n'), contains('28R1'));
    });
  });

  group('29C1 and 29D score groups', () {
    test('S1: within a score group the upper half plays the lower half', () {
      // Eight players on 1 point whose colors already fit the natural
      // pairing: 1v5, 2v6, 3v7, 4v8 by rating.
      final e = scenario([
        (id: 'a', rating: 2200, colors: 'W', points: 2),
        (id: 'b', rating: 2180, colors: 'W', points: 2),
        (id: 'c', rating: 2160, colors: 'W', points: 2),
        (id: 'd', rating: 2140, colors: 'W', points: 2),
        (id: 'e', rating: 2120, colors: 'B', points: 2),
        (id: 'f', rating: 2100, colors: 'B', points: 2),
        (id: 'g', rating: 2080, colors: 'B', points: 2),
        (id: 'h', rating: 2060, colors: 'B', points: 2),
      ]);
      final r = proposeRound(e, e.sections.single, ids('x'));
      expect(games(r), [('e', 'a'), ('f', 'b'), ('g', 'c'), ('h', 'd')]);
    });

    test(
      '29D1a: the lowest-rated rated player drops and meets the highest below',
      () {
        final e = scenario([
          (id: 'a', rating: 2200, colors: 'W', points: 2),
          (id: 'b', rating: 2100, colors: 'B', points: 2),
          (id: 'c', rating: 2000, colors: 'W', points: 2),
          (id: 'd', rating: 1900, colors: 'B', points: 0),
          (id: 'e', rating: 1800, colors: 'W', points: 0),
          (id: 'f', rating: 1700, colors: 'B', points: 0),
        ]);
        final r = proposeRound(e, e.sections.single, ids('x'));
        expect(games(r).first, ('b', 'a'));
        expect(games(r)[1], ('d', 'c'));
        expect(r.explanations.join('\n'), contains('29D1a'));
      },
    );

    test(
      '29D2 example 2: two odd players who met take the two highest below',
      () {
        final e = scenario(
          [
            (id: 'a', rating: 2200, colors: 'W', points: 2),
            (id: 'b', rating: 2100, colors: 'B', points: 2),
            (id: 'c', rating: 2000, colors: 'B', points: 0),
            (id: 'd', rating: 1900, colors: 'W', points: 0),
            (id: 'e', rating: 1800, colors: 'B', points: 0),
            (id: 'f', rating: 1700, colors: 'W', points: 0),
          ],
          met: [('a', 'b')],
        );
        final r = proposeRound(e, e.sections.single, ids('x'));
        final pairs = games(r).map((g) => {g.$1, g.$2}).toList();
        expect(pairs.take(2), [
          {'a', 'c'},
          {'b', 'd'},
        ]);
      },
    );

    test(
      '27A1: a repeat is allowed only when unavoidable, and is explained',
      () {
        final e = scenario(
          [
            (id: 'a', rating: 2200, colors: 'WBW', points: 6),
            (id: 'b', rating: 2100, colors: 'BWB', points: 4),
            (id: 'c', rating: 2000, colors: 'WBW', points: 2),
            (id: 'd', rating: 1900, colors: 'BWB', points: 0),
          ],
          met: [('a', 'b'), ('c', 'd')],
        );
        // Make every pair a prior meeting.
        final s = e.sections.single;
        final all = e.copy(
          sections: [
            s.copy(
              rounds: [
                s.rounds[0].copy(
                  games: [
                    const Game(
                      id: 'm1',
                      white: 'a',
                      black: 'b',
                      board: 1,
                      outcome: Outcome.whiteWin,
                    ),
                    const Game(
                      id: 'm2',
                      white: 'c',
                      black: 'd',
                      board: 2,
                      outcome: Outcome.whiteWin,
                    ),
                  ],
                ),
                s.rounds[1].copy(
                  games: [
                    const Game(
                      id: 'm3',
                      white: 'c',
                      black: 'a',
                      board: 1,
                      outcome: Outcome.blackWin,
                    ),
                    const Game(
                      id: 'm4',
                      white: 'd',
                      black: 'b',
                      board: 2,
                      outcome: Outcome.blackWin,
                    ),
                  ],
                ),
                s.rounds[2].copy(
                  games: [
                    const Game(
                      id: 'm5',
                      white: 'a',
                      black: 'd',
                      board: 1,
                      outcome: Outcome.whiteWin,
                    ),
                    const Game(
                      id: 'm6',
                      white: 'b',
                      black: 'c',
                      board: 2,
                      outcome: Outcome.whiteWin,
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        final r = proposeRound(all, all.sections.single, ids('x'));
        expect(r.games.length, 2);
        expect(r.explanations.first, contains('27A1'));
      },
    );
  });

  group('28L bye eligibility', () {
    Event lowGroup(
      Map<String, Player Function(Player)> adjust, {
      List<Round> Function(List<Round>)? rounds,
    }) {
      final e = scenario([
        (id: 'a', rating: 2200, colors: 'W', points: 2),
        (id: 'b', rating: 2100, colors: 'B', points: 2),
        (id: 'c', rating: 2000, colors: 'W', points: 2),
        (id: 'd', rating: 1900, colors: 'B', points: 0),
        (id: 'e', rating: 1800, colors: 'W', points: 0),
        (id: 'f', rating: 1700, colors: 'B', points: 0),
        (id: 'g', rating: 1600, colors: 'W', points: 0),
      ], adjust: adjust);
      if (rounds == null) return e;
      final s = e.sections.single;
      return e.copy(sections: [s.copy(rounds: rounds(s.rounds))]);
    }

    String byeOf(Event e) => proposeRound(
      e,
      e.sections.single,
      ids('x'),
    ).byes.singleWhere((b) => b.allocated).player;

    test('the lowest-rated player in the lowest group', () {
      expect(byeOf(lowGroup({})), 'g');
    });
    test('28L3: not a player who already had a bye', () {
      final e = lowGroup(
        {},
        rounds: (rs) => [
          rs.single.copy(
            games: rs.single.games
                .where((g) => g.white != 'g' && g.black != 'g')
                .toList(),
            byes: [const ByeAward('g', 2, 'Bye', allocated: true)],
          ),
        ],
      );
      expect(byeOf(e), 'f');
    });
    test('28L3: not a player who won by forfeit', () {
      final e = lowGroup(
        {},
        rounds: (rs) => [
          rs.single.copy(
            games: [
              for (final g in rs.single.games)
                g.white == 'g' ? g.copy(outcome: Outcome.whiteForfeit) : g,
            ],
          ),
        ],
      );
      expect(byeOf(e), 'f');
    });
    test('28L4: not a player holding a half-point bye, even a future one', () {
      expect(
        byeOf(
          lowGroup({
            'g': (p) => p.copy(byes: {4: 1}),
          }),
        ),
        'f',
      );
    });
    test(
      '28L5: equal ratings above a NEW player pass the bye to the lowest-ranked',
      () {
        // A four-round event whose lowest group is a lone NEW player: the bye
        // moves up, and among the three 2000s the last pairing number takes it.
        final e = scenario([
          (id: 'a', rating: 2200, colors: 'W', points: 2),
          (id: 'b', rating: 2000, colors: 'B', points: 2),
          (id: 'c', rating: 2000, colors: 'W', points: 2),
          (id: 'd', rating: 2000, colors: 'B', points: 2),
          (id: 'n', rating: 0, colors: 'W', points: 0),
        ], plannedRounds: 4);
        final bye = proposeRound(
          e,
          e.sections.single,
          ids('x'),
        ).byes.singleWhere((b) => b.allocated);
        expect(bye.player, 'd');
        expect(bye.reason, contains('28L5'));
      },
    );
    test('28L2: an unrated player only when no rated player is eligible', () {
      expect(
        byeOf(lowGroup({'g': (p) => p.copy(rating: 0, memberId: '12345678')})),
        'f',
      );
    });
  });

  group('28M1, 28N1, 28S, 36 and fixed boards', () {
    test('a house player is paired only when the field is odd', () {
      final odd = scenario(
        [
          (id: 'a', rating: 2200, colors: 'W', points: 2),
          (id: 'b', rating: 2100, colors: 'B', points: 2),
          (id: 'c', rating: 2000, colors: 'W', points: 0),
          (id: 'h', rating: 1500, colors: 'B', points: 0),
        ],
        adjust: {'h': (p) => p.copy(house: true)},
      );
      final r = proposeRound(odd, odd.sections.single, ids('x'));
      expect(r.games.length, 2);
      expect(r.byes.where((b) => b.allocated), isEmpty);
      final even = odd.copy(
        players: [
          for (final p in odd.players)
            p.id == 'c' ? p.copy(withdrawn: true) : p,
        ],
      );
      final r2 = proposeRound(even, even.sections.single, ids('x'));
      expect(r2.games.length, 1);
      expect(r2.byes.any((b) => b.player == 'h' && b.points == 0), true);
    });

    test('28N1: team-mates are kept apart below plus-two', () {
      final e = scenario(
        [
          (id: 'a', rating: 2200, colors: 'W', points: 2),
          (id: 'b', rating: 2100, colors: 'B', points: 2),
          (id: 'c', rating: 2000, colors: 'W', points: 2),
          (id: 'd', rating: 1900, colors: 'B', points: 2),
        ],
        adjust: {
          'a': (p) => p.copy(team: 'Lions'),
          'c': (p) => p.copy(team: 'Lions'),
        },
      );
      final s = e.sections.single;
      final teams = e.copy(sections: [s.copy(avoidTeammates: true)]);
      final r = proposeRound(teams, teams.sections.single, ids('x'));
      expect(games(r).map((g) => {g.$1, g.$2}), isNot(contains({'a', 'c'})));
    });

    test('28S1: a re-entry may not meet an opponent of its earlier entry', () {
      final e = scenario(
        [
          (id: 'a', rating: 2200, colors: 'W', points: 2),
          (id: 'b', rating: 2100, colors: 'B', points: 0),
          (id: 'c', rating: 2000, colors: 'W', points: 0),
          (id: 'd', rating: 1900, colors: 'B', points: 0),
        ],
        met: [('a', 'b')],
      );
      // 'd' re-enters for 'a': they are the same person.
      final re = e.copy(
        players: [
          for (final p in e.players)
            p.id == 'd'
                ? p.copy(reentryOf: 'a')
                : p.id == 'a'
                ? p.copy(withdrawn: true)
                : p,
        ],
      );
      final r = proposeRound(re, re.sections.single, ids('x'));
      expect(games(r).map((g) => {g.$1, g.$2}), isNot(contains({'b', 'd'})));
    });

    test('36: two computers are never paired', () {
      final e = scenario(
        [
          (id: 'a', rating: 2200, colors: 'W', points: 2),
          (id: 'b', rating: 2100, colors: 'B', points: 2),
          (id: 'c', rating: 2000, colors: 'W', points: 0),
          (id: 'd', rating: 1900, colors: 'B', points: 0),
        ],
        adjust: {
          'a': (p) => p.copy(computer: true),
          'b': (p) => p.copy(computer: true),
        },
      );
      final r = proposeRound(e, e.sections.single, ids('x'));
      expect(games(r).map((g) => {g.$1, g.$2}), isNot(contains({'a', 'b'})));
    });

    test('20M3: a fixed board is kept and the others fill around it', () {
      final e = scenario(
        [
          (id: 'a', rating: 2200, colors: 'W', points: 2),
          (id: 'b', rating: 2100, colors: 'B', points: 2),
          (id: 'c', rating: 2000, colors: 'W', points: 0),
          (id: 'd', rating: 1900, colors: 'B', points: 0),
        ],
        adjust: {'d': (p) => p.copy(fixedBoard: 1)},
      );
      final r = proposeRound(e, e.sections.single, ids('x'));
      final dGame = r.games.singleWhere(
        (g) => g.white == 'd' || g.black == 'd',
      );
      expect(dGame.board, 1);
      expect(r.games.map((g) => g.board).toSet(), {1, 2});
    });
  });
}
