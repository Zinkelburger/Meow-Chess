import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/diagnostics.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import '../support.dart';

void main() {
  late Directory directory;
  late List<String> diagnostics;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('meow-event-file-');
    diagnostics = [];
    Diagnostics.sink = diagnostics.add;
  });
  tearDown(() {
    Diagnostics.sink = null;
    if (!Platform.isWindows) Process.runSync('chmod', ['755', directory.path]);
    directory.deleteSync(recursive: true);
  });

  /// Opens [copy] (just the .meow, no recovery files) and returns its revision.
  int? revisionOf(String copy) {
    final repository = SqliteEventRepository(copy);
    try {
      return repository.load()?.revision;
    } finally {
      repository.close();
    }
  }

  String copyMainFile(String source) {
    final elsewhere = Directory(p.join(directory.path, 'copy'))..createSync();
    return File(source).copySync(p.join(elsewhere.path, 'copy.meow')).path;
  }

  /// Leaves [folder] read-only; false where permissions are not enforced.
  bool lockDown(Directory folder) {
    if (Platform.isWindows) return false;
    Process.runSync('chmod', ['555', folder.path]);
    try {
      File(p.join(folder.path, 'probe')).writeAsStringSync('');
      return false;
    } on FileSystemException {
      return true;
    }
  }

  /// A valid event whose on-disk journal is a rollback journal, as saved
  /// where WAL was refused.
  String rollbackEvent() {
    final path = p.join(directory.path, 'event.meow');
    fixture(path: path).dispose();
    sqlite3.open(path)
      ..execute('PRAGMA journal_mode = DELETE')
      ..close();
    return path;
  }

  test('each commit reaches the .meow itself while the event is open', () {
    final source = p.join(directory.path, 'event.meow');
    final c = fixture(path: source);
    c.change('Rename', c.event!.copy(name: 'Spring Open'));
    final revision = c.event!.revision;
    // A director copying only the .meow while the app still runs.
    final copy = copyMainFile(source);
    c.dispose();
    expect(revisionOf(copy), revision);
  });

  test('closing folds the recovery file into the .meow', () {
    final source = p.join(directory.path, 'event.meow');
    final c = fixture(path: source);
    c.change('Rename', c.event!.copy(name: 'Spring Open'));
    final revision = c.event!.revision;
    expect(c.repository is SqliteEventRepository, isTrue);
    expect((c.repository as SqliteEventRepository).crashProtected, isTrue);
    c.dispose();
    final wal = File('$source-wal');
    expect(!wal.existsSync() || wal.lengthSync() == 0, isTrue);
    expect(revisionOf(copyMainFile(source)), revision);
  });

  test('a refused recovery file falls back and says protection is off', () {
    final path = rollbackEvent();
    if (!lockDown(directory)) {
      markTestSkipped('Folder permissions are not enforced here.');
      return;
    }
    final repository = SqliteEventRepository(path);
    addTearDown(repository.close);
    expect(repository.crashProtected, isFalse);
    expect(
      diagnostics.where((d) => d.contains('crash protection unavailable')),
      hasLength(1),
    );
    final event = repository.load()!;
    repository.commit(
      event.copy(name: 'Renamed'),
      expectedRevision: event.revision,
      action: 'Rename',
    );
    expect(repository.load()!.name, 'Renamed');
  });

  test('another program holding the file is reported, not worked around', () {
    final path = rollbackEvent();
    final reader = sqlite3.open(path)
      ..execute('BEGIN')
      ..select('SELECT count(*) FROM event');
    addTearDown(reader.close);
    expect(
      () => SqliteEventRepository(path),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('open in another window or program'),
        ),
      ),
    );
    expect(
      diagnostics.where((d) => d.contains('crash protection unavailable')),
      isEmpty,
    );
    expect(File(path).existsSync(), isTrue);
  });

  test(
    'a WAL event in a folder that refuses its recovery file is explained',
    () {
      final path = p.join(directory.path, 'event.meow');
      fixture(path: path).dispose();
      final bytes = File(path).readAsBytesSync();
      if (!lockDown(directory)) {
        markTestSkipped('Folder permissions are not enforced here.');
        return;
      }
      expect(
        () => SqliteEventRepository(path),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'message',
            contains('recovery file'),
          ),
        ),
      );
      expect(File(path).readAsBytesSync(), bytes);
    },
  );

  test('a new event in a read-only folder is explained and leaves no file', () {
    if (!lockDown(directory)) {
      markTestSkipped('Folder permissions are not enforced here.');
      return;
    }
    final path = p.join(directory.path, 'new.meow');
    expect(
      () => SqliteEventRepository(path),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('cannot create a file in this folder'),
        ),
      ),
    );
    expect(File(path).existsSync(), isFalse);
  });
}
