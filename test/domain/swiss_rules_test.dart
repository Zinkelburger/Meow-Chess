import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/standings.dart';

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

/// A board's two players, in either order.
String pair(String a, String b) => a.compareTo(b) < 0 ? '$a-$b' : '$b-$a';

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

  group('28R2 / 28R3 accelerated pairings', () {
    // Sixteen players rated 2400 down to 900, numbered 1–16 in rating order.
    Event field(int n, String method) => Event(
      id: 'acc',
      name: 'Accelerated',
      date: '2026-10-09',
      players: [
        for (var i = 1; i <= n; i++)
          Player(
            id: '$i',
            name: 'P$i',
            rating: 2500 - 100 * i,
            memberId: '1000000$i',
          ),
      ],
      sections: [
        Section(
          id: 's',
          name: 'Open',
          players: [for (var i = 1; i <= n; i++) '$i'],
          plannedRounds: 5,
          accelerated: method,
        ),
      ],
    );
    Set<String> pairs(Round r) => {
      for (final g in r.games) pair(g.white, g.black),
    };

    test('28R2 round 1: A1 plays B1 and C1 plays D1', () {
      final e = field(16, 'adjustedRating');
      final r = proposeRound(e, e.sections.single, ids('x'));
      expect(pairs(r), {
        pair('1', '5'),
        pair('2', '6'),
        pair('3', '7'),
        pair('4', '8'), // A1 v B1
        pair('9', '13'),
        pair('10', '14'),
        pair('11', '15'),
        pair('12', '16'), // C1 v D1
      });
      final text = r.explanations.join('\n');
      expect(text, contains('28R2'));
      expect(text, contains('A1 (4): P1 to P4'));
      expect(text, contains('D1 (4): P13 to P16'));
    });

    test('28R2 round 2: A2, B2 against C2, and D2, with ±100 for draws', () {
      final e = field(16, 'adjustedRating');
      final r1 = proposeRound(e, e.sections.single, ids('g'));
      // Round 1 results: 1, 2 and 8 win in A1 v B1 (8 upsets 4), 3 draws
      // with 7; 9, 12 and 15 win in C1 v D1 (15 upsets 11), 10 draws 14.
      const winners = {'1', '2', '8', '9', '12', '15'};
      const draws = {'3', '7', '10', '14'};
      final played = r1.copy(
        games: [
          for (final g in r1.games)
            g.copy(
              outcome: draws.contains(g.white)
                  ? Outcome.draw
                  : winners.contains(g.white)
                  ? Outcome.whiteWin
                  : Outcome.blackWin,
            ),
        ],
      );
      final after = e.copy(
        sections: [
          e.sections.single.copy(rounds: [played]),
        ],
      );
      final r = proposeRound(after, after.sections.single, ids('x'));
      final text = r.explanations.join('\n');
      // A2 = winners of A1 v B1 (1, 2, 8): odd, so 8 drops to C2. B2 =
      // non-winners 3, 4, 5, 6, 7 with the drawers +100; C2 = non-losers
      // 9, 10, 12, 14, 15 and 8 with the drawers −100. B2 has five and C2
      // six, so the highest of D2 (11, 13, 16) rises to B2.
      expect(text, contains('A2 (2): P1 (2400), P2 (2300)'));
      expect(
        text,
        contains(
          'B2 (6): P3 (2300), P4 (2100), P5 (2000), P6 (1900), P7 (1900), P11 (1400)',
        ),
      );
      expect(
        text,
        contains(
          'C2 (6): P8 (1700), P9 (1600), P10 (1400), P12 (1300), P14 (1000), P15 (1000)',
        ),
      );
      expect(text, contains('D2 (2): P13 (1200), P16 (900)'));
      expect(text, contains('P8 drops from A2 to C2'));
      expect(text, contains('P11 rises from D2 to B2'));
      expect(text, contains('P3 2200→2300'));
      expect(text, contains('P10 1500→1400'));
      // A2 pairs within itself, B2 plays C2 board by board, D2 within
      // itself; 11 and 15 met in round 1, so they are kept apart (27A1).
      const b2 = {'3', '4', '5', '6', '7', '11'};
      const c2 = {'8', '9', '10', '12', '14', '15'};
      final got = pairs(r);
      expect(got, contains(pair('1', '2')));
      expect(got, contains(pair('13', '16')));
      expect(got, isNot(contains(pair('11', '15'))));
      for (final g in r.games) {
        final p = [g.white, g.black];
        if (p.contains('1') || p.contains('13')) continue;
        expect(p.where(b2.contains), hasLength(1), reason: '$p');
        expect(p.where(c2.contains), hasLength(1), reason: '$p');
      }
      // Third and later rounds pair by the basic system.
      expect(
        r.explanations.where((x) => x.contains('28R2')).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('28R3 round 1: sixths pair 1 v 2, 3 v 4 and 5 v 6', () {
      final e = field(12, 'sixths');
      final r = proposeRound(e, e.sections.single, ids('x'));
      expect(pairs(r), {
        pair('1', '3'), pair('2', '4'), pair('5', '7'), pair('6', '8'), //
        pair('9', '11'), pair('10', '12'),
      });
      expect(r.explanations.join('\n'), contains('28R3'));
    });
  });

  group('29I and 29J class pairings, 28L2a', () {
    // Four rounds played; the fifth is the last. Two experts lead on 4
    // points, out of reach of the class players on 2 or less.
    Event classes({Set<String> variations = const {}, Json prizes = const {}}) {
      final e = scenario(
        [
          (id: 'x1', rating: 2150, colors: 'WBWB', points: 8),
          (id: 'x2', rating: 2100, colors: 'BWBW', points: 8),
          (id: 'a1', rating: 1950, colors: 'WBWB', points: 4),
          (id: 'b1', rating: 1750, colors: 'BWBW', points: 4),
          (id: 'a2', rating: 1900, colors: 'WBWB', points: 2),
          (id: 'b2', rating: 1650, colors: 'BWBW', points: 2),
        ],
        plannedRounds: 5,
        variations: variations,
      );
      return e.copy(sections: [e.sections.single.copy(prizes: prizes)]);
    }

    Json classPrizes({int places = 2}) => {
      'list': [
        for (var i = 1; i <= places; i++)
          {
            'id': 'p$i',
            'kind': 'place',
            'place': i,
            'cents': 50000 - i * 10000,
          },
        {'id': 'ca', 'kind': 'class', 'min': 1800, 'max': 1999, 'cents': 10000},
        {'id': 'cb', 'kind': 'class', 'min': 1600, 'max': 1799, 'cents': 10000},
      ],
    };
    Set<String> pairs(Round r) => {
      for (final g in r.games) pair(g.white, g.black),
    };

    test('without 29I the last round pairs by score groups', () {
      final e = classes(prizes: classPrizes());
      final r = proposeRound(e, e.sections.single, ids('x'));
      expect(pairs(r), {pair('x1', 'x2'), pair('a1', 'b1'), pair('a2', 'b2')});
    });

    test('29I1: in the last round each class pairs as its own Swiss', () {
      final e = classes(variations: {'29I'}, prizes: classPrizes());
      final r = proposeRound(e, e.sections.single, ids('x'));
      expect(pairs(r), {pair('x1', 'x2'), pair('a1', 'a2'), pair('b1', 'b2')});
      expect(
        r.explanations.join('\n'),
        contains('1800–1999: the class paired'),
      );
    });

    test('29I1: standard 200-point classes when no class prizes', () {
      final e = classes(variations: {'29I'});
      final r = proposeRound(e, e.sections.single, ids('x'));
      expect(pairs(r), contains(pair('a1', 'a2')));
      expect(r.explanations.join('\n'), contains('Class A'));
    });

    test('29I: not for a class whose player can still win a larger prize', () {
      // Three place prizes above the class prize: a1 or b1, winning while
      // the others lose, could share third place.
      final e = classes(variations: {'29I'}, prizes: classPrizes(places: 3));
      final r = proposeRound(e, e.sections.single, ids('x'));
      expect(pairs(r), contains(pair('a1', 'b1')));
      expect(r.explanations.join('\n'), contains('paired normally'));
    });

    test('29I2: only the class-prize contenders pair together', () {
      final e = classes(variations: {'29I2'}, prizes: classPrizes());
      final r = proposeRound(e, e.sections.single, ids('x'));
      expect(pairs(r), contains(pair('a1', 'a2')));
      expect(
        r.explanations.join('\n'),
        contains('class-prize contenders paired among themselves (29I2)'),
      );
      // Not in the last round: score groups.
      final early = e.copy(
        sections: [e.sections.single.copy(plannedRounds: 6)],
      );
      final r2 = proposeRound(early, early.sections.single, ids('x'));
      expect(pairs(r2), contains(pair('a1', 'b1')));
    });

    test('29J: unrateds on plus scores in one group play each other', () {
      Event plus(Set<String> variations) => scenario([
        (id: 'r1', rating: 1500, colors: 'WB', points: 4),
        (id: 'r2', rating: 1400, colors: 'BW', points: 4),
        (id: 'u1', rating: 0, colors: 'WB', points: 4),
        (id: 'u2', rating: 0, colors: 'BW', points: 4),
      ], variations: variations);
      final normal = plus({});
      expect(
        pairs(proposeRound(normal, normal.sections.single, ids('x'))),
        isNot(contains(pair('u1', 'u2'))),
      );
      final e = plus({'29J'});
      final r = proposeRound(e, e.sections.single, ids('x'));
      expect(pairs(r), {pair('r1', 'r2'), pair('u1', 'u2')});
      expect(r.explanations.join('\n'), contains('29J'));
    });

    test('28L2a: the bye goes higher when it improves the colors', () {
      // c1 and c2 have both had white twice: paired together, one takes
      // white a third time. With the bye to c2 (50 points higher than c3),
      // c1 meets c3, due white, and nobody's colors suffer.
      Event low(Set<String> variations) => scenario([
        (id: 'a', rating: 2000, colors: 'WB', points: 4),
        (id: 'b', rating: 1900, colors: 'BW', points: 4),
        (id: 'c1', rating: 1500, colors: 'WW', points: 0),
        (id: 'c2', rating: 1450, colors: 'WW', points: 0),
        (id: 'c3', rating: 1400, colors: 'BB', points: 0),
      ], variations: variations);
      final normal = low({});
      final natural = proposeRound(normal, normal.sections.single, ids('x'));
      expect(natural.byes.singleWhere((b) => b.allocated).player, 'c3');
      final e = low({'28L2a'});
      final r = proposeRound(e, e.sections.single, ids('x'));
      final bye = r.byes.singleWhere((b) => b.allocated);
      expect(bye.player, 'c2');
      expect(bye.reason, contains('28L2a'));
      expect(games(r), contains(('c3', 'c1')));
    });
  });

  group('28S5 re-entry scores and 29G3 selective re-pairing', () {
    // Round 1: P1 beats P2, X (the earlier entry) beats P3, P4 and P5
    // draw. X then withdraws and re-enters as XR with a half-point bye
    // replacing the round it missed (28S4).
    Event reentry({
      Outcome x = Outcome.blackWin,
      Set<String> variations = const {},
    }) {
      final players = [
        for (var i = 1; i <= 5; i++)
          Player(id: 'p$i', name: 'P$i', rating: 2100 - 100 * i),
        Player(id: 'x', name: 'X', rating: 1500, withdrawn: true),
        Player(id: 'xr', name: 'XR', rating: 1500, reentryOf: 'x'),
      ];
      return Event(
        id: 're',
        name: 'Re-entry',
        date: '2026-10-09',
        players: players,
        sections: [
          Section(
            id: 's',
            name: 'Open',
            players: [for (final p in players) p.id],
            plannedRounds: 4,
            variations: variations,
            rounds: [
              Round(
                number: 1,
                games: [
                  Game(
                    id: 'g1',
                    white: 'p1',
                    black: 'p2',
                    board: 1,
                    outcome: Outcome.whiteWin,
                  ),
                  Game(id: 'g2', white: 'p3', black: 'x', board: 2, outcome: x),
                  Game(
                    id: 'g3',
                    white: 'p4',
                    black: 'p5',
                    board: 3,
                    outcome: Outcome.draw,
                  ),
                ],
                byes: [const ByeAward('xr', 1, 'Re-entry half-point bye')],
              ),
            ],
          ),
        ],
      );
    }

    int points(Event e, String id, {bool forPrizes = false}) => standings(
      e,
      e.sections.single,
      forPrizes: forPrizes,
    ).firstWhere((r) => r.player.id == id).points;

    test('28S5: the re-entry carries the better score, with its colors', () {
      final e = reentry();
      expect(points(e, 'xr'), 2);
      expect(points(e, 'xr', forPrizes: true), 2);
      final r = proposeRound(e, e.sections.single, ids('r'));
      // XR plays in the 1-point group with P1, and X's black in round 1
      // makes XR due white.
      expect(games(r), contains(('xr', 'p1')));
      expect(r.explanations.join('\n'), contains('28S5'));
    });

    test('28S5: equal scores, or the organizer\'s option, keep the latest', () {
      final equal = reentry(x: Outcome.draw);
      expect(points(equal, 'xr'), 1);
      expect(
        proposeRound(
          equal,
          equal.sections.single,
          ids('r'),
        ).explanations.join('\n'),
        isNot(contains('28S5')),
      );
      final latest = reentry(variations: {'28S5latest'});
      expect(points(latest, 'xr'), 1);
      final r = proposeRound(latest, latest.sections.single, ids('r'));
      expect(games(r), isNot(contains(('xr', 'p1'))));
    });

    test('29G3: only the boards that have not started are re-paired', () {
      final e = Event(
        id: 'g3',
        name: 'Repair',
        date: '2026-10-09',
        players: [
          for (var i = 1; i <= 8; i++)
            Player(id: 'p$i', name: 'P$i', rating: 2100 - 100 * i),
        ],
        sections: [
          Section(
            id: 's',
            name: 'Open',
            players: [for (var i = 1; i <= 8; i++) 'p$i'],
            plannedRounds: 4,
          ),
        ],
      );
      final r1 = proposeRound(e, e.sections.single, ids('g'));
      final posted = e.copy(
        sections: [
          e.sections.single.copy(rounds: [r1]),
        ],
      );
      // Boards 1 and 2 have started; a player on board 3 withdraws.
      final keep = {r1.games[0].id, r1.games[1].id};
      final gone = r1.games[2].white;
      final withdrawn = posted.copy(
        players: [
          for (final p in posted.players)
            p.id == gone ? p.copy(withdrawn: true) : p,
        ],
      );
      final r = repairUnstartedRound(
        withdrawn,
        withdrawn.sections.single,
        keep,
        ids('n'),
      );
      expect(r.number, 1);
      expect(r.revision, r1.revision + 1);
      expect(r.games.take(2).map((g) => g.id), keep);
      expect(r.games.take(2).map((g) => g.board), [1, 2]);
      // Three are waiting: one game on a freed board and a full-point bye.
      expect(r.games, hasLength(3));
      expect(r.games.last.board, 3);
      expect(r.byes.singleWhere((b) => b.allocated).points, 2);
      expect(r.byes.any((b) => b.player == gone && b.points == 0), isTrue);
      final seated = {
        for (final g in r.games) ...[g.white, g.black],
        for (final b in r.byes) b.player,
      };
      expect(seated, {for (var i = 1; i <= 8; i++) 'p$i'});
      expect(r.explanations.first, contains('29G3'));
      // A board with a result cannot be re-paired.
      final scored = withdrawn.copy(
        sections: [
          withdrawn.sections.single.copy(
            rounds: [
              r1.copy(
                games: [
                  for (final g in r1.games)
                    g.id == r1.games[3].id ? g.copy(outcome: Outcome.draw) : g,
                ],
              ),
            ],
          ),
        ],
      );
      expect(
        () => repairUnstartedRound(
          scored,
          scored.sections.single,
          keep,
          ids('n'),
        ),
        throwsA(isA<TournamentException>()),
      );
    });
  });
}
