import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/swiss.dart';
import 'package:meow_chess/domain/simulation.dart';
import 'package:meow_chess/domain/standings.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

SwissEntry entry(
  String id,
  int rating, {
  String colors = '',
  Set<String> avoid = const {},
  Set<String> opponents = const {},
  bool bye = true,
  bool halfBye = false,
  int score = 0,
  int lastFloat = 0,
}) => SwissEntry(
  id: id,
  name: id,
  rating: rating,
  score: score,
  colors: colors,
  avoid: avoid,
  opponents: opponents,
  byeEligible: bye,
  halfBye: halfBye,
  lastFloat: lastFloat,
);

Event eventWith(
  int count, {
  Scoring scoring = const Scoring(),
  Map<String, List<int>> acceleration = const {},
}) => Event(
  id: 'e',
  name: 'Test',
  date: '2024-01-01',
  players: [
    for (var i = 0; i < count; i++)
      Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 20),
  ],
  sections: [
    Section(
      id: 's',
      name: 'Open',
      plannedRounds: 5,
      scoring: scoring,
      acceleration: acceleration,
      players: [for (var i = 0; i < count; i++) 'p$i'],
    ),
  ],
);

void main() {
  test('equal score gaps prefer not repeating a float', () {
    final result = pairSwiss(
      SwissInput(
        round: 3,
        players: [
          entry('a', 2000, score: 2),
          entry('b', 1800, score: 0, lastFloat: 1),
          entry('c', 1780, score: 0),
          entry('d', 1760, score: 0),
        ],
      ),
    );
    expect({result.pairs.first.$1, result.pairs.first.$2}, {'a', 'c'});
  });

  test('double-game replay checks the second leg too', () {
    final e = eventWith(4);
    final section = e.sections.single.copy(doubleGames: true);
    var id = 0;
    final r = proposeRound(
      e.copy(sections: [section]),
      section,
      () => '${id++}',
    );
    expect(recheckPairing(r), isEmpty);
    expect(
      recheckPairing(
        r.copy(games: r.games.where((g) => g.leg == 1).toList()),
      ).join(),
      contains('Opponents or colors differ'),
    );
  });

  test(
    '28J first round pairs halves and alternates the recorded top-seed color',
    () {
      final e = eventWith(6);
      var n = 0;
      final round = proposeRound(e, e.sections.single, () => '${n++}');
      expect(round.games.map((g) => (g.white, g.black)), [
        ('p0', 'p3'),
        ('p4', 'p1'),
        ('p2', 'p5'),
      ]);
      final flipped = e.copy(
        sections: [e.sections.single.copy(firstColorWhite: false)],
      );
      final reverse = proposeRound(
        flipped,
        flipped.sections.single,
        () => '${n++}',
      );
      expect(reverse.games.map((g) => (g.white, g.black)), [
        ('p3', 'p0'),
        ('p1', 'p4'),
        ('p5', 'p2'),
      ]);
    },
  );

  test('29E5c uses the smaller rating switch to prevent third colors', () {
    final result = pairSwiss(
      SwissInput(
        round: 3,
        players: [
          entry('a', 2000, colors: 'WW'),
          entry('b', 1980, colors: 'BB'),
          entry('c', 1800, colors: 'WW'),
          entry('d', 1500, colors: 'BB'),
        ],
      ),
    );
    expect(result.pairs, [('d', 'a'), ('b', 'c')]);
    expect(result.warnings, isEmpty);
  });

  test('out-of-limit color swaps remain flagged for TD review', () {
    final result = pairSwiss(
      SwissInput(
        round: 3,
        players: [
          entry('a', 2400, colors: 'WW'),
          entry('b', 2000, colors: 'BB'),
          entry('c', 1600, colors: 'WW'),
          entry('d', 1200, colors: 'BB'),
        ],
      ),
    );
    expect(
      result.warnings.where((w) => w.contains('third consecutive')),
      hasLength(2),
    );
  });

  test('color improvement never overrides a do-not-pair request', () {
    final input = SwissInput(
      round: 3,
      players: [
        entry('a', 2000, colors: 'WW', avoid: {'d'}),
        entry('b', 1980, colors: 'BB'),
        entry('c', 1800, colors: 'WW'),
        entry('d', 1500, colors: 'BB'),
      ],
    );
    expect(
      pairSwiss(input).pairs.any((p) => {p.$1, p.$2}.containsAll(['a', 'd'])),
      false,
    );
  });

  test('29E4 latest differing round decides equal color claims', () {
    final result = pairSwiss(
      SwissInput(
        round: 5,
        players: [
          entry('a', 2000, colors: 'WBWB'),
          entry('b', 1900, colors: 'BWWB'),
        ],
      ),
    );
    expect(result.pairs, [('a', 'b')]);
  });

  test(
    '28L3 forfeit wins exclude an allocated bye and add no color history',
    () {
      var e = eventWith(3);
      e = e.copy(
        sections: [
          e.sections.single.copy(
            rounds: [
              Round(
                number: 1,
                games: [
                  const Game(
                    id: 'g',
                    white: 'p1',
                    black: 'p2',
                    board: 1,
                    outcome: Outcome.blackForfeit,
                  ),
                ],
                byes: [const ByeAward('p0', 2, 'Allocated', allocated: true)],
              ),
            ],
          ),
        ],
      );
      final input = swissInput(e, e.sections.single);
      expect(input.players.singleWhere((p) => p.id == 'p2').byeEligible, false);
      expect(input.players.singleWhere((p) => p.id == 'p2').colors, '-');
      expect(pairSwiss(input).bye, 'p1');
    },
  );

  test(
    '28L4 avoids half-bye commitments when a same-score alternative exists',
    () {
      final result = pairSwiss(
        SwissInput(
          round: 1,
          players: [
            entry('a', 2000),
            entry('b', 1800),
            entry('c', 1600, halfBye: true),
          ],
        ),
      );
      expect(result.bye, 'b');
    },
  );

  test('bye selection prefers rated players within the lowest score group', () {
    final result = pairSwiss(
      SwissInput(
        round: 1,
        players: [entry('a', 2000), entry('b', 1800), entry('c', 0)],
      ),
    );
    expect(result.bye, 'b');
  });

  test('search limits and impossible restrictions fail explicitly', () {
    final input = SwissInput(
      round: 1,
      players: [
        entry('a', 2000, opponents: {'b'}),
        entry('b', 1800),
      ],
    );
    expect(() => pairSwiss(input), throwsA(isA<TournamentException>()));
    expect(
      () => pairSwiss(
        SwissInput(round: 1, players: [entry('a', 2000), entry('b', 1800)]),
        nodeLimit: 0,
      ),
      throwsA(isA<TournamentException>()),
    );
  });

  test('replay reproduces saved inputs and detects manual color changes', () {
    final e = eventWith(4);
    var id = 0;
    final r = proposeRound(e, e.sections.single, () => '${id++}');
    expect(recheckPairing(Round.fromJson(r.toJson())), isEmpty);
    final g = r.games.first;
    final changed = r.copy(
      games: [
        g.copy(white: g.black, black: g.white),
        ...r.games.skip(1),
      ],
    );
    expect(
      recheckPairing(changed).join(),
      contains('Opponents or colors differ'),
    );
    final edited = e.copy(
      players: [for (final p in e.players) p.copy(rating: 1)],
      sections: [
        e.sections.single.copy(rounds: [r]),
      ],
    );
    expect(pairingChecklist(edited), contains('2000'));
    expect(pairingChecklist(edited), contains('matches saved proposal'));
  });

  test('replay detects altered bye values', () {
    final e = eventWith(5);
    var id = 0;
    final r = proposeRound(e, e.sections.single, () => '${id++}');
    expect(recheckPairing(r), isEmpty);
    expect(
      recheckPairing(
        r.copy(
          byes: [ByeAward(r.byes.single.player, 0, 'Changed', allocated: true)],
        ),
      ).join(),
      contains('Bye assignments differ'),
    );
  });

  test('old rounds explicitly lack replay evidence', () {
    expect(
      recheckPairing(Round(number: 1, games: [])).single,
      contains('No saved inputs'),
    );
  });

  test('acceleration changes pairing scores but never standings', () {
    final e = eventWith(
      4,
      acceleration: {
        'p0': [2, 2],
        'p1': [2, 2],
      },
    );
    final input = swissInput(e, e.sections.single);
    expect(input.players.map((p) => p.pairingScore), [2, 2, 0, 0]);
    expect(
      standings(e, e.sections.single).map((s) => s.points),
      everyElement(0),
    );
    expect(e.sections.single.accelerationFor('p0', 3), 0);
  });

  test('custom competition scoring preserves actual game outcomes', () {
    var e = eventWith(
      4,
      scoring: const Scoring(win: 6, draw: 2, loss: 0, bye: 2),
    );
    e = e.copy(
      sections: [
        e.sections.single.copy(
          rounds: [
            Round(
              number: 1,
              games: [
                const Game(
                  id: 'g1',
                  white: 'p0',
                  black: 'p1',
                  board: 1,
                  outcome: Outcome.whiteWin,
                ),
                const Game(
                  id: 'g2',
                  white: 'p2',
                  black: 'p3',
                  board: 2,
                  outcome: Outcome.draw,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    expect(standings(e, e.sections.single).map((r) => r.points), [6, 2, 2, 0]);
    expect(e.games.first.outcome.whiteScore, 2);
    expect(swissInput(e, e.sections.single).players.first.score, 6);
  });

  test('score-only standings share ranks despite different tiebreaks', () {
    var e = eventWith(4);
    e = e.copy(
      sections: [
        e.sections.single.copy(
          tiebreakOrder: TiebreakOrder.scoreOnly,
          rounds: [
            Round(
              number: 1,
              games: [
                const Game(
                  id: 'a',
                  white: 'p0',
                  black: 'p1',
                  board: 1,
                  outcome: Outcome.whiteWin,
                ),
                const Game(
                  id: 'b',
                  white: 'p2',
                  black: 'p3',
                  board: 2,
                  outcome: Outcome.whiteWin,
                ),
              ],
            ),
            Round(
              number: 2,
              games: [],
              byes: [
                const ByeAward('p0', 0, 'Out'),
                const ByeAward('p1', 1, 'Half'),
                const ByeAward('p2', 0, 'Out'),
                const ByeAward('p3', 0, 'Out'),
              ],
            ),
          ],
        ),
      ],
    );
    final rows = standings(e, e.sections.single);
    expect(rows[0].points, rows[1].points);
    expect(rows[0].buchholz, isNot(rows[1].buchholz));
    expect(rows[0].rank, rows[1].rank);
  });

  test(
    'new settings persist through storage/history; posted scoring is locked',
    () async {
      final c = TournamentController(SqliteEventRepository(':memory:'));
      addTearDown(c.dispose);
      final e = eventWith(
        4,
        scoring: const Scoring(win: 6, draw: 2),
        acceleration: {
          'p0': [2],
        },
      );
      c.change('Setup', e);
      c.post(await c.propose());
      expect(c.repository.load()!.sections.single.scoring.win, 6);
      expect(
        c.repository.load()!.sections.single.rounds.single.pairingInput,
        isNotEmpty,
      );
      expect(
        () => c.change(
          'Bad edit',
          c.event!.copy(
            sections: [c.event!.sections.single.copy(scoring: const Scoring())],
          ),
        ),
        throwsA(isA<TournamentException>()),
      );
      c.undo();
      expect(c.event!.sections.single.rounds, isEmpty);
      c.redo();
      expect(recheckPairing(c.event!.sections.single.rounds.single), isEmpty);
    },
  );

  test('legacy records keep standard policies and invalid settings fail', () {
    final e = eventWith(4);
    final j = e.sections.single.toJson();
    for (final key in [
      'scoring',
      'tiebreakOrder',
      'firstColorWhite',
      'acceleration',
    ]) {
      j.remove(key);
    }
    expect(Section.fromJson(j).scoring.win, 2);
    expect(
      () => validateEvent(
        e.copy(
          sections: [e.sections.single.copy(scoring: const Scoring(win: 0))],
        ),
      ),
      throwsA(isA<TournamentException>()),
    );
    expect(
      () => validateEvent(
        e.copy(
          sections: [
            e.sections.single.copy(
              acceleration: {
                'unknown': [2],
              },
            ),
          ],
        ),
      ),
      throwsA(isA<TournamentException>()),
    );
    expect(parsePoints('1.5'), 3);
    expect(() => parsePoints('0.25'), throwsA(isA<TournamentException>()));
  });

  test('seeded simulation reproduces events and always remains practice', () {
    const config = SimulationConfig(
      players: 32,
      rounds: 5,
      seed: 123,
      withdrawPercent: 2,
    );
    final a = simulateTournament(config), b = simulateTournament(config);
    expect(a.event.encode(), b.event.encode());
    expect(a.event.practice, true);
    validateEvent(a.event);
    expect(a.event.players.every((p) => p.memberId.isEmpty), true);
    expect(a.event.notes, contains('seed 123'));
  });

  test(
    'simulation records an impossible round instead of fabricating pairings',
    () {
      final result = simulateTournament(
        const SimulationConfig(players: 4, rounds: 12, forfeitPercent: 0),
      );
      expect(result.stopReason, isNotNull);
      expect(result.event.sections.single.rounds.length, 3);
      expect(result.event.practice, true);
      expect(
        () => simulateTournament(const SimulationConfig(players: 1000)),
        throwsA(isA<TournamentException>()),
      );
    },
  );
}
