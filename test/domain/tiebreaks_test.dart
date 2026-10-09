import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/standings.dart';

/// Fixtures name players by a single letter; a game string is
/// `white-black=result` with results 1, 0, ½, `+` (white wins by forfeit),
/// `-` (black wins by forfeit) or `F` (double forfeit); a bye string is
/// `X:bye1`, `X:bye½` or `X:bye0`.
Event fixture(
  List<List<String>> rounds, {
  Format format = Format.swiss,
  int plannedRounds = 0,
  List<String> tiebreaks = const [],
  bool useTiebreaks = true,
  Map<String, int> ratings = const {},
}) {
  final game = RegExp(r'^([A-Z])-([A-Z])=(.+)$');
  final bye = RegExp(r'^([A-Z]):bye(1|½|0)$');
  final ids = <String>{};
  for (final round in rounds) {
    for (final entry in round) {
      final m = game.firstMatch(entry);
      if (m != null) ids.addAll([m[1]!, m[2]!]);
      final b = bye.firstMatch(entry);
      if (b != null) ids.add(b[1]!);
    }
  }
  final sorted = ids.toList()..sort();
  var board = 0;
  final section = Section(
    id: 's',
    name: 'Open',
    format: format,
    players: sorted,
    plannedRounds: plannedRounds == 0 ? rounds.length : plannedRounds,
    rounds: [
      for (final (i, round) in rounds.indexed)
        Round(
          number: i + 1,
          games: [
            for (final entry in round)
              if (game.firstMatch(entry) case final m?)
                Game(
                  id: 'g${++board}',
                  white: m[1]!,
                  black: m[2]!,
                  board: board,
                  outcome: switch (m[3]!) {
                    '1' => Outcome.whiteWin,
                    '0' => Outcome.blackWin,
                    '½' => Outcome.draw,
                    '+' => Outcome.whiteForfeit,
                    '-' => Outcome.blackForfeit,
                    'F' => Outcome.doubleForfeit,
                    _ => throw ArgumentError(entry),
                  },
                ),
          ],
          byes: [
            for (final entry in round)
              if (bye.firstMatch(entry) case final b?)
                ByeAward(b[1]!, switch (b[2]!) {
                  '1' => 2,
                  '½' => 1,
                  _ => 0,
                }, 'Requested'),
          ],
        ),
    ],
  );
  return Event(
    id: 'event-1',
    name: 'Tie-breaks',
    date: '2026-10-09',
    useTiebreaks: useTiebreaks,
    tiebreaks: tiebreaks,
    players: [
      for (final id in sorted)
        Player(id: id, name: id, rating: ratings[id] ?? 1500),
    ],
    sections: [section],
  );
}

Standing row(Event e, String id) =>
    standings(e, e.sections.single).firstWhere((r) => r.player.id == id);

/// The value of [m] for [id]: from the posted order, or computed alone
/// when the event does not post it.
int value(Event e, String id, TiebreakMethod m) =>
    (row(e, id).tiebreak(m) ??
            row(e.copy(tiebreaks: [m.code]), id).tiebreak(m)!)
        .value;

