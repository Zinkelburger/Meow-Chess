import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/history.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/workspace_actions.dart';
import '../support.dart';

TournamentController blank() {
  final c = TournamentController(SqliteEventRepository(':memory:'));
  c.create('History');
  c.importPlayers([Player(id: 'a', name: 'Ann')]);
  return c;
}

void note(TournamentController c, String text) =>
    c.savePlayer(c.event!.player('a').copy(notes: text));

void main() {
  test('going back and changing something keeps the old line as a branch', () {
    final c = blank();
    addTearDown(c.dispose);
    final start = c.graph.head!;
    note(c, 'B');
    note(c, 'C');
    final c3 = c.graph.head!;
    c.undo();
    c.undo();
    note(c, 'D');
    expect(c.event!.player('a').notes, 'D');
    final graph = c.graph;
    expect(graph.nodes[graph.head]!.parent, start);
    expect(graph.children[start], hasLength(2));
    expect(graph.style(c3), NodeStyle.branch);
    c.restore(c3);
    expect(c.event!.player('a').notes, 'C');
    expect(c.graph.head, c3);
  });

  test('forward follows the line most recently visited', () {
    final c = blank();
    addTearDown(c.dispose);
    note(c, 'B');
    final b = c.graph.head!;
    c.undo();
    note(c, 'D');
    final d = c.graph.head!;
    c.undo();
    expect(c.graph.forward, d);
    expect(c.redoLabel, 'Edit Ann');
    c.restore(b);
    c.undo();
    expect(c.graph.forward, b);
    c.redo();
    expect(c.event!.player('a').notes, 'B');
    expect(c.canRedo, false);
  });

  test('redoing a step by hand returns to its node instead of a twin', () {
    final c = blank();
    addTearDown(c.dispose);
    note(c, 'B');
    final b = c.graph.head!, count = c.graph.nodes.length;
    c.undo();
    note(c, 'B');
    expect(c.graph.head, b);
    expect(c.graph.nodes.length, count);
  });

  test('moves advance the revision and are written to the activity log', () {
    final c = blank();
    addTearDown(c.dispose);
    note(c, 'B');
    final revision = c.event!.revision;
    c.undo();
    c.redo();
    expect(c.event!.revision, revision + 2);
    expect(c.repository.history().take(2).map((h) => h['action']), [
      'Redo Edit Ann',
      'Undo Edit Ann',
    ]);
    expect(c.repository.load()!.encode(), c.event!.encode());
  });

  test('one result undoes freely; rolling back more play asks first', () async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post(await c.propose());
    final paired = c.graph.head!;
    final games = c.event!.games.toList();
    c.recordResult(games[0].id, Outcome.whiteWin);
    c.recordResult(games[1].id, Outcome.draw);
    expect(c.lossesTo(c.graph.back!), isEmpty);
    expect(c.lossesTo(paired), ['Quad 1 round 1: 2 results']);
    final before = c.event!.encode();
    expect(() => c.restore(paired), throwsA(isA<TournamentException>()));
    expect(c.event!.encode(), before);
    c.restore(paired, acceptLosses: true);
    expect(c.event!.games.every((g) => g.outcome == Outcome.unreported), true);
    // Nothing is lost for good: forward returns to the results.
    expect(c.lossesTo(c.graph.forward!), isEmpty);
    c.redo();
    c.redo();
    expect(c.event!.games.take(2).map((g) => g.outcome), [
      Outcome.whiteWin,
      Outcome.draw,
    ]);
  });

  test('undoing a round start warns, and redo brings the start back', () async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post(await c.propose());
    c.startRound(c.event!.sections.first.id);
    final started = c.event!.sections.first.rounds.single.startedAt;
    expect(c.lossesTo(c.graph.back!), ['Quad 1 round 1: the round start']);
    c.undo(acceptLosses: true);
    expect(c.event!.sections.first.rounds.single.startedAt, isNull);
    c.redo();
    expect(c.event!.sections.first.rounds.single.startedAt, started);
  });

  test('removing a played round is always a warning', () async {
    final c = fixture();
    addTearDown(c.dispose);
    final unpaired = c.graph.head!;
    c.post(await c.propose());
    c.recordResult(c.event!.games.first.id, Outcome.blackWin);
    expect(c.lossesTo(unpaired), [
      'Quad 1 round 1: the round is removed, 1 result',
    ]);
  });

  test('a practice copy cannot go back to before it was copied', () async {
    final dir = Directory.systemTemp.createTempSync('meow-history-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final real = fixture(path: p.join(dir.path, 'real.meow'));
    final copyPath = p.join(dir.path, 'copy.meow');
    real.repository.backup(copyPath);
    real.dispose();
    await markPracticeCopy(copyPath);
    final copy = TournamentController(SqliteEventRepository(copyPath));
    addTearDown(copy.dispose);
    expect(copy.undo, throwsA(isA<TournamentException>()));
    expect(copy.event!.practice, true);
  });

  test('graph keeps the current line in lane 0 with branches beside it', () {
    final c = blank();
    addTearDown(c.dispose);
    final fork = c.graph.head!;
    note(c, 'side 1');
    note(c, 'side 2');
    c.restore(fork);
    note(c, 'main');
    final rows = c.graph.rows;
    expect(rows.map((r) => r.node.id), [
      for (final id in c.graph.nodes.keys.toList()..sort((a, b) => b - a)) id,
    ]);
    final main = rows.first,
        forkRow = rows.firstWhere((r) => r.node.id == fork);
    expect(main.lane, 0);
    expect(main.top.whereType<int>(), isEmpty);
    final side = rows.where(
      (r) => c.graph.style(r.node.id) == NodeStyle.branch,
    );
    expect(side.map((r) => r.lane), everyElement(1));
    expect(forkRow.lane, 0);
    expect(forkRow.merges, [1]);
  });

  test('changes are described in plain language', () async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post(await c.propose());
    final before = c.event!;
    final g = before.games.first;
    c.recordResult(g.id, Outcome.draw);
    final changes = describeChanges(before, c.event!);
    expect(changes, hasLength(1));
    expect(changes.single, contains('board ${g.board}'));
    expect(changes.single, contains('— → ½–½'));
    expect(describeChanges(before, before.copy(name: 'Sunday Quads')), [
      'Event name: “Saturday Quads” → “Sunday Quads”',
    ]);
  });

  test('the graph and its forward line survive reopening', () {
    final dir = Directory.systemTemp.createTempSync('meow-history-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = p.join(dir.path, 'e.meow');
    var c = TournamentController(SqliteEventRepository(path));
    c.create('History');
    c.importPlayers([Player(id: 'a', name: 'Ann')]);
    note(c, 'B');
    c.undo();
    final head = c.graph.head, forward = c.graph.forward;
    c.dispose();
    c = TournamentController(SqliteEventRepository(path));
    addTearDown(c.dispose);
    expect(c.graph.head, head);
    expect(c.graph.forward, forward);
    c.redo();
    expect(c.event!.player('a').notes, 'B');
  });

  test('a version 1 file starts its graph from its current state', () {
    final dir = Directory.systemTemp.createTempSync('meow-history-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = p.join(dir.path, 'old.meow');
    final c = TournamentController(SqliteEventRepository(path));
    c.create('Old');
    c.importPlayers([Player(id: 'a', name: 'Ann')]);
    final expected = c.event!.encode();
    c.dispose();
    // Rebuild the version 1 audit table, which had no graph.
    final db = sqlite3.open(path);
    db.execute('''DROP INDEX audit_node;
CREATE TABLE audit1 (id INTEGER PRIMARY KEY, revision INTEGER NOT NULL, action TEXT NOT NULL, timestamp TEXT NOT NULL, before_state TEXT, undone INTEGER NOT NULL DEFAULT 0);
INSERT INTO audit1(revision,action,timestamp) SELECT revision,action,timestamp FROM audit;
DROP TABLE audit; ALTER TABLE audit1 RENAME TO audit; DROP TABLE node;
PRAGMA user_version = 1;''');
    db.close();
    final migrated = TournamentController(SqliteEventRepository(path));
    addTearDown(migrated.dispose);
    expect(migrated.event!.encode(), expected);
    expect(migrated.graph.nodes.values.single.action, 'Earlier changes');
    expect(migrated.canUndo, false);
    note(migrated, 'new');
    migrated.undo();
    expect(migrated.event!.encode(), isNot(expected)); // revision advanced
    expect(migrated.event!.player('a').notes, isEmpty);
    expect(
      migrated.repository.history().map((h) => h['action']),
      containsAll(['Create event', 'Start history graph']),
    );
  });
}
