import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/fide.dart';
import 'package:meow_chess/domain/fide_generator.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/trf.dart';

import '../support.dart';

/// What FIDE's verification checklist (VCL) and the endorsement reports
/// ask of a tournament program, beyond pairing and tie-breaks themselves.
Event _event(int count, {String accelerated = '', int rounds = 9}) {
  final players = [
    for (var i = 0; i < count; i++)
      Player(
        id: 'p$i',
        name: 'First$i Last$i',
        fideId: '${500000 + i}',
        fideStandard: 2600 - i * 5,
      ),
  ];
  return Event(
    id: 'vcl',
    name: 'VCL',
    date: '2026-10-10',
    timeControl: 'G/90 inc/30',
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'Open',
        players: [for (final p in players) p.id],
        plannedRounds: rounds,
        fideRated: true,
        unrated: true,
        accelerated: accelerated,
      ),
    ],
  );
}

void main() {
  group('Baku acceleration (C.04.7, VCL.10)', () {
    test('161 players: group A is 82, as the rules\' example says', () {
      final e = _event(161, accelerated: 'baku');
      final a = bakuAccelerations(trfTournament(e, e.sections.single));
      expect(a.map((x) => x.lastPlayer).toSet(), {82});
    });

    test('nine rounds: one point for three rounds, half for two', () {
      final e = _event(20, accelerated: 'baku');
      final a = bakuAccelerations(trfTournament(e, e.sections.single));
      expect(
        [for (final x in a) (x.halves, x.firstRound, x.lastRound)],
        [(2, 1, 3), (1, 4, 5)],
      );
      // 2 × ⌈20/4⌉ = 10.
      expect(a.first.lastPlayer, 10);
    });

    test('the TRF writes records 192 and 250', () {
      final e = _event(20, accelerated: 'baku');
      final trf = writeTrf(e, e.sections.single);
      expect(trf, contains('192 FIDE_DUTCH_BAKU'));
      expect(trf, contains('250       1.0   1   3    1   10'));
      expect(trf, contains('250       0.5   4   5    1   10'));
    });

    test('group A keeps its last player after a late entry (1.3.2)', () {
      final e = generateFideTournament(
        const RandomTournamentSettings(
          players: 20,
          rounds: 7,
          seed: 4,
          baku: true,
        ),
      );
      final s = e.sections.single;
      final last = s.bakuLast;
      expect(last, isNotEmpty);
      // A strong late entry ranks above the group's last player: the group
      // grows by one and still ends with the same player.
      final late = Player(
        id: 'late',
        name: 'Late Entry',
        fideId: '9999999',
        fideStandard: 2700,
      );
      final next = e.copy(
        players: [...e.players, late],
        sections: [
          s.copy(players: [...s.players, late.id]),
        ],
      );
      final t = trfTournament(next, next.sections.single);
      final a = bakuAccelerations(t);
      expect(t.players[a.first.lastPlayer - 1].id, last);
    });
  });

  group('pairing-allocated bye value (C.04.1 3, VCL.16)', () {
    test('a drawn bye writes record 162 and scores ½', () {
      final e = generateFideTournament(
        const RandomTournamentSettings(
          players: 9,
          rounds: 3,
          seed: 2,
          pabPoints: 1,
        ),
      );
      final s = e.sections.single;
      final bye = s.rounds.first.byes.firstWhere((b) => b.allocated);
      expect(bye.points, 1);
      final trf = writeTrf(e, s);
      expect(trf, contains('162  P 0.5'));
    });

    test('the value is fixed once the section is paired', () {
      final e = generateFideTournament(
        const RandomTournamentSettings(players: 9, rounds: 3, seed: 2),
      );
      final s = e.sections.single;
      expect(fideSettingsChangeProblem(s, s.copy(pabPoints: 1)), isNotNull);
      expect(
        fideSettingsChangeProblem(
          s.copy(rounds: const []),
          s.copy(rounds: const [], pabPoints: 1),
        ),
        isNull,
      );
    });
  });

  group('results (VCL.13–15)', () {
    test('½–0, 0–½ and 0–0 need a section US Chess does not rate', () {
      final e = _event(4, rounds: 3);
      final s = e.sections.single;
      Event withResult(Section section, Outcome o) => e.copy(
        sections: [
          section.copy(
            rounds: [
              Round(
                number: 1,
                games: [
                  Game(id: 'g', white: 'p0', black: 'p1', board: 1, outcome: o),
                  const Game(
                    id: 'h',
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
      for (final o in [
        Outcome.whiteHalf,
        Outcome.blackHalf,
        Outcome.bothLose,
      ]) {
        expect(() => validateEvent(withResult(s, o)), returnsNormally);
        expect(
          () => validateEvent(withResult(s.copy(unrated: false), o)),
          throwsA(isA<TournamentException>()),
        );
      }
      final half = withResult(s, Outcome.whiteHalf);
      final trf = writeTrf(half, half.sections.single);
      // White (pairing number 1) ½, Black (2) 0: each player's own result.
      expect(trf, contains('   2 w ='));
      expect(trf, contains('   1 b 0'));
    });

    test('a game of less than one move is W, D or L in the TRF', () {
      final e = generateFideTournament(
        const RandomTournamentSettings(
          players: 10,
          rounds: 3,
          seed: 9,
          shortGameRate: 1,
        ),
      );
      final trf = writeTrf(e, e.sections.single);
      final cells = RegExp(
        r' [wb] ([WDL10=])',
      ).allMatches(trf).map((m) => m[1]!).toSet();
      expect(cells.difference({'W', 'D', 'L'}), isEmpty);
    });

    test('an adjourned game pairs as a draw for one round only', () async {
      final c = fixture(count: 6, format: Format.swiss);
      addTearDown(c.dispose);
      c.change(
        'FIDE',
        c.event!.copy(
          players: [
            for (final (i, p) in c.event!.players.indexed)
              p.copy(fideId: '${600000 + i}', fideStandard: 2400 - i * 20),
          ],
          sections: [
            c.event!.sections.single.copy(fideRated: true, plannedRounds: 4),
          ],
        ),
      );
      final id = c.event!.sections.single.id;
      c.post(await c.propose(sectionId: id));
      final r1 = c.event!.sections.single.rounds.single;
      c.recordResult(r1.games[0].id, Outcome.unfinished);
      for (final g in r1.games.skip(1)) {
        c.recordResult(g.id, Outcome.whiteWin);
      }
      // Round 2 pairs with the adjourned game as a draw.
      expect(readyToPair(c.event!.sections.single), isTrue);
      c.post(await c.propose(sectionId: id));
      for (final g in c.event!.sections.single.rounds.last.games) {
        c.recordResult(g.id, Outcome.draw);
      }
      // Round 3 waits for the adjourned game's result.
      expect(readyToPair(c.event!.sections.single), isFalse);
      expect(
        () => proposeRound(c.event!, c.event!.sections.single, () => 'x'),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'message',
            contains('still adjourned'),
          ),
        ),
      );
    });

    test('a FIDE pairing assumption is a draw', () async {
      final c = fixture(count: 4, format: Format.swiss);
      addTearDown(c.dispose);
      c.change(
        'FIDE',
        c.event!.copy(
          players: [
            for (final (i, p) in c.event!.players.indexed)
              p.copy(fideId: '${700000 + i}'),
          ],
          sections: [c.event!.sections.single.copy(fideRated: true)],
        ),
      );
      c.post(await c.propose(sectionId: c.event!.sections.single.id));
      final g = c.event!.sections.single.rounds.single.games.first;
      expect(
        () => c.setPairingAssumption(g.id, Outcome.whiteWin, 'Still going'),
        throwsA(isA<TournamentException>()),
      );
      c.setPairingAssumption(g.id, Outcome.draw, 'Still going');
    });
  });
}
