import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/fide_tiebreaks.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/standings.dart';

/// A hand-worked C.07 (2026) example covering Article 16's unplayed
/// rounds: a pairing-allocated bye, a forfeit win and loss, a half-point
/// bye followed by a played round (16.2.3) and a zero-point bye in the
/// last round (16.2.5).
///
///   R1  A–B 1–0   C–D ½–½   E pairing-allocated bye
///   R2  A–C forfeit win for A   B–E 0–1   D half-point bye
///   R3  A–E ½–½   B–D 1–0   C withdrawn (zero-point bye)
///
/// Scores: A 2½, E 2½, B 1, D 1, C ½. Adjusted for opponents (16.3):
/// C's last-round bye counts as a draw, so C is 1; the others as scored.
Event _event() {
  Player p(String id) => Player(id: id, name: 'Player $id', fideId: '1$id');
  final players = [
    for (final id in ['a', 'b', 'c', 'd', 'e']) p(id),
  ];
  Game g(String id, String w, String b, Outcome o) =>
      Game(id: id, white: w, black: b, board: 1, outcome: o);
  return Event(
    id: 'tb',
    name: 'Tie-breaks',
    date: '2026-10-10',
    timeControl: 'G/90 inc/30',
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'Open',
        players: [for (final x in players) x.id],
        plannedRounds: 3,
        fideRated: true,
        rounds: [
          Round(
            number: 1,
            games: [
              g('1', 'a', 'b', Outcome.whiteWin),
              g('2', 'c', 'd', Outcome.draw),
            ],
            byes: const [
              ByeAward('e', 2, 'Pairing-allocated bye', allocated: true),
            ],
          ),
          Round(
            number: 2,
            games: [
              g('3', 'a', 'c', Outcome.whiteForfeit),
              g('4', 'b', 'e', Outcome.blackWin),
            ],
            byes: const [ByeAward('d', 1, 'Requested bye')],
          ),
          Round(
            number: 3,
            games: [
              g('5', 'a', 'e', Outcome.draw),
              g('6', 'b', 'd', Outcome.whiteWin),
            ],
            byes: const [ByeAward('c', 0, 'Withdrawn')],
          ),
        ],
      ),
    ],
  );
}

