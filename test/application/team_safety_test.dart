import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:path/path.dart' as p;

TournamentController swiss(String path) {
  final c = TournamentController(SqliteEventRepository(path))..create('Family Swiss');
  c.importPlayers([for (var i = 0; i < 10; i++) Player(id: 'p$i', name: 'Entrant $i', rating: 2000 - 100 * i)]);
  c.addSection('Open', Format.swiss, 4);
  return c;
}

void main() {
  test('team labels do not impose opponent restrictions or change scores', () async {
    final c = swiss(':memory:');
    addTearDown(c.dispose);
    final initial = (await c.propose()).rounds.values.single;
    c.assignTeam(c.event!.players.map((p) => p.id), 'One club');
    final next = (await c.propose()).rounds.values.single;
    expect(next.games.map((g) => (g.white, g.black)), initial.games.map((g) => (g.white, g.black)));
    expect(c.event!.players.every((p) => p.avoid.isEmpty), true);
  });

  test('four Swiss rounds obey sibling restrictions after every reopen', () async {
    final directory = Directory.systemTemp.createTempSync('meow teams é ');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = p.join(directory.path, "Family's event.meow");
    var c = swiss(path);
    addTearDown(() => c.dispose());
    c.assignTeam(['p0', 'p5'], "O'Brien mixed doubles");
    c.avoidPair('p0', 'p5', true);
    final opponents = <String>{};
    for (var round = 0; round < 4; round++) {
      final batch = await c.propose();
      expect(batch.issues, isEmpty);
      c.post(batch);
      for (final game in c.event!.sections.single.rounds.last.games) {
        expect(pairingRestricted(c.event!, game.white, game.black), false);
        expect(opponents.add(([game.white, game.black]..sort()).join('/')), true);
        c.recordResult(game.id, Outcome.draw);
      }
      final expected = c.event!.encode();
      final history = c.repository.history();
      c.dispose();
      c = TournamentController(SqliteEventRepository(path));
      expect(c.event!.encode(), expected);
      expect(c.repository.history(), history);
      expect(c.event!.player('p0').team, "O'Brien mixed doubles");
      expect(c.event!.player('p5').avoid, {'p0'});
    }
    final copy = p.join(directory.path, 'independent copy.meow');
    c.repository.backup(copy);
    c.assignTeam(['p0'], 'Changed later');
    final backup = TournamentController(SqliteEventRepository(copy));
    addTearDown(backup.dispose);
    expect(backup.event!.player('p0').team, "O'Brien mixed doubles");
    expect(backup.event!.player('p0').avoid, {'p5'});
    expect(backup.event!.games, hasLength(20));
  });

  test('invalid requests and stale pre-request proposals cannot partially commit', () async {
    final c = swiss(':memory:');
    addTearDown(c.dispose);
    final old = await c.propose();
    final before = c.event!.encode(), count = c.repository.history().length;
    expect(() => c.avoidPair('p0', 'p0', true), throwsA(isA<TournamentException>()));
    expect(() => c.assignTeam(['p0', 'missing'], 'Partial'), throwsA(anything));
    expect(() => c.avoidPair('p0', 'missing', true), throwsA(anything));
    expect(c.repository.load()!.encode(), before);
    expect(c.repository.history().length, count);
    c.avoidPair('p0', 'p5', true);
    expect(() => c.post(old), throwsA(isA<TournamentException>()));
    expect(c.event!.games, isEmpty);
  });

  test('legacy records plus SQL-looking text remain literal in files and backups', () {
    final c = swiss(':memory:');
    addTearDown(c.dispose);
    const text = "Robert'); DROP TABLE player;-- é 家";
    c.assignTeam(['p0', 'p1'], text);
    c.savePlayer(c.event!.player('p0').copy(notes: text));
    c.repository.writePreference("key' OR 1=1;--", text);
    expect(c.repository.load()!.players, hasLength(10));
    expect(c.repository.load()!.player('p0').notes, text);
    expect(c.repository.load()!.player('p1').team, text);
    expect(c.repository.readPreference("key' OR 1=1;--"), text);
  });
}
