import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/history.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import '../support.dart';

void main() {
  test(
    'teams and symmetric requests persist, undo independently, and allow removal',
    () async {
      final dir = Directory.systemTemp.createTempSync('meow-requests-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/event.meow';
      final c = fixture(count: 6, path: path);
      final before = c.event!;
      c.assignTeam(['p0', 'p1'], 'Mixed doubles');
      expect(c.event!.player('p0').avoid, isEmpty);
      c.avoidPair('p0', 'p1', true);
      expect(c.event!.player('p0').avoid, {'p1'});
      expect(c.event!.player('p1').avoid, {'p0'});
      expect(
        describeChanges(before, c.event!).join(' '),
        contains('Mixed doubles'),
      );
      expect(
        describeChanges(before, c.event!).join(' '),
        contains('do not pair with'),
      );
      c.undo();
      expect(c.event!.player('p0').team, 'Mixed doubles');
      expect(c.event!.player('p0').avoid, isEmpty);
      c.redo();
      c.dispose();
      final reopened = TournamentController(SqliteEventRepository(path));
      addTearDown(reopened.dispose);
      expect(reopened.event!.player('p1').team, 'Mixed doubles');
      expect(reopened.event!.player('p1').avoid, {'p0'});
      reopened.avoidPair('p0', 'p1', false);
      expect(reopened.event!.players.every((p) => p.avoid.isEmpty), true);
      reopened.assignTeam(['p0', 'p1'], '');
      expect(reopened.event!.players.every((p) => p.team.isEmpty), true);
    },
  );

  test(
    'Swiss searches for another opponent and refuses impossible requests',
    () async {
      final c = fixture(count: 6);
      addTearDown(c.dispose);
      final initial = await c.propose();
      final g = initial.rounds.values.single.games.first;
      c.avoidPair(g.white, g.black, true);
      final next = await c.propose();
      expect(next.issues, isEmpty);
      expect(
        next.rounds.values.single.games.any(
          (x) => {x.white, x.black}.containsAll({g.white, g.black}),
        ),
        false,
      );
      for (final p in c.event!.players.skip(1)) {
        c.avoidPair('p0', p.id, true);
      }
      final impossible = await c.propose();
      expect(impossible.rounds, isEmpty);
      expect(impossible.issues.values.single, contains('opponent requests'));
    },
  );

  test(
    'requests preserve posted games and block manual conflicting pairings',
    () async {
      final c = fixture(count: 6);
      addTearDown(c.dispose);
      final batch = await c.propose();
      c.post(batch);
      final section = c.event!.sections.single;
      final game = section.rounds.single.games.first;
      c.avoidPair(game.white, game.black, true);
      expect(c.event!.games.first.toJson(), game.toJson());
      expect(
        () => c.replacePairing(
          section.id,
          1,
          section.rounds.single.games,
          'Review',
        ),
        throwsA(isA<TournamentException>()),
      );
    },
  );

  test(
    'quad reports a request conflict instead of silently pairing siblings',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final initial = await c.propose();
      final g = initial.rounds.values.single.games.first;
      c.avoidPair(g.white, g.black, true);
      final next = await c.propose();
      expect(next.rounds, isEmpty);
      expect(next.issues.values.single, contains('round robin'));
      expect(pairingRestricted(c.event!, g.black, g.white), true);
    },
  );

  test('older player records default to no team and no pairing requests', () {
    final old = Player(id: 'a', name: 'A').toJson()
      ..remove('team')
      ..remove('avoid');
    final p = Player.fromJson(old);
    expect(p.team, isEmpty);
    expect(p.avoid, isEmpty);
  });
  test(
    'quad detects a later-round restriction before posting round one',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final initial = await c.propose();
      final current = initial.rounds.values.single.games;
      final a = current.first.white, b = current.last.white;
      c.avoidPair(a, b, true);
      final next = await c.propose();
      expect(next.rounds, isEmpty);
      expect(next.issues.values.single, contains('round robin cannot skip'));
      expect(c.event!.games, isEmpty);
    },
  );
}