void main() {
  final e = _event();
  final s = e.sections.single;
  final calc = FideTiebreaks(e, s, (g) => g.outcome);
  int v(TiebreakMethod m, String id, [List<String> group = const []]) =>
      calc.value(m, id, group);

  test('16.3: a last-round requested bye counts as a draw for opponents', () {
    expect(calc.score('c'), 1);
    expect(calc.adjusted('c'), 2);
    expect(
      calc.adjusted('d'),
      2,
      reason: '16.2.3: the bye is followed by play',
    );
  });

  test('Buchholz with dummy opponents (16.4)', () {
    // A: B 1 + forfeit dummy min(2½, C's adjusted 1) + E 2½ = 4½.
    expect(v(TiebreakMethod.fideBh, 'a'), 9);
    // E: PAB dummy min(2½, ½ × 3 rounds) = 1½, B 1, A 2½ = 5.
    expect(v(TiebreakMethod.fideBh, 'e'), 10);
    // C: D 1 + forfeit dummy min(½, 2½) + bye dummy min(½, 1½) = 2.
    expect(v(TiebreakMethod.fideBh, 'c'), 4);
  });

  test('Cut-1 removes a voluntary unplayed round first (16.5)', () {
    expect(v(TiebreakMethod.fideBhC1, 'a'), 7);
    expect(v(TiebreakMethod.fideBhC1, 'e'), 8);
    // D's half-point bye (dummy 1) is cut ahead of an equal opponent.
    expect(v(TiebreakMethod.fideBhC1, 'd'), 4);
    expect(v(TiebreakMethod.fideBhC1, 'b'), 10);
  });

  test('Sonneborn–Berger counts unplayed rounds against the dummy', () {
    // A: 1×1 + 1×1 + 2½×½ = 3¼.
    expect(v(TiebreakMethod.fideSb, 'a'), 13);
    // E: 1½×1 + 1×1 + 2½×½ = 3¾.
    expect(v(TiebreakMethod.fideSb, 'e'), 15);
  });

  test('own-record methods', () {
    expect(v(TiebreakMethod.fideWin, 'a'), 2);
    expect(v(TiebreakMethod.fideWin, 'e'), 2);
    expect(v(TiebreakMethod.fideWon, 'a'), 1);
    expect(v(TiebreakMethod.fideBpg, 'e'), 2);
    expect(v(TiebreakMethod.fideBwg, 'e'), 1);
    expect(v(TiebreakMethod.fidePs, 'a'), 11);
    expect(v(TiebreakMethod.fidePsC1, 'a'), 9);
    expect(v(TiebreakMethod.fideRep, 'c'), 1);
    expect(v(TiebreakMethod.fideRep, 'd'), 2);
  });

  test('direct encounter between the tied leaders', () {
    // ½ each: they share first place among themselves.
    expect(v(TiebreakMethod.fideDe, 'a', ['a', 'e']), -1);
    expect(v(TiebreakMethod.fideDe, 'e', ['a', 'e']), -1);
    expect(TiebreakMethod.fideDe.format(-1), '1');
    // B and D met; A and D never did. A and B both have 1 among the three
    // and A could still reach 2, so nobody is alone on top (6.3).
    final place = [
      for (final p in ['a', 'b', 'd'])
        v(TiebreakMethod.fideDe, p, ['a', 'b', 'd']),
    ];
    expect(place.toSet(), {-1});
  });

  test('FIDE sections rank by the default C.07 order', () {
    final rows = standings(e, s);
    expect(rows.first.tiebreaks.first.method, TiebreakMethod.fideBhC1);
    // E's Buchholz Cut-1 (4) beats A's (3½).
    expect([for (final r in rows.take(2)) r.player.id], ['e', 'a']);
    expect(rows[0].rank, 1);
    expect(rows[1].rank, 2);
    // B over D on Buchholz Cut-1.
    expect([for (final r in rows.skip(2).take(2)) r.player.id], ['b', 'd']);
  });

  test('round robins never use Buchholz', () {
    final rr = e.copy(
      fideTiebreaks: const ['BH/C1', 'SB', 'WIN'],
      sections: [s.copy(format: Format.roundRobin)],
    );
    expect(fideSectionTiebreaks(rr, rr.sections.single), [
      TiebreakMethod.fideSb,
      TiebreakMethod.fideWin,
    ]);
    expect(fideTiebreakCodesProblem(['BH', 'modifiedMedian']), isNotNull);
    expect(tiebreakCodesProblem(['BH']), isNotNull);
  });

  test('rating-based methods follow the B.02 tables', () {
    // X beats a 2000 and draws an 1800: 1½ of 2 against ARO 1900.
    final players = [
      Player(id: 'x', name: 'X Player', fideStandard: 1900),
      Player(id: 'y', name: 'Y Player', fideStandard: 2000),
      Player(id: 'z', name: 'Z Player', fideStandard: 1800),
    ];
    final ev = Event(
      id: 'perf',
      name: 'Performance',
      date: '2026-10-10',
      timeControl: 'G/90 inc/30',
      players: players,
      sections: [
        Section(
          id: 's',
          name: 'Open',
          players: const ['x', 'y', 'z'],
          format: Format.roundRobin,
          plannedRounds: 3,
          fideRated: true,
          rounds: [
            Round(
              number: 1,
              games: const [
                Game(
                  id: '1',
                  white: 'x',
                  black: 'y',
                  board: 1,
                  outcome: Outcome.whiteWin,
                ),
              ],
              byes: const [ByeAward('z', 0, 'Round-robin sit-out')],
            ),
            Round(
              number: 2,
              games: const [
                Game(
                  id: '2',
                  white: 'z',
                  black: 'x',
                  board: 1,
                  outcome: Outcome.draw,
                ),
              ],
              byes: const [ByeAward('y', 0, 'Round-robin sit-out')],
            ),
          ],
        ),
      ],
    );
    final t = FideTiebreaks(ev, ev.sections.single, (g) => g.outcome);
    expect(t.averageOpponentRating('x'), 1900);
    // p = 0.75 → dp 193.
    expect(t.performance('x'), 2093);
    // Lowest R with PD(R−2000) + PD(R−1800) ≥ 1.50: 2103 (.64 + .86).
    expect(t.perfectPerformance('x'), 2103);
    // Y scored zero: 800 below its only opponent.
    expect(t.perfectPerformance('y'), 1100);
    expect(fideExpectedHundredths(0), 50);
    expect(fideExpectedHundredths(-736), 0);
    expect(fideScoreDifference[50], 0);
  });

  test('Fore Buchholz treats the last round as drawn', () {
    // B: A 2½ + E 2½ + D, whose last-round loss to B counts as a draw
    // (1 → 1½): 6½, against Buchholz 6.
    expect(calc.value(TiebreakMethod.fideBh, 'b', const []), 12);
    expect(calc.value(TiebreakMethod.fideFb, 'b', const []), 13);
  });

  test('direct encounter: 6.2 re-applies, 6.3 finds who is alone on top', () {
    Game g(String id, String w, String b, Outcome o, {int board = 1}) =>
        Game(id: id, white: w, black: b, board: board, outcome: o);
    Event ev(Format format, List<Round> rounds, List<String> ids) => Event(
      id: 'de',
      name: 'DE',
      date: '2026-10-10',
      players: [for (final id in ids) Player(id: id, name: 'P $id')],
      sections: [
        Section(
          id: 's',
          name: 'Open',
          players: ids,
          format: format,
          plannedRounds: rounds.length,
          fideRated: true,
          rounds: rounds,
        ),
      ],
    );
    // Round robin of four, all met. Among A, B and C: A beat B, B beat C,
    // A drew C (A 1½, B 1, C ½). D lost to all three.
    final rr = ev(
      Format.roundRobin,
      [
        Round(
          number: 1,
          games: [
            g('1', 'a', 'b', Outcome.whiteWin),
            g('2', 'c', 'd', Outcome.whiteWin, board: 2),
          ],
        ),
        Round(
          number: 2,
          games: [
            g('3', 'b', 'c', Outcome.whiteWin),
            g('4', 'd', 'a', Outcome.blackWin, board: 2),
          ],
        ),
        Round(
          number: 3,
          games: [
            g('5', 'a', 'c', Outcome.draw),
            g('6', 'b', 'd', Outcome.whiteWin, board: 2),
          ],
        ),
      ],
      ['a', 'b', 'c', 'd'],
    );
    final t = FideTiebreaks(rr, rr.sections.single, (x) => x.outcome);
    final group = ['a', 'b', 'c'];
    final values = {for (final p in group) p: t.directEncounter(p, group)};
    expect(values['a']! > values['b']! && values['b']! > values['c']!, isTrue);

    // Swiss: X beat Y and Z; Y and Z never met. X stays alone on top
    // whatever Y–Z would have been; Y and Z stay tied.
    final sw = ev(
      Format.swiss,
      [
        Round(
          number: 1,
          games: [g('1', 'x', 'y', Outcome.whiteWin)],
          byes: const [ByeAward('z', 0, 'Requested bye')],
        ),
        Round(
          number: 2,
          games: [g('2', 'z', 'x', Outcome.blackWin)],
          byes: const [ByeAward('y', 0, 'Requested bye')],
        ),
      ],
      ['x', 'y', 'z'],
    );
    final u = FideTiebreaks(sw, sw.sections.single, (x) => x.outcome);
    final tied = ['x', 'y', 'z'];
    expect(
      u.directEncounter('x', tied),
      greaterThan(u.directEncounter('y', tied)),
    );
    expect(u.directEncounter('y', tied), u.directEncounter('z', tied));
  });
}
