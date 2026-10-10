import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/diagnostics.dart';
import 'package:meow_chess/application/tournament_controller_core.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:path/path.dart' as p;

import '../support.dart';

List<String> captureDiagnostics() {
  final lines = <String>[], previous = Diagnostics.sink;
  Diagnostics.sink = lines.add;
  addTearDown(() => Diagnostics.sink = previous);
  return lines;
}

void main() {
  test('an owner may release the event file early and still dispose', () {
    final c = fixture(count: 4);
    c.releaseResources();
    // A second release must not close the file or the drafts twice.
    expect(c.releaseResources, returnsNormally);
    expect(c.dispose, returnsNormally);
  });

  test('a failing listener cannot turn a committed save into a failure', () {
    final c = TournamentControllerCore(SqliteEventRepository(':memory:'));
    addTearDown(c.dispose);
    c.create('Listener check');
    final revision = c.event!.revision;
    var later = 0;
    c.addListener(() => throw StateError('listener broke'));
    c.addListener(() => later++);
    final lines = captureDiagnostics();
    // A CLI or MCP caller sees the command succeed, as the save did.
    c.change('Rename', c.event!.copy(name: 'Renamed'));
    expect(c.event!.revision, revision + 1);
    expect(c.repository.load()!.name, 'Renamed');
    expect(later, 1);
    expect(lines.where((l) => l.contains('save event — failed')), isEmpty);
    expect(
      lines.where((l) => l.contains('save event — succeeded')),
      hasLength(1),
    );
    final failure = lines.singleWhere(
      (l) => l.contains('notify listeners — failed'),
    );
    expect(failure, contains('notifier: TournamentControllerCore'));
    expect(failure, contains('Error: Bad state: listener broke'));
    // History moves notify the same way.
    c.undo();
    expect(c.repository.load()!.name, 'Listener check');
    expect(later, 2);
  });

  test('a failed backup copy is recorded in diagnostics', () {
    final directory = Directory.systemTemp.createTempSync('meow-backup');
    addTearDown(() => directory.deleteSync(recursive: true));
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final notDirectory = File(p.join(directory.path, 'ordinary-file'))
      ..writeAsStringSync('keep');
    c.change('Backup config', c.event!.copy(backupFolder: notDirectory.path));
    final lines = captureDiagnostics();
    c.secondaryBackup();
    expect(c.backupWarning, contains('Saved to the event file'));
    expect(lines.single, contains('secondary backup — failed'));
    expect(lines.single, contains('revision: ${c.event!.revision}'));
  });

  test('a section removed meanwhile refuses drawing lots', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    expect(
      () => c.drawLots('gone'),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          'That section no longer exists.',
        ),
      ),
    );
  });

  test('a move records its own copy of the moved players', () {
    final c = fixture(count: 8);
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    final ids = [q1.players.last];
    c.movePlayers(ids, q2.id);
    ids.add('later edit');
    expect(c.event!.transitions.last['players'], [q1.players.last]);
  });

  test('a closed event refuses to compare history and keeps its drafts', () {
    final c = fixture(count: 4);
    c.savePlayer(c.event!.players.first.copy(rating: 1600));
    final back = c.graph.back!;
    c.workspaceState.write('draft', 'unsaved');
    c.releaseResources();
    expect(
      () => c.lossesTo(back),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          'This event has closed.',
        ),
      ),
    );
    // The file is closed: drafts held in memory still read, others are absent.
    expect(c.workspaceState.read('draft'), 'unsaved');
    expect(c.workspaceState.read('never written'), isNull);
    expect(c.workspaceState.readMap('never written'), isEmpty);
    c.dispose();
  });

  test('a closed event refuses an unread history graph plainly', () {
    final c = fixture(count: 4);
    c.releaseResources();
    // Nothing read the graph before the file closed, so there is none to show.
    expect(
      () => c.graph,
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          'This event has closed.',
        ),
      ),
    );
    expect(() => c.canUndo, throwsA(isA<TournamentException>()));
    c.dispose();
  });

  test('a closed event still shows the history it had read', () {
    final c = fixture(count: 4);
    c.savePlayer(c.event!.players.first.copy(rating: 1600));
    expect(c.canUndo, isTrue);
    final graph = c.graph;
    c.releaseResources();
    expect(c.graph, same(graph));
    expect(c.undoLabel, 'Edit Player 00');
    c.dispose();
  });

  test('a new section name matching one with stray spaces is refused', () {
    final c = fixture(count: 8);
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    c.change(
      'Spaced name',
      c.event!.copy(
        sections: [
          q1.copy(name: ' Open '),
          q2,
        ],
      ),
    );
    final revision = c.event!.revision;
    expect(
      () => c.createSections(const [], format: Format.swiss, name: 'open'),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          'There is already a section called open.',
        ),
      ),
    );
    expect(c.event!.revision, revision);
  });
}
