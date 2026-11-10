import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/event_repository.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/application/tournament_controller_core.dart'
    show backupFileStem, debugComputer;
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:path/path.dart' as p;

import '../support.dart';

/// An event file on a drive that has just been pulled out.
class _DriveGone extends SqliteEventRepository {
  _DriveGone() : super(':memory:');
  bool gone = false;

  @override
  Event commit(
    Event next, {
    required int expectedRevision,
    required String action,
  }) => gone
      ? throw const EventFileUnreachable()
      : super.commit(next, expectedRevision: expectedRevision, action: action);

  @override
  EventFileProblem? checkFile() => gone ? EventFileProblem.unreachable : null;
}

void main() {
  late Directory directory, backups;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('meow-backup-settings-');
    backups = Directory(p.join(directory.path, 'backups'))..createSync();
    debugComputer = 'laptop';
  });
  tearDown(() {
    debugComputer = null;
    directory.deleteSync(recursive: true);
  });

  List<String> copies() =>
      [for (final file in backups.listSync()) p.basename(file.path)]..sort();

  test('choosing a backup folder is not a step in the history', () {
    final c = fixture();
    addTearDown(c.dispose);
    final nodes = c.graph.nodes.length, undo = c.undoLabel;
    c.change('Set backup folder', c.event!.copy(backupFolder: backups.path));
    expect(c.event!.backupFolder, backups.path);
    expect(c.graph.nodes.length, nodes);
    expect(c.undoLabel, undo);
    // Still logged, and still a save.
    expect(c.repository.history().first['action'], 'Set backup folder');
    expect(c.repository.load()!.backupFolder, backups.path);
  });

  test('undo, redo and restore leave the backup folder and record alone', () {
    final c = fixture();
    addTearDown(c.dispose);
    final start = c.graph.head!;
    c.change('Rename', c.event!.copy(name: 'Before the folder'));
    c.change('Set backup folder', c.event!.copy(backupFolder: backups.path));
    c.secondaryBackup();
    final record = c.repository.readPreference('lastBackup');
    expect(record, isNotNull);
    c.change('Rename', c.event!.copy(name: 'After the folder'));
    c.undo();
    c.undo();
    expect(c.event!.name, 'Saturday Quads');
    expect(c.event!.backupFolder, backups.path);
    c.redo();
    expect(c.event!.backupFolder, backups.path);
    c.restore(start, acceptLosses: true);
    expect(c.event!.backupFolder, backups.path);
    expect(c.repository.load()!.backupFolder, backups.path);
    expect(c.repository.readPreference('lastBackup'), record);
    // Stopping backups is not undone by going back either.
    c.change('Stop folder backups', c.event!.copy(backupFolder: ''));
    c.redo();
    expect(c.event!.backupFolder, isEmpty);
  });

  test('copies are named for the event and never collide', () {
    final c = fixture();
    addTearDown(c.dispose);
    c.change(
      'Set up',
      c.event!.copy(
        name: 'Spring Open: Día 1 / "Final"?',
        backupFolder: backups.path,
      ),
    );
    c.secondaryBackup();
    c.secondaryBackup();
    c.secondaryBackup();
    expect(c.backupWarning, isNull);
    final names = copies();
    expect(names, hasLength(3));
    for (final name in names) {
      expect(
        name,
        startsWith('spring-open-dia-1-final-r${c.event!.revision}-'),
      );
      // Letters, digits, hyphens and one dot: valid on every file system.
      expect(
        RegExp(r'^[a-z0-9-]+\.meow$').hasMatch(name),
        isTrue,
        reason: name,
      );
    }
    expect(backupFileStem('李小龙杯'), 'event');
    expect(backupFileStem('CON'), 'con');
    expect(backupFileStem('  ...  '), 'event');
    expect(backupFileStem('x' * 200).length, 40);
  });

  test('a folder chosen on another computer is not used on this one', () {
    final path = p.join(directory.path, 'event.meow');
    var c = fixture(path: path);
    c.change('Set backup folder', c.event!.copy(backupFolder: backups.path));
    c.secondaryBackup();
    final record = c.repository.readPreference('lastBackup');
    expect(copies(), hasLength(1));
    c.dispose();

    // The file is carried to the second laptop.
    debugComputer = 'second laptop';
    c = TournamentController(SqliteEventRepository(path));
    expect(c.event!.backupFolder, isEmpty);
    expect(c.backupWarning, contains('chosen on another computer'));
    expect(c.backupWarning, contains(backups.path));
    expect(c.repository.readPreference('lastBackup'), isNull);
    c.secondaryBackup();
    expect(copies(), hasLength(1));
    final theirs = Directory(p.join(directory.path, 'theirs'))..createSync();
    c.change('Set backup folder', c.event!.copy(backupFolder: theirs.path));
    c.secondaryBackup();
    expect(theirs.listSync(), hasLength(1));
    c.dispose();

    // And back: the first laptop's folder and last copy are its own again.
    debugComputer = 'laptop';
    c = TournamentController(SqliteEventRepository(path));
    addTearDown(c.dispose);
    expect(c.event!.backupFolder, backups.path);
    expect(c.backupWarning, isNull);
    expect(c.repository.readPreference('lastBackup'), record);
    c.secondaryBackup();
    expect(copies(), hasLength(2));
    expect(theirs.listSync(), hasLength(1));
  });

  test('a path that is not a folder here is never written to', () {
    final path = p.join(directory.path, 'event.meow');
    final foreign = Platform.isWindows
        ? '/home/td/backups'
        : r'C:\Users\TD\Backups';
    // Saved before backups were tied to a computer, on the other system.
    final repository = SqliteEventRepository(path);
    final made = repository.commit(
      Event(
        id: 'e',
        name: 'Carried',
        date: '2026-11-10',
        backupFolder: foreign,
      ),
      expectedRevision: 0,
      action: 'Create event',
    );
    repository.writePreference(
      'lastBackup',
      '${made.revision}|$foreign/x|2026',
    );
    repository.close();
    final before = Directory.current.listSync().length;
    final c = TournamentController(SqliteEventRepository(path));
    addTearDown(c.dispose);
    expect(c.event!.backupFolder, isEmpty);
    expect(c.backupWarning, contains('another computer'));
    expect(c.repository.readPreference('lastBackup'), isNull);
    c.secondaryBackup();
    expect(Directory.current.listSync().length, before);
    // Nor through the repository, should a relative name ever reach it.
    expect(
      () => c.repository.backup('relative.meow'),
      throwsA(isA<TournamentException>()),
    );
    expect(File('relative.meow').existsSync(), isFalse);
  });

  test('a drive that has gone is said plainly and shown until fixed', () {
    final repository = _DriveGone();
    final c = TournamentController(repository);
    addTearDown(c.dispose);
    c.create('On a USB stick');
    var notified = 0;
    c.addListener(() => notified++);
    repository.gone = true;
    expect(
      () => c.change('Rename', c.event!.copy(name: 'Lost?')),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          allOf(contains('can no longer be reached'), contains('save a copy')),
        ),
      ),
    );
    expect(c.event!.name, 'On a USB stick');
    expect(c.fileProblem, EventFileProblem.unreachable);
    expect(c.fileWarning, contains('changes are not being saved'));
    expect(notified, greaterThan(0));
  });
}
