import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/application/tournament_controller_core.dart'
    show runOnPairingIsolate;
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/standings.dart';
import '../support.dart';

/// Posting flows around the pairing engine: non-reporters held out, a
/// withdrawn player in a fixed schedule, quad seeding by pairing rating, the
/// name of a result's undo step, and the limit on how long pairing may run.
Matcher refuses(String text) => throwsA(
  isA<TournamentException>().having(
    (e) => e.message,
    'message',
    contains(text),
  ),
);

void main() {
  test('29H4: the next round pairs without the held-out result', () async {
    final c = fixture(count: 6, format: Format.swiss);
    addTearDown(c.dispose);
    c.post(await c.propose());
    final s = c.event!.sections.single;
    final held = s.rounds.single.games.first;
    for (final g in s.rounds.single.games.skip(1)) {
      c.recordResult(g.id, Outcome.whiteWin);
    }
    c.holdOutNonReporters(s.id, treatment: NonReporterTreatment.halfPointByes);
    expect(readyToPair(c.event!.sections.single), isTrue);
    final batch = await c.propose();
    expect(batch.issues, isEmpty);
    c.post(batch);
    final round = c.event!.sections.single.rounds.last;
    expect(round.games.length, 2);
    expect(
      round.byes.where((b) => b.points == 1).map((b) => b.player).toSet(),
      {held.white, held.black},
    );
    // The real result still goes in, and replaces the stand-in.
    c.recordResult(held.id, Outcome.blackWin, reason: 'Reported late');
    final game = c.event!.games.firstWhere((g) => g.id == held.id);
    expect(game.outcome, Outcome.blackWin);
    expect(game.pairingAssumption, isNull);
  });

  test('a result names its section, round and players for undo', () async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    c.post(await c.propose());
    final e = c.event!, g = e.games.first;
    c.recordResult(g.id, Outcome.draw);
    expect(
      c.undoLabel,
      'Result, ${e.sections.single.name} round 1 board ${g.board}: '
      '${e.player(g.white).name} – ${e.player(g.black).name}',
    );
  });

  test('a quad posts its rounds while a player is withdrawn', () async {
    final c = fixture(count: 4, format: Format.quad);
    addTearDown(c.dispose);
    final s = c.event!.sections.single;
    final gone = s.players.last;
    // Round 1 is played, then the fourth player leaves.
    for (final g in c.pairingEvent.sections.single.rounds.first.games) {
      c.recordResult(g.id, Outcome.draw);
    }
    c.setWithdrawn([gone], true);
    expect(c.quadScheduleIssues, isEmpty);
    final rounds = c.pairingEvent.sections.single.rounds;
    expect(rounds.length, 3);
    for (final r in rounds.skip(1)) {
      final forfeit = r.games.singleWhere(
        (g) => g.white == gone || g.black == gone,
      );
      expect(
        forfeit.outcome,
        forfeit.white == gone ? Outcome.blackForfeit : Outcome.whiteForfeit,
      );
      expect(r.byes.where((b) => b.player == gone), isEmpty);
      // The other board is an ordinary game waiting for its result.
      final other = r.games.singleWhere((g) => g != forfeit);
      expect(other.outcome, Outcome.unreported);
      c.recordResult(other.id, Outcome.whiteWin);
    }
    final e = c.event!;
    validateEvent(e);
    expect(e.player(gone).withdrawn, isTrue);
    // Each opponent still to play the withdrawn player scores the forfeit.
    final table = {
      for (final row in standings(e, e.sections.single)) row.player.id: row,
    };
    expect(table[gone]!.points, 1);
    expect(
      e.games.where((g) => !g.outcome.played && g.outcome.resolved).length,
      2,
    );
  });

  test('a round robin with a withdrawn player posts by itself', () async {
    final c = fixture(count: 5, format: Format.roundRobin);
    addTearDown(c.dispose);
    final gone = c.event!.sections.single.players[1];
    c.setWithdrawn([gone], true);
    final batch = await c.propose();
    expect(batch.issues, isEmpty);
    c.post(batch);
    final round = c.event!.sections.single.rounds.single;
    for (final g in round.games.where(
      (g) => g.white == gone || g.black == gone,
    )) {
      expect(g.outcome.resolved && !g.outcome.played, isTrue);
      expect(round.explanations.join('\n'), contains('withdrawn'));
    }
  });

  test('quads seed by the assigned pairing rating', () {
    final players = [
      for (var i = 0; i < 8; i++)
        Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 100),
      // Unrated, but assigned 1950 for pairing: belongs in the top quad.
      Player(id: 'new', name: 'Newcomer', pairingRating: 1950),
      for (var i = 8; i < 11; i++)
        Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 100),
    ];
    final groups = planQuads(players);
    expect(groups.first.players.map((p) => p.id), ['p0', 'new', 'p1', 'p2']);
  });

  test(
    'pairing that runs past its time limit is stopped and refused',
    () async {
      // One section of 40: its proposal cannot arrive within a microsecond.
      final c = fixture(count: 40, format: Format.swiss);
      addTearDown(c.dispose);
      final e = c.event!;
      c.change(
        'One section',
        e.copy(
          sections: [
            e.sections.first.copy(players: [for (final p in e.players) p.id]),
          ],
        ),
      );
      final before = c.event!.revision;
      c.pairingTimeLimit = const Duration(microseconds: 1);
      await expectLater(c.propose(), refuses('was stopped'));
      expect(c.event!.revision, before);
      c.pairingTimeLimit = const Duration(seconds: 60);
      expect((await c.propose()).rounds.values.single.games.length, 20);
    },
  );

  test('a fault on the pairing isolate comes back as itself', () async {
    // A bug in the engine, not a refusal: the error keeps its type and the
    // isolate's stack, so Diagnostics and the failure message can tell it
    // apart from a plain-words refusal.
    Object? caught;
    StackTrace? trace;
    try {
      await runOnPairingIsolate<int>(
        () => throw StateError('engine fault'),
        const Duration(seconds: 30),
      );
    } catch (error, stack) {
      caught = error;
      trace = stack;
    }
    expect(caught, isA<StateError>());
    expect((caught as StateError).message, 'engine fault');
    expect('$trace', contains('_runInIsolate'));
    // A refusal in plain words keeps its words.
    await expectLater(
      runOnPairingIsolate<int>(
        () => throw const TournamentException('Nobody left to pair.'),
        const Duration(seconds: 30),
      ),
      refuses('Nobody left to pair.'),
    );
    expect(
      await runOnPairingIsolate(() => 6 * 7, const Duration(seconds: 30)),
      42,
    );
  });
}
