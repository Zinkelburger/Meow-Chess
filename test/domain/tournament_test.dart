import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/standings.dart';
import '../support.dart';

void main() {
  test('quad boundaries conserve entrants and isolate bottom Swiss', () {
    for (var n = 4; n <= 500; n++) {
      final sizes = quadGroupSizes(n);
      expect(sizes.fold<int>(0, (n, v) => n + v), n);
      expect(sizes.take(sizes.length - 1).every((v) => v == 4), true);
      expect(sizes.last, n % 4 == 0 ? 4 : 4 + n % 4);
    }
    for (var n = 0; n < 4; n++) {
      expect(() => quadGroupSizes(n), throwsA(isA<TournamentException>()));
    }
  });
  test(
    'round robin covers odd and even fields once without duplicate assignment',
    () {
      for (var n = 2; n <= 20; n++) {
        final ids = List.generate(n, (i) => '$i');
        final schedule = roundRobinSchedule(ids);
        final pairs = <String>{};
        for (final round in schedule) {
          final used = <String>{};
          for (final (a, b) in round) {
            if (a != null) expect(used.add(a), true);
            if (b != null) expect(used.add(b), true);
            if (a != null && b != null) {
              final pair = [a, b]..sort();
              expect(pairs.add(pair.join('/')), true);
            }
          }
        }
        expect(pairs.length, n * (n - 1) ~/ 2);
      }
    },
  );
  test(
    'complete quad day, exact scores, reciprocal history and fixed round count',
    () async {
      final c = fixture();
      addTearDown(c.dispose);
      for (var round = 0; round < 3; round++) {
        c.post(await c.propose());
        for (final s in c.event!.sections) {
          for (final g in s.rounds.last.games) {
            c.recordResult(g.id, Outcome.draw);
          }
        }
      }
      expect(c.event!.games.length, 12);
      expect(c.event!.sections.every((s) => s.finished), true);
      for (final s in c.event!.sections) {
        expect(standings(c.event!, s).map((r) => r.points), everyElement(3));
      }
      expect((await c.propose()).rounds, isEmpty);
    },
  );
  test(
    '22 players finish mixed quad/Swiss day without repeat opponents',
    () async {
      final c = fixture(count: 22);
      addTearDown(c.dispose);
      for (var round = 0; round < 3; round++) {
        final proposals = await c.propose();
        expect(proposals.issues, isEmpty);
        c.post(proposals);
        for (final s in c.event!.sections) {
          for (final g in s.rounds.last.games) {
            c.recordResult(g.id, Outcome.draw);
          }
        }
      }
      expect(c.event!.games.length, 33);
      for (final p in c.event!.players) {
        final opponents = c.event!.games
            .where((g) => g.white == p.id || g.black == p.id)
            .map((g) => g.white == p.id ? g.black : g.white)
            .toList();
        expect(opponents.toSet().length, opponents.length);
      }
    },
  );
  test('double-game rounds preserve two color-reversed games', () async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final s = c.event!.sections.single;
    c.change(
      'Double games',
      c.event!.copy(sections: [s.copy(doubleGames: true)]),
    );
    c.post(await c.propose());
    final games = c.event!.games.toList();
    expect(games.length, 4);
    expect(games[1].white, games[0].black);
    expect(games[1].black, games[0].white);
    c.recordResult(games[0].id, Outcome.whiteWin);
    c.recordResult(games[1].id, Outcome.whiteWin);
    expect(c.event!.games.where((g) => g.outcome == Outcome.draw), isEmpty);
  });
  test(
    'stale proposals cannot post and incomplete rounds cannot advance',
    () async {
      final c = fixture();
      addTearDown(c.dispose);
      final stale = await c.propose();
      c.savePlayer(c.event!.players.first.copy(notes: 'Leaving early'));
      expect(() => c.post(stale), throwsA(isA<TournamentException>()));
      c.post(await c.propose());
      expect((await c.propose()).rounds, isEmpty);
    },
  );
  test('bye reservations never become fake games', () async {
    final c = fixture(count: 6);
    addTearDown(c.dispose);
    c.reserveBye('p0', 1, 1);
    c.post(await c.propose());
    final round = c.event!.sections.single.rounds.single;
    expect(round.byes.firstWhere((b) => b.player == 'p0').points, 1);
    expect(round.games.any((g) => g.white == 'p0' || g.black == 'p0'), false);
    expect(() => c.reserveBye('p0', 1, 0), throwsA(isA<TournamentException>()));
  });
  test(
    'one undo per independently committed result; practice stays practice',
    () async {
      final c = fixture(practice: true);
      addTearDown(c.dispose);
      c.post(await c.propose());
      final games = c.event!.games.toList();
      c.recordResult(games[0].id, Outcome.blackWin);
      c.recordResult(games[1].id, Outcome.draw);
      c.undo();
      expect(c.event!.games.first.outcome, Outcome.blackWin);
      expect(c.event!.games.elementAt(1).outcome, Outcome.unreported);
      c.undo();
      expect(c.event!.games.first.outcome, Outcome.unreported);
      c.change('Attempt reclassify', c.event!.copy(practice: false));
      expect(c.event!.practice, true);
    },
  );
  test(
    'historical corrections require reason and preserve later games',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post(await c.propose());
      for (final g in c.event!.games.toList()) {
        c.recordResult(g.id, Outcome.draw);
      }
      c.post(await c.propose());
      final old = c.event!.games.first.id;
      final later = c.event!.sections.single.rounds.last.games
          .map((g) => g.id)
          .toList();
      expect(
        () => c.recordResult(old, Outcome.whiteWin),
        throwsA(isA<TournamentException>()),
      );
      c.recordResult(old, Outcome.whiteWin, reason: 'Corrected signed slip');
      expect(
        c.event!.sections.single.rounds.last.games.map((g) => g.id),
        later,
      );
    },
  );
  test(
    'combine completed same-progress sections preserves games and carried scores',
    () async {
      final c = fixture();
      addTearDown(c.dispose);
      c.post(await c.propose());
      for (final g in c.event!.games.toList()) {
        c.recordResult(g.id, Outcome.draw);
      }
      final source = c.event!.sections.first, target = c.event!.sections.last;
      final history = c.event!.games.map((g) => g.id).toList();
      c.movePlayers(
        source.players,
        target.id,
        reason:
            'TD-approved common playing pool; original prize groups retained',
      );
      expect(c.event!.games.map((g) => g.id), history);
      expect(c.event!.sections.last.players.length, 8);
      expect(c.event!.transitions.single['effectiveRound'], 2);
      expect(
        standings(c.event!, c.event!.sections.last).map((r) => r.points),
        everyElement(1),
      );
    },
  );
  test('board collisions reject whole posting transaction', () async {
    final c = fixture();
    addTearDown(c.dispose);
    c.change(
      'Colliding range',
      c.event!.copy(
        sections: c.event!.sections.map((s) => s.copy(boardStart: 1)).toList(),
      ),
    );
    expect(
      () => c.post(
        PairingBatch(c.event!.revision, {
          for (final s in c.event!.sections)
            s.id: proposeRound(c.event!, s, c.newId),
        }, {}),
      ),
      throwsA(isA<TournamentException>()),
    );
    expect(c.event!.sections.every((s) => s.rounds.isEmpty), true);
  });
}
