import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/event_repository.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../support.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('meow-safety-'));
  tearDown(() => directory.deleteSync(recursive: true));

  Event opened(String path) {
    final repository = SqliteEventRepository(path);
    try {
      return repository.load()!;
    } finally {
      repository.close();
    }
  }

  String integrity(String path) {
    final db = sqlite3.open(path);
    try {
      return db.select('PRAGMA integrity_check').first.values.first as String;
    } finally {
      db.close();
    }
  }

  test('a backup copied over the event after a crash opens as the backup', () {
    final path = p.join(directory.path, 'event.meow');
    final c = fixture(path: path);
    addTearDown(c.dispose);
    final backup = p.join(directory.path, 'backup.meow');
    c.repository.backup(backup);
    final kept = c.event!;
    for (var i = 0; i < 5; i++) {
      c.change('Rename $i', c.event!.copy(name: 'Later name $i'));
    }
    c.workspaceState.write('draft', 'typed after the last save');
    // The power goes: the event is never closed, so its recovery file stays
    // beside it exactly as it lies now.
    final crashed = Directory(p.join(directory.path, 'crashed'))..createSync();
    final wal = File('$path-wal');
    expect(wal.existsSync(), isTrue);
    expect(wal.lengthSync(), 0, reason: 'nothing left to replay');
    wal.copySync(p.join(crashed.path, 'event.meow-wal'));
    // The director restores the backup under the event's name.
    final restored = File(backup).copySync(p.join(crashed.path, 'event.meow'));
    final event = opened(restored.path);
    expect(event.name, kept.name);
    expect(event.revision, kept.revision);
    expect(integrity(restored.path), 'ok');
  });

  test('emptying the recovery file after each save costs little', () {
    // The same connection settings as an event, with and without the
    // checkpoint that follows each save.
    double millisecondsPerSave({required bool truncate}) {
      final db = sqlite3.open(
        p.join(directory.path, truncate ? 'truncate.db' : 'plain.db'),
      );
      try {
        db
          ..execute('PRAGMA locking_mode = EXCLUSIVE')
          ..execute('PRAGMA journal_mode = WAL')
          ..execute('PRAGMA synchronous = FULL')
          ..execute(
            'CREATE TABLE preference (key TEXT PRIMARY KEY, value TEXT)',
          );
        final clock = Stopwatch()..start();
        for (var i = 0; i < 200; i++) {
          db.execute(
            'INSERT INTO preference VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
            ['draft', 'value $i' * 20],
          );
          if (truncate) db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        }
        return clock.elapsedMicroseconds / 200 / 1000;
      } finally {
        db.close();
      }
    }

    final plain = millisecondsPerSave(truncate: false);
    final truncated = millisecondsPerSave(truncate: true);
    // ignore: avoid_print
    print(
      'CHECKPOINT: a small save takes ${plain.toStringAsFixed(2)} ms left in '
      'the recovery file, ${truncated.toStringAsFixed(2)} ms with the '
      'recovery file emptied after it',
    );
    expect(truncated, lessThan(50));
  });

  test('a preference can be forgotten', () {
    final c = fixture(path: p.join(directory.path, 'event.meow'));
    addTearDown(c.dispose);
    c.repository.writePreference('lastBackup', '1|/x|2026');
    c.repository.deletePreference('lastBackup');
    expect(c.repository.readPreference('lastBackup'), isNull);
    expect(File('${p.join(directory.path, 'event.meow')}-wal').lengthSync(), 0);
  });

  group('file format version', () {
    /// An event as release 1.4.0 saved it: the same tables, version 2.
    String version2() {
      final path = p.join(directory.path, 'saved-by-1.4.0.meow');
      final c = fixture(path: path);
      c.change('Rename', c.event!.copy(name: 'Spring Open'));
      c.dispose();
      sqlite3.open(path)
        ..execute('PRAGMA user_version = 2')
        ..close();
      return path;
    }

    int versionOf(String path) {
      final db = sqlite3.open(path);
      try {
        return db.select('PRAGMA user_version').first.values.first as int;
      } finally {
        db.close();
      }
    }

    test('a version 2 event opens, keeps its history and moves up', () {
      final path = version2();
      final c = TournamentController(SqliteEventRepository(path));
      expect(c.event!.name, 'Spring Open');
      expect(c.event!.players, hasLength(8));
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.event!.name, 'Saturday Quads');
      c.dispose();
      // Higher than any release up to 1.4.0 accepts, so none of them can
      // open it and save it back without what they do not know.
      expect(versionOf(path), SqliteEventRepository.schemaVersion);
      expect(SqliteEventRepository.schemaVersion, greaterThan(2));
    });

    test('an event from a newer version is refused in plain words', () {
      final path = version2();
      sqlite3.open(path)
        ..execute(
          'PRAGMA user_version = ${SqliteEventRepository.schemaVersion + 1}',
        )
        ..close();
      final bytes = File(path).readAsBytesSync();
      for (final open in [
        () => SqliteEventRepository(path).close(),
        () => SqliteEventRepository.peek(path),
      ]) {
        expect(
          open,
          throwsA(
            isA<TournamentException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('newer version of Meow Chess'),
                contains('Update this copy'),
              ),
            ),
          ),
        );
      }
      expect(File(path).readAsBytesSync(), bytes);
    });

    test('looking at an event neither changes nor creates a file', () {
      final path = version2();
      final bytes = File(path).readAsBytesSync();
      expect(SqliteEventRepository.peek(path)!.name, 'Spring Open');
      expect(File(path).readAsBytesSync(), bytes);
      expect(versionOf(path), 2);
      expect(directory.listSync().map((f) => p.basename(f.path)), [
        'saved-by-1.4.0.meow',
      ]);
      final missing = p.join(directory.path, 'gone.meow');
      expect(SqliteEventRepository.peek(missing), isNull);
      expect(File(missing).existsSync(), isFalse);
    });

    test('an open event is looked at without a second handle on it', () {
      final path = p.join(directory.path, 'open.meow');
      final c = fixture(path: path);
      addTearDown(c.dispose);
      expect(SqliteEventRepository.peek(path)!.encode(), c.event!.encode());
      // Still the owner: a second opener is refused as before.
      expect(
        () => SqliteEventRepository(path),
        throwsA(isA<TournamentException>()),
      );
    });

    test('opening an event already in this format does not rewrite it', () {
      final path = p.join(directory.path, 'current.meow');
      fixture(path: path).dispose();
      final bytes = File(path).readAsBytesSync();
      opened(path);
      expect(File(path).readAsBytesSync(), bytes);
    });
  });

  group('an event file that goes away while open', () {
    test('a moved or deleted file is noticed, and a copy keeps the work', () {
      final path = p.join(directory.path, 'event.meow');
      final c = fixture(path: path);
      addTearDown(c.dispose);
      var notified = 0;
      c.addListener(() => notified++);
      c.checkFile();
      expect(c.fileProblem, isNull);
      expect(notified, 0);
      if (Platform.isWindows) {
        markTestSkipped('Windows refuses to move a file SQLite has open.');
        return;
      }
      // Cut and pasted to another drive: copied there, deleted here.
      final elsewhere = File(path).copySync(p.join(directory.path, 'usb.meow'));
      File(path).deleteSync();
      c.checkFile();
      expect(c.fileProblem, EventFileProblem.moved);
      expect(c.fileWarning, contains('Save a copy'));
      expect(notified, 1);
      // Work goes on, and is only in the open event.
      c.change('Rename', c.event!.copy(name: 'Entered after the move'));
      expect(opened(elsewhere.path).name, 'Saturday Quads');
      final copy = p.join(directory.path, 'rescued.meow');
      c.repository.backup(copy);
      expect(opened(copy).name, 'Entered after the move');
    });

    test('another file taking the name is not mistaken for the event', () {
      if (Platform.isWindows) {
        markTestSkipped('Windows refuses to replace a file SQLite has open.');
        return;
      }
      final path = p.join(directory.path, 'event.meow');
      final c = fixture(path: path);
      addTearDown(c.dispose);
      // A sync client delivers its own version by renaming it into place.
      final theirs = File(p.join(directory.path, 'incoming'))
        ..writeAsBytesSync(File(path).readAsBytesSync());
      theirs.renameSync(path);
      expect(c.repository.checkFile(), EventFileProblem.moved);
    });

    test('a file whose folder has gone is reported as unreachable', () {
      if (Platform.isWindows) {
        markTestSkipped(
          'Windows refuses to remove a folder with an open file.',
        );
        return;
      }
      final folder = Directory(p.join(directory.path, 'usb'))..createSync();
      final c = fixture(path: p.join(folder.path, 'event.meow'));
      addTearDown(c.dispose);
      folder.deleteSync(recursive: true);
      c.checkFile();
      expect(c.fileProblem, EventFileProblem.unreachable);
      expect(c.fileWarning, contains('can no longer be reached'));
    });

    test('a copy is still made when the event file cannot be read', () {
      final path = p.join(directory.path, 'event.meow');
      final c = fixture(path: path);
      addTearDown(c.dispose);
      // Enough history that most of the file is not held in memory.
      final random = Random(7);
      for (var i = 0; i < 6; i++) {
        c.change(
          'Notes $i',
          c.event!.copy(
            notes: String.fromCharCodes([
              for (var n = 0; n < 700000; n++) 33 + random.nextInt(90),
            ]),
          ),
        );
      }
      c.change('Rename', c.event!.copy(name: 'Last saved', notes: ''));
      final last = c.event!;
      // The drive fails: what was the event file is now unreadable.
      File(path).writeAsBytesSync(List.filled(8192, 0x55));
      final copy = p.join(directory.path, 'rescued.meow');
      c.repository.backup(copy);
      final rescued = opened(copy);
      expect(rescued.encode(), last.encode());
      expect(integrity(copy), 'ok');
      final repository = SqliteEventRepository(copy);
      addTearDown(repository.close);
      expect(
        repository.history().map((row) => row['action']),
        contains('Copy saved without earlier history'),
      );
    });
  });
}
