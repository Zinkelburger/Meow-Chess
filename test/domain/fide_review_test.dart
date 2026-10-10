import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/fide.dart';
import 'package:meow_chess/domain/fide_tiebreaks.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/trf.dart';
import 'package:meow_chess/infrastructure/fide_export.dart';

import '../support.dart';

/// Regressions from the FIDE code review.
Event _event(int count, {bool house = false}) {
  final players = [
    for (var i = 0; i < count; i++)
      Player(
        id: 'p$i',
        name: 'First$i Last$i',
        fideId: '${300000 + i}',
        fideStandard: 2000 - i * 50,
        house: house && i == count - 1,
      ),
  ];
  return Event(
    id: 'review',
    name: 'Review',
    date: '2026-10-10',
    city: 'Boston',
    timeControl: 'G/90 inc/30',
    fide: const FideRegistration(
      chiefArbiter: FideOfficial(name: 'A Arbiter', id: '2000001'),
    ),
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'Open',
        players: [for (final p in players) p.id],
        plannedRounds: 3,
        fideRated: true,
      ),
    ],
  );
}

void main() {
  test('pairing numbers stay fixed once round 1 is posted', () async {
    final c = fixture(count: 6, format: Format.swiss);
    addTearDown(c.dispose);
    final e = c.event!;
    c.change(
      'FIDE',
      e.copy(
        players: [
          for (final (i, p) in e.players.indexed)
            p.copy(fideId: '${400000 + i}', fideStandard: 2000 - i * 10),
        ],
        sections: [e.sections.single.copy(fideRated: true)],
      ),
    );
    final s = c.event!.sections.single;
    c.post(await c.propose(sectionId: s.id));
    final posted = c.event!.sections.single;
    expect(posted.fideOrder, [for (final p in c.event!.players) p.id]);
    // The lowest-rated player's rating is corrected after round 1 (the
    // player panel locks FIDE ratings then, so the correction goes straight
    // to the event): no renumbering.
    final last = posted.players.last;
    c.change(
      'Correct a rating',
      c.event!.copy(
        players: [
          for (final p in c.event!.players)
            p.id == last ? p.copy(fideStandard: 2500) : p,
        ],
      ),
    );
    final order = fidePairingOrder(c.event!, c.event!.sections.single);
    expect(order.last.id, last);
  });

  test('a late entry is slotted in by rating', () {
    final e = _event(4);
    final s = e.sections.single.copy(
      fideOrder: const ['p0', 'p1', 'p2'],
      rounds: [Round(number: 1, games: const [])],
    );
    expect(
      [for (final p in fidePairingOrder(e, s)) p.id],
      ['p0', 'p1', 'p2', 'p3'],
    );
  });

  test('a house player sits out a FIDE round with a zero bye', () {
    final e = _event(6, house: true);
    final r = proposeRound(e, e.sections.single, () => 'g');
    final house = r.byes.where((b) => b.player == 'p5').single;
    expect(house.points, 0);
    expect(r.byes.where((b) => b.allocated), hasLength(1));
  });

  test('US Chess selective re-pairing is refused in FIDE sections', () {
    final e = _event(6);
    final r = proposeRound(e, e.sections.single, () => 'g');
    final posted = e.copy(
      sections: [
        e.sections.single.copy(rounds: [r]),
      ],
    );
    expect(
      () => repairUnstartedRound(posted, posted.sections.single, {}, () => 'x'),
      throwsA(isA<TournamentException>()),
    );
  });

  test('two sections that name alike still get two files', () {
    final e = _event(4);
    final s = e.sections.single;
    Round played(String id) => Round(
      number: 1,
      games: [
        Game(
          id: '${id}1',
          white: 'p0',
          black: 'p1',
          board: 1,
          outcome: Outcome.draw,
        ),
        Game(
          id: '${id}2',
          white: 'p2',
          black: 'p3',
          board: 2,
          outcome: Outcome.draw,
        ),
      ],
    );
    final two = e.copy(
      sections: [
        s.copy(name: 'U1800 (Sat)', plannedRounds: 1, rounds: [played('a')]),
        Section(id: 't', name: 'U1800 Sat', players: const [], fideRated: true),
      ],
    );
    // Give the second section its own players.
    final more = [
      for (var i = 4; i < 8; i++)
        Player(id: 'p$i', name: 'F$i L$i', fideId: '${500000 + i}'),
    ];
    final both = two.copy(
      players: [...two.players, ...more],
      sections: [
        two.sections.first,
        two.sections.last.copy(
          players: [for (final p in more) p.id],
          plannedRounds: 1,
          rounds: [
            Round(
              number: 1,
              games: [
                Game(
                  id: 'b1',
                  white: 'p4',
                  black: 'p5',
                  board: 3,
                  outcome: Outcome.draw,
                ),
                Game(
                  id: 'b2',
                  white: 'p6',
                  black: 'p7',
                  board: 4,
                  outcome: Outcome.draw,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    expect(fideReport(both).keys, hasLength(2));
  });

  test('a two-game round bye scores in both TRF legs', () {
    final e = _event(3);
    final s = e.sections.single.copy(
      format: Format.roundRobin,
      doubleGames: true,
      rounds: [
        Round(
          number: 1,
          games: const [
            Game(
              id: '1',
              white: 'p0',
              black: 'p1',
              board: 1,
              outcome: Outcome.whiteWin,
            ),
            Game(
              id: '2',
              white: 'p1',
              black: 'p0',
              board: 1,
              leg: 2,
              outcome: Outcome.draw,
            ),
          ],
          byes: const [ByeAward('p2', 4, 'Full-point bye', allocated: true)],
        ),
      ],
    );
    final t = trfTournament(e, s);
    final p2 = e.player('p2');
    final cells = [
      for (final (r, leg) in t.rounds) trfCell(t, p2, r, leg, (g) => g.outcome),
    ];
    expect(cells.map((c) => c.result), ['U', 'U']);
    expect(cells.fold(0, (n, c) => n + trfCellHalves(c)), 4);
  });

  test('direct encounter counts a round-robin forfeit', () {
    final e = _event(2);
    final s = e.sections.single.copy(
      format: Format.roundRobin,
      plannedRounds: 1,
      rounds: [
        Round(
          number: 1,
          games: const [
            Game(
              id: '1',
              white: 'p0',
              black: 'p1',
              board: 1,
              outcome: Outcome.whiteForfeit,
            ),
          ],
        ),
      ],
    );
    final calc = FideTiebreaks(e, s, (g) => g.outcome);
    expect(calc.directEncounter('p0', ['p0', 'p1']), -1);
    expect(calc.directEncounter('p1', ['p0', 'p1']), -2);
  });
}