void main() {
  group('34E1 Modified Median', () {
    // Four rounds, eight players, every game played. Final scores:
    // A 3, B 1½, C 2½, D 2, E 3½, F 2, G 1½, H 0.
    final e = fixture([
      ['A-B=1', 'C-D=1', 'E-F=1', 'G-H=1'],
      ['C-A=0', 'E-G=1', 'B-D=0', 'F-H=1'],
      ['A-E=0', 'C-G=1', 'D-F=1', 'B-H=1'],
      ['E-C=½', 'A-D=1', 'G-B=½', 'H-F=0'],
    ]);

    test('plus score discards only the lowest opponent score', () {
      // A (3 of 4): opponents B 1½, C 2½, E 3½, D 2 → drop B → 8.
      expect(row(e, 'A').points, 6);
      expect(value(e, 'A', TiebreakMethod.solkoff), 19);
      expect(value(e, 'A', TiebreakMethod.modifiedMedian), 16);
    });

    test('even score discards the highest and the lowest', () {
      // D (2 of 4): opponents C 2½, B 1½, F 2, A 3 → drop A and B → 4½.
      expect(row(e, 'D').points, 4);
      expect(value(e, 'D', TiebreakMethod.modifiedMedian), 9);
    });

    test('minus score discards only the highest opponent score', () {
      // H (0 of 4): opponents G 1½, F 2, B 1½, F 2 → drop one 2 → 5.
      expect(row(e, 'H').points, 0);
      expect(value(e, 'H', TiebreakMethod.modifiedMedian), 10);
    });

    test('nine or more rounds discard two from each end', () {
      final long = fixture([
        for (var r = 0; r < 9; r++)
          r.isEven
              ? ['A-B=1', 'C-D=½', 'E-F=1', 'G-H=1']
              : ['A-C=1', 'B-E=½', 'D-G=½', 'F-H=½'],
      ], plannedRounds: 9);
      // A wins all nine: B (2) five times, C (2½) four times → Solkoff 20.
      expect(row(long, 'A').points, 18);
      expect(value(long, 'A', TiebreakMethod.solkoff), 40);
      // Plus score: drop the two lowest (B, B) → 16.
      expect(value(long, 'A', TiebreakMethod.modifiedMedian), 32);
      // Median (34E4) drops two from each end: 20 − 4 − 5 = 11.
      expect(value(long, 'A', TiebreakMethod.median), 22);
    });
  });

  group('34E1 unplayed-game adjustments', () {
    // Three rounds. A wins round 1 by forfeit and takes a full-point bye
    // in round 2; D takes a half-point bye in round 2. Final scores:
    // A 3, B 2, C 1, D ½. Adjusted (unplayed = ½): A 2, B 2½, C 1, D ½.
    final e = fixture([
      ['A-B=+', 'C-D=1'],
      ['B-C=1', 'A:bye1', 'D:bye½'],
      ['A-C=1', 'B-D=1'],
    ]);

    test("an opponent's forfeit loss and forfeit win both count ½", () {
      // C played D (½), B (2½ with the forfeit loss as ½) and A (2 with
      // the forfeit win and the bye as ½ each): Solkoff 5.
      expect(row(e, 'C').points, 2);
      expect(value(e, 'C', TiebreakMethod.solkoff), 10);
      // Minus score: drop B → 2½.
      expect(value(e, 'C', TiebreakMethod.modifiedMedian), 5);
    });

    test("the player's own half-point bye counts as an opponent on 0", () {
      // D played C (1) and B (2½); the bye round adds a 0: Solkoff 3½.
      expect(row(e, 'D').points, 1);
      expect(value(e, 'D', TiebreakMethod.solkoff), 7);
      // Minus score: drop B → 1.
      expect(value(e, 'D', TiebreakMethod.modifiedMedian), 2);
    });

    test("the player's own forfeit win and full-point bye count 0 each", () {
      // A played only C (1); two unplayed games add two 0s: Solkoff 1.
      expect(row(e, 'A').points, 6);
      expect(value(e, 'A', TiebreakMethod.solkoff), 2);
      // Plus score: drop one 0 → still 1.
      expect(value(e, 'A', TiebreakMethod.modifiedMedian), 2);
      // B played C (1) and D (½) and lost round 1 by forfeit (a 0).
      expect(value(e, 'B', TiebreakMethod.solkoff), 3);
      expect(value(e, 'B', TiebreakMethod.modifiedMedian), 3);
    });
  });

  group('34E3 / 34E9 Cumulative', () {
    test('sums the running score round by round', () {
      // Rulebook example: win, loss, win, draw, loss → 1,1,2,2½,2½ = 9.
      final e = fixture([
        ['A-B=1', 'C-D=1', 'E-F=1'],
        ['A-C=0', 'B-E=1', 'D-F=1'],
        ['A-D=1', 'C-E=1', 'B-F=1'],
        ['A-E=½', 'B-C=1', 'D-F=½'],
        ['A-B=0', 'C-D=1', 'E-F=1'],
      ]);
      expect(value(e, 'A', TiebreakMethod.cumulative), 18);
      // B: loss, win, win, win, win → 0,1,2,3,4 = 10.
      expect(value(e, 'B', TiebreakMethod.cumulative), 20);
    });

    test('deducts 1 per forfeit win or full-point bye and ½ per half-point '
        'bye, and sums played opponents for 34E9', () {
      final e = fixture([
        ['A-B=+', 'C:bye1', 'D:bye½'],
        ['A-C=1', 'B-D=1'],
        ['A-D=1', 'B-C=1'],
      ]);
      // A: 1 (forfeit), 2, 3 → 6, less 1 for the unplayed win = 5.
      expect(value(e, 'A', TiebreakMethod.cumulative), 10);
      // C: 1 (bye), 1, 1 → 3, less 1 = 2.
      expect(value(e, 'C', TiebreakMethod.cumulative), 4);
      // D: ½ (bye), ½, ½ → 1½, less ½ = 1.
      expect(value(e, 'D', TiebreakMethod.cumulative), 2);
      // B: 0, 1, 2 → 3; a forfeit loss deducts nothing.
      expect(value(e, 'B', TiebreakMethod.cumulative), 6);
      // B played C (2) and D (1) → 3.
      expect(value(e, 'B', TiebreakMethod.cumulativeOpposition), 6);
      // A's forfeit opponent B is not a played opponent: C 2 + D 1 = 3.
      expect(value(e, 'A', TiebreakMethod.cumulativeOpposition), 6);
    });
  });

  group('34E5 Result between tied players', () {
    test('breaks a tied pair that met and did not draw', () {
      // C 2, A 1, B 1, D 0; A beat B.
      final e = fixture(
        [
          ['A-B=1', 'C-D=1'],
          ['A-C=0', 'B-D=1'],
        ],
        tiebreaks: ['headToHead'],
      );
      final rows = standings(e, e.sections.single);
      expect(rows.map((r) => r.player.id), ['C', 'A', 'B', 'D']);
      expect(value(e, 'A', TiebreakMethod.headToHead), 1);
      expect(value(e, 'B', TiebreakMethod.headToHead), -1);
      expect(row(e, 'A').tiebreak(TiebreakMethod.headToHead)!.text, '+1');
      expect(row(e, 'B').tiebreak(TiebreakMethod.headToHead)!.text, '−1');
      expect(rows.map((r) => r.rank), [1, 2, 3, 4]);
    });

    test('leaves a three-way cycle tied', () {
      // A, B and C each score 2, each beating one of the others.
      final e = fixture(
        [
          ['A-B=1', 'C-D=1'],
          ['B-C=1', 'A-D=1'],
          ['C-A=1', 'B-D=1'],
        ],
        tiebreaks: ['headToHead'],
      );
      for (final id in ['A', 'B', 'C']) {
        expect(row(e, id).points, 4);
        expect(value(e, id, TiebreakMethod.headToHead), 0);
        expect(row(e, id).rank, 1);
      }
      expect(row(e, 'D').rank, 4);
    });

    test('ranks by plus or minus, not percentage, among more than two', () {
      // A, B and C tie on 2 ahead of D and E. A beat B and C (+2); B lost
      // to A and beat C (0); C lost to both (−2), scoring against D and
      // with a full-point bye.
      final e = fixture(
        [
          ['A-B=1', 'C-D=1', 'E:bye0'],
          ['A-C=1', 'B-D=1', 'E:bye0'],
          ['A-D=0', 'B-C=1', 'E:bye0'],
          ['A-E=0', 'B:bye0', 'C:bye1', 'D:bye0'],
        ],
        tiebreaks: ['headToHead'],
      );
      for (final id in ['A', 'B', 'C']) {
        expect(row(e, id).points, 4, reason: id);
      }
      expect(value(e, 'A', TiebreakMethod.headToHead), 2);
      expect(value(e, 'B', TiebreakMethod.headToHead), 0);
      expect(value(e, 'C', TiebreakMethod.headToHead), -2);
      expect(standings(e, e.sections.single).map((r) => r.player.id).take(3), [
        'A',
        'B',
        'C',
      ]);
    });
  });

  group('34E6–34E8, 34E10, 34E11, 34E13', () {
    // A 2½ (win, draw, forfeit win), B 0, C 2, D 1½.
    final e = fixture(
      [
        ['A-B=1', 'C-D=½'],
        ['C-A=½', 'D-B=1'],
        ['A-D=+', 'B-C=0'],
      ],
      ratings: {'A': 1800, 'B': 1600, 'C': 1700, 'D': 0},
    );

    test('most blacks counts played games as black', () {
      expect(value(e, 'A', TiebreakMethod.mostBlacks), 1);
      expect(value(e, 'B', TiebreakMethod.mostBlacks), 2);
      expect(value(e, 'D', TiebreakMethod.mostBlacks), 1);
    });

    test('Kashdan scores 4, 2, 1 and 0 for an unplayed game', () {
      expect(value(e, 'A', TiebreakMethod.kashdan), 6);
      // C: draw, draw, win.
      expect(value(e, 'C', TiebreakMethod.kashdan), 8);
      // B: three losses.
      expect(value(e, 'B', TiebreakMethod.kashdan), 3);
    });

    test('Sonneborn-Berger adds beaten and half of drawn opponents', () {
      // A beat B (0), drew C (2) and won by forfeit vs D (nothing):
      // 1 point → 4 quarter-points.
      expect(value(e, 'A', TiebreakMethod.sonnebornBerger), 4);
      final sb = row(
        e.copy(tiebreaks: ['sonnebornBerger']),
        'A',
      ).tiebreak(TiebreakMethod.sonnebornBerger)!;
      expect(sb.text, '1');
      expect(sb.number, 1.0);
      // C drew D (1½) and A (2½) and beat B (0): 2 points.
      expect(value(e, 'C', TiebreakMethod.sonnebornBerger), 8);
    });

    test('average opponent rating skips unrated opponents', () {
      // A played B 1600 and C 1700.
      expect(value(e, 'A', TiebreakMethod.averageOpponentRating), 1650);
      // D played C 1700 and B 1600.
      expect(value(e, 'D', TiebreakMethod.averageOpponentRating), 1650);
    });

    test("opponents' performance follows the rulebook example", () {
      // P beats B 1400 and C 1500, draws D 1600 and loses to E 1700:
      // (1800 + 1900 + 1600 + 1300) / 4 = 1650. Z, unrated, plays only P
      // and so is skipped from P's performance; Z's value is P's 1650.
      final perf = fixture(
        [
          ['P-B=1', 'C-D=½', 'E:bye½', 'Z:bye½'],
          ['C-P=0', 'B-E=1', 'D:bye½', 'Z:bye½'],
          ['P-D=½', 'B-C=1', 'E:bye½', 'Z:bye½'],
          ['E-P=1', 'D-B=1', 'C:bye½', 'Z:bye½'],
          ['Z-P=0', 'B-C=½', 'D-E=½'],
        ],
        ratings: {
          'P': 1550,
          'B': 1400,
          'C': 1500,
          'D': 1600,
          'E': 1700,
          'Z': 0,
        },
        tiebreaks: ['opponentsPerformance'],
      );
      expect(row(perf, 'Z').points, 4);
      expect(value(perf, 'Z', TiebreakMethod.opponentsPerformance), 1650);
    });

    test("opponents' performance leaves out games between tied players", () {
      // A and B tie on 1 behind C. A beat B; B's performance for A's
      // tie-break excludes that game (B beat D → 1900), as does A's for
      // B's (A lost to C → 1100).
      final tied = fixture(
        [
          ['A-B=1', 'C-D=1'],
          ['A-C=0', 'B-D=1'],
        ],
        tiebreaks: ['opponentsPerformance'],
      );
      expect(row(tied, 'A').points, row(tied, 'B').points);
      expect(value(tied, 'A', TiebreakMethod.opponentsPerformance), 1900);
      expect(value(tied, 'B', TiebreakMethod.opponentsPerformance), 1100);
      expect(row(tied, 'A').rank, 2);
      expect(row(tied, 'B').rank, 3);
    });

    test('coin flip is deterministic and recorded', () {
      final first = value(e, 'A', TiebreakMethod.coinFlip);
      expect(first, value(e, 'A', TiebreakMethod.coinFlip));
      expect(first, inInclusiveRange(0, 999999));
      expect(first, isNot(value(e, 'B', TiebreakMethod.coinFlip)));
      final other = Event.fromJson({...e.toJson(), 'id': 'event-2'});
      expect(
        value(other, 'A', TiebreakMethod.coinFlip),
        isNot(first),
        reason: 'the lot belongs to this event',
      );
    });
  });

  group('order and defaults', () {
    test('a Swiss defaults to 34E: Modified Median, Solkoff, Cumulative, '
        'Cumulative of opposition', () {
      expect(defaultTiebreaks(Format.swiss).map((m) => m.code), [
        'modifiedMedian',
        'solkoff',
        'cumulative',
        'cumulativeOpposition',
      ]);
      final e = fixture([
        ['A-B=1', 'C-D=1'],
      ]);
      expect(
        row(e, 'A').tiebreaks.map((t) => t.method),
        defaultTiebreaks(Format.swiss),
      );
    });

    test('a round robin or quad defaults to 34F: SB then head-to-head', () {
      for (final f in [Format.roundRobin, Format.quad]) {
        expect(defaultTiebreaks(f).map((m) => m.code), [
          'sonnebornBerger',
          'headToHead',
        ]);
      }
      final e = fixture([
        ['A-B=1', 'C-D=1'],
        ['A-C=1', 'B-D=1'],
        ['A-D=0', 'B-C=1'],
      ], format: Format.quad);
      expect(
        row(e, 'A').tiebreaks.map((t) => t.method),
        defaultTiebreaks(Format.quad),
      );
    });

    test('a posted order is honored in sequence', () {
      // C 2, A 1, B 1, D 0. A had white twice (no blacks), B one black;
      // Kashdan ties them (a win and a loss each); Solkoff favors A
      // (B 1 + C 2) over B (A 1 + D 0).
      final e = fixture(
        [
          ['A-B=1', 'C-D=1'],
          ['A-C=0', 'B-D=1'],
        ],
        tiebreaks: ['kashdan'],
      );
      expect(row(e, 'A').tiebreaks.map((t) => t.code), ['kashdan']);
      expect(row(e, 'A').rank, row(e, 'B').rank);
      Event posted(List<String> codes) =>
          Event.fromJson({...e.toJson(), 'tiebreaks': codes});
      final blacksFirst = posted(['kashdan', 'mostBlacks', 'solkoff']);
      expect(row(blacksFirst, 'A').tiebreaks.map((t) => t.code), [
        'kashdan',
        'mostBlacks',
        'solkoff',
      ]);
      expect(row(blacksFirst, 'B').rank, 2);
      expect(row(blacksFirst, 'A').rank, 3);
      final solkoffFirst = posted(['kashdan', 'solkoff', 'mostBlacks']);
      expect(row(solkoffFirst, 'A').rank, 2);
      expect(row(solkoffFirst, 'B').rank, 3);
      expect(tiebreakLabel('solkoff'), 'Solkoff');
      expect(tiebreakCodesProblem(['solkoff', 'solkoff']), isNotNull);
      expect(tiebreakCodesProblem(['buchholz']), isNotNull);
      expect(tiebreakCodesProblem(['solkoff', 'kashdan']), isNull);
    });

    test('ranks are equal only when every posted key ties', () {
      final e = fixture(
        [
          ['A-B=½', 'C-D=½'],
          ['A-C=½', 'B-D=½'],
        ],
        tiebreaks: ['solkoff', 'coinFlip'],
      );
      final rows = standings(e, e.sections.single);
      // Everyone is on 1 with Solkoff 2; the coin flip then breaks all ties.
      expect(rows.map((r) => r.points).toSet(), {2});
      expect(
        rows.map((r) => r.tiebreak(TiebreakMethod.solkoff)!.value).toSet(),
        {4},
      );
      expect(rows.map((r) => r.rank), [1, 2, 3, 4]);
      final shared = standings(e.copy(useTiebreaks: false), e.sections.single);
      expect(shared.map((r) => r.rank).toSet(), {1});
      expect(sharePlace(rows[0], rows[1], tiebreaks: true), isFalse);
      expect(sharePlace(rows[0], rows[1], tiebreaks: false), isTrue);
    });

    test('a re-entry uses only its own games (34H)', () {
      final e = fixture([
        ['A-B=1', 'C-D=1'],
        ['A-C=0', 'B-D=1'],
        ['A-D=1', 'C-B=1'],
      ]);
      // E re-enters for B after round 1 with a half-point bye for that round.
      final reentered = Event.fromJson({
        ...e.toJson(),
        'players': [
          ...e.players.map((p) => p.toJson()),
          Player(id: 'E', name: 'B again', reentryOf: 'B').toJson(),
        ],
      });
      final section = reentered.sections.single.copy(
        players: [...reentered.sections.single.players, 'E'],
        rounds: [
          reentered.sections.single.rounds[0].copy(
            byes: [const ByeAward('E', 1, 'Re-entry')],
          ),
          ...reentered.sections.single.rounds.skip(1),
        ],
      );
      final withE = reentered.copy(sections: [section]);
      final rowE = standings(
        withE,
        section,
      ).firstWhere((r) => r.player.id == 'E');
      expect(rowE.points, 1);
      // E's Solkoff is built from E's own list: no played games, three
      // slots unplayed → three zero opponents → 0.
      expect(rowE.tiebreak(TiebreakMethod.solkoff)!.value, 0);
      // B's own values are unchanged by the re-entry.
      expect(
        standings(withE, section)
            .firstWhere((r) => r.player.id == 'B')
            .tiebreak(TiebreakMethod.solkoff)!
            .value,
        row(e, 'B').tiebreak(TiebreakMethod.solkoff)!.value,
      );
    });
  });
}
