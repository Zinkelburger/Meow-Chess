import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/bye_policy.dart';
import 'package:meow_chess/domain/history.dart';
import 'package:meow_chess/domain/model.dart';
import '../support.dart';

Matcher refuses(String text) => throwsA(
  isA<TournamentException>().having(
    (e) => e.message,
    'message',
    contains(text),
  ),
);

/// A four-player Swiss with a five-round plan and the given bye policy.
TournamentController swiss({Map<String, dynamic> byeRules = const {}}) {
  final c = fixture(count: 4, format: Format.swiss);
  c.change(
    'Plan five rounds',
    c.event!.copy(
      sections: [
        for (final s in c.event!.sections)
          s.copy(plannedRounds: 5, byeRules: byeRules),
      ],
    ),
  );
  return c;
}

Future<void> playRound(TournamentController c, {String? winner}) async {
  c.post(await c.propose());
  for (final g in c.event!.sections.single.rounds.last.games) {
    c.recordResult(
      g.id,
      winner == null
          ? Outcome.draw
          : g.white == winner
          ? Outcome.whiteWin
          : g.black == winner
          ? Outcome.blackWin
          : Outcome.draw,
    );
  }
}

void main() {
  test('22C1: half-point byes are refused after the announced last round', () {
    final c = swiss(byeRules: {'lastHalfByeRound': 3});
    addTearDown(c.dispose);
    c.reserveBye('p0', 3, 1);
    expect(c.event!.player('p0').byes[3], 1);
    expect(
      () => c.reserveBye('p0', 4, 1),
      refuses('announced only through round 3'),
    );
    // Zero-point byes are never limited.
    c.reserveBye('p0', 4, 0);
    expect(c.event!.player('p0').byes[4], 0);
  });

  test('22C3: half-point byes per player are capped', () {
    final c = swiss(byeRules: {'maxHalfByes': 1});
    addTearDown(c.dispose);
    c.reserveBye('p1', 2, 1);
    expect(() => c.reserveBye('p1', 3, 1), refuses('one half-point bye'));
    // Changing the same round's bye is not a second bye.
    c.reserveBye('p1', 2, 1);
    c.reserveBye('p1', 2, -1);
    c.reserveBye('p1', 3, 1);
    expect(c.event!.player('p1').byes, {3: 1});
  });

  test('22C4: byes from the announced round need an irrevocable notice', () {
    final c = swiss(byeRules: {'irrevocableFromRound': 5});
    addTearDown(c.dispose);
    c.reserveBye('p2', 4, 1);
    expect(() => c.reserveBye('p2', 5, 1), refuses('declared irrevocable'));
    c.reserveBye('p2', 5, 1, irrevocable: true);
    final p = c.event!.player('p2');
    expect(p.byes[5], 1);
    expect(p.irrevocableByes, {5});
    // Cancelling keeps the declaration (22C5); withdrawing it clears it.
    c.reserveBye('p2', 5, -1);
    expect(c.event!.player('p2').byes.containsKey(5), isFalse);
    expect(c.event!.player('p2').irrevocableByes, {5});
    c.reserveBye('p2', 5, -1, irrevocable: false);
    expect(c.event!.player('p2').irrevocableByes, isEmpty);
  });

  test(
    '22C5: a win after cancelling an irrevocable bye is a draw for prizes',
    () async {
      final c = swiss(byeRules: {'irrevocableFromRound': 2});
      addTearDown(c.dispose);
      c.reserveBye('p0', 2, 1, irrevocable: true);
      c.reserveBye('p0', 2, -1); // the director agreed to let them play
      await playRound(c);
      await playRound(c, winner: 'p0');
      final round = c.event!.sections.single.rounds.last;
      final game = round.games.firstWhere(
        (g) => g.white == 'p0' || g.black == 'p0',
      );
      expect(game.outcome, anyOf(Outcome.whiteWin, Outcome.blackWin));
      expect(game.prizeOutcome, Outcome.draw);
      expect(game.note, contains(irrevocableByeNote));
      // Correcting to a draw lifts the override and its note.
      c.correctResult(c.reviewResult(game.id), Outcome.draw);
      final corrected = c.event!.games.firstWhere((g) => g.id == game.id);
      expect(corrected.prizeOutcome, isNull);
      expect(corrected.note, isNot(contains(irrevocableByeNote)));
    },
  );

  test(
    '29H3: unreported games become double forfeits in one revision',
    () async {
      final c = swiss();
      addTearDown(c.dispose);
      c.post(await c.propose());
      final s = c.event!.sections.single;
      final games = s.rounds.single.games;
      c.recordResult(games.last.id, Outcome.draw);
      final before = c.event!.revision;
      final boards = c.holdOutNonReporters(s.id, treatment: 'doubleForfeit');
      expect(boards, [games.first.board]);
      expect(c.event!.revision, before + 1);
      final treated = c.event!.games.firstWhere((g) => g.id == games.first.id);
      expect(treated.outcome, Outcome.doubleForfeit);
      expect(treated.note, contains('29H3'));
      expect(
        () => c.holdOutNonReporters(s.id, treatment: 'doubleForfeit'),
        refuses('has a result'),
      );
    },
  );

  test(
    '29H4: both non-reporters get half-point byes for the next round',
    () async {
      final c = swiss();
      addTearDown(c.dispose);
      c.post(await c.propose());
      final s = c.event!.sections.single;
      final game = s.rounds.single.games.first;
      c.recordResult(s.rounds.single.games.last.id, Outcome.draw);
      c.holdOutNonReporters(s.id, treatment: 'halfPointByes');
      expect(c.event!.player(game.white).byes[2], 1);
      expect(c.event!.player(game.black).byes[2], 1);
      expect(
        c.event!.games.firstWhere((g) => g.id == game.id).note,
        contains('29H4'),
      );
      c.undo();
      expect(c.event!.player(game.white).byes, isEmpty);
    },
  );

  test('29H4 respects the announced bye availability', () async {
    final c = swiss(byeRules: {'lastHalfByeRound': 1});
    addTearDown(c.dispose);
    c.post(await c.propose());
    final s = c.event!.sections.single;
    expect(
      () => c.holdOutNonReporters(s.id, treatment: 'halfPointByes'),
      refuses('not available for round 2'),
    );
  });

  test('history describes bye policy and irrevocable declarations', () {
    final c = swiss();
    addTearDown(c.dispose);
    final before = c.event!;
    c.reserveBye('p3', 4, 1, irrevocable: true);
    expect(
      describeChanges(before, c.event!).join('\n'),
      contains('round 4 bye declared irrevocable'),
    );
    final section = c.event!;
    c.change(
      'Policy',
      c.event!.copy(
        sections: [
          for (final s in c.event!.sections)
            s.copy(byeRules: const {'maxHalfByes': 1}),
        ],
      ),
    );
    expect(
      describeChanges(section, c.event!).join('\n'),
      contains('bye policy: half-point byes in any round · one per player'),
    );
  });
}
