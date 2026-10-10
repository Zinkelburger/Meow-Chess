import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/scheveningen.dart';

/// [a] Lions and [b] Tigers in one Scheveningen section, Lions at home.
Event matchEvent(
  int a,
  int b, {
  Set<String> withdrawn = const {},
  List<Round> rounds = const [],
  String homeTeam = 'Lions',
}) {
  final players = [
    for (var i = 0; i < a; i++)
      Player(
        id: 'l$i',
        name: 'Lion $i',
        rating: 1800 - i * 10,
        team: ' lions ',
        withdrawn: withdrawn.contains('l$i'),
      ),
    for (var i = 0; i < b; i++)
      Player(
        id: 't$i',
        name: 'Tiger $i',
        rating: 1790 - i * 10,
        team: 'Tigers',
        withdrawn: withdrawn.contains('t$i'),
      ),
  ];
  return Event(
    id: 'event',
    name: 'Lions v Tigers',
    date: '2026-10-10',
    players: players,
    sections: [
      Section(
        id: 'match',
        name: 'Match',
        players: [for (final p in players) p.id],
        format: Format.scheveningen,
        plannedRounds: a > b ? a : b,
        homeTeam: homeTeam,
      ),
    ],
  );
}

void main() {
  group('scheveningenSchedule', () {
    for (final (a, b) in [(4, 4), (5, 5), (6, 4), (3, 7), (1, 3), (8, 8)]) {
      test('$a v $b: every A meets every B once, nobody twice', () {
        final e = matchEvent(a, b);
        final schedule = scheveningenSchedule(e, e.sections.single);
        expect(schedule, hasLength(a > b ? a : b));
        final met = <String>{};
        for (final round in schedule) {
          final seen = <String>{};
          for (final (w, bl) in round) {
            for (final id in [w, bl].nonNulls) {
              expect(seen.add(id), isTrue, reason: '$id twice in a round');
            }
            if (w != null && bl != null) {
              expect(
                w.startsWith('l') != bl.startsWith('l'),
                isTrue,
                reason: 'sides never meet their own side',
              );
              final key = ([w, bl]..sort()).join('-');
              expect(met.add(key), isTrue, reason: '$key met twice');
            }
          }
        }
        expect(met, hasLength(a * b));
      });

      test('$a v $b: sit-outs are shared equally and colors balance', () {
        final e = matchEvent(a, b);
        final schedule = scheveningenSchedule(e, e.sections.single);
        final games = <String, int>{}, whites = <String, int>{};
        for (final round in schedule) {
          for (final (w, bl) in round) {
            if (w == null || bl == null) continue;
            games[w] = (games[w] ?? 0) + 1;
            games[bl] = (games[bl] ?? 0) + 1;
            whites[w] = (whites[w] ?? 0) + 1;
          }
        }
        for (final p in e.players) {
          final played = games[p.id] ?? 0;
          final expected = p.id.startsWith('l') ? b : a;
          expect(played, expected, reason: '${p.id} plays the other side');
          final white = whites[p.id] ?? 0;
          expect(
            (white - (played - white)).abs(),
            lessThanOrEqualTo(1),
            reason: '${p.id} colors: $white white of $played',
          );
        }
      });
    }

    test('side A has White on board 1 in round 1 and the sides alternate', () {
      final e = matchEvent(4, 4);
      final schedule = scheveningenSchedule(e, e.sections.single);
      expect(schedule[0].first.$1, 'l0');
      expect(schedule[0].every((p) => p.$1!.startsWith('l')), isTrue);
      expect(schedule[1].every((p) => p.$1!.startsWith('t')), isTrue);
    });

    test('the home team is matched case-insensitively and trimmed', () {
      final e = matchEvent(2, 2, homeTeam: 'LIONS ');
      final (a, b) = scheveningenSides(e, e.sections.single);
      expect(a, ['l0', 'l1']);
      expect(b, ['t0', 't1']);
    });

    test('an empty side or missing home team is refused plainly', () {
      final noHome = matchEvent(2, 2, homeTeam: '');
      expect(
        scheveningenProblem(noHome, noHome.sections.single),
        contains('two team labels'),
      );
      final wrong = matchEvent(2, 2, homeTeam: 'Bears');
      expect(
        scheveningenProblem(wrong, wrong.sections.single),
        contains('No player'),
      );
      expect(
        () => scheveningenSchedule(wrong, wrong.sections.single),
        throwsA(isA<TournamentException>()),
      );
    });
  });

  group('scheveningenRound', () {
    test('posts round 1 with boards from the first board and a note', () {
      final e = matchEvent(3, 3);
      var n = 0;
      final round = proposeRound(e, e.sections.single, () => 'g${n++}');
      expect(round.policy, 'scheveningen-v1');
      expect(round.games.map((g) => g.board), [1, 2, 3]);
      expect(round.note, contains('Lions vs Tigers'));
      expect(round.byes, isEmpty);
    });

    test('the larger side sits one out each round with a zero-point bye', () {
      final e = matchEvent(3, 4);
      final round = scheveningenRound(e, e.sections.single, 1, () => 'g');
      expect(round.games, hasLength(3));
      expect(round.byes.single.points, 0);
      expect(round.byes.single.reason, 'Scheveningen sit-out');
      expect(round.byes.single.player, startsWith('t'));
    });

    test('a withdrawal is refused like a round robin, not skipped', () {
      final e = matchEvent(3, 3, withdrawn: {'t1'});
      expect(
        () => scheveningenRound(e, e.sections.single, 1, () => 'g'),
        throwsA(
          isA<TournamentException>().having(
            (x) => x.message,
            'message',
            contains('unavailable (withdrawn)'),
          ),
        ),
      );
    });

    test('a do-not-pair request anywhere in the table is refused', () {
      final base = matchEvent(2, 2);
      final e = base.copy(
        players: [
          for (final p in base.players)
            p.id == 'l0' ? p.copy(avoid: {'t1'}) : p,
        ],
      );
      expect(
        () => scheveningenRound(e, e.sections.single, 1, () => 'g'),
        throwsA(
          isA<TournamentException>().having(
            (x) => x.message,
            'message',
            contains('cannot skip this meeting'),
          ),
        ),
      );
    });

    test('the match score follows results and heads the next round', () {
      final base = matchEvent(2, 2);
      var n = 0;
      final first = scheveningenRound(
        base,
        base.sections.single,
        1,
        () => 'g${n++}',
      );
      final played = first.copy(
        games: [
          first.games[0].copy(outcome: Outcome.whiteWin),
          first.games[1].copy(outcome: Outcome.draw),
        ],
      );
      final e = base.copy(
        sections: [
          base.sections.single.copy(rounds: [played]),
        ],
      );
      final s = e.sections.single;
      // Round 1 of a 2 v 2 table: Lions have White on both boards.
      expect(scheveningenScore(e, s), (3, 1));
      expect(scheveningenScoreLine(e, s), 'Lions 1½ – Tigers ½');
      final second = scheveningenRound(e, s, 2, () => 'g${n++}');
      expect(second.note, 'Lions 1½ – Tigers ½ after round 1.');
      expect(second.games.every((g) => g.white.startsWith('t')), isTrue);
    });
  });
}
