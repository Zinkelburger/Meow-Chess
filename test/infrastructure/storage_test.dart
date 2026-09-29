import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import '../support.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('meow-storage-'));
  tearDown(() => directory.deleteSync(recursive: true));
  test(
    'reopen and SQLite backup preserve exactly their committed revision',
    () async {
      final source = p.join(directory.path, 'event.meow'),
          copy = p.join(directory.path, 'backup.meow');
      final c = fixture(path: source);
      c.post(await c.propose());
      final game = c.event!.games.first.id;
      c.recordResult(game, Outcome.whiteWin);
      final expected = c.event!.encode();
      c.repository.backup(copy);
      c.recordResult(game, Outcome.draw);
      c.dispose();
      final backup = SqliteEventRepository(copy);
      expect(backup.load()!.encode(), expected);
      backup.close();
      final reopened = SqliteEventRepository(source);
      expect(reopened.load()!.games.first.outcome, Outcome.draw);
      reopened.close();
    },
  );
  test(
    'stale write and invalid mutation leave state and history untouched',
    () {
      final c = fixture(path: p.join(directory.path, 'event.meow'));
      addTearDown(c.dispose);
      final before = c.event!, count = c.repository.history().length;
      expect(
        () => c.repository.commit(
          before.copy(name: 'Wrong'),
          expectedRevision: 0,
          action: 'Stale',
        ),
        throwsA(isA<TournamentException>()),
      );
      expect(
        () => c.repository.commit(
          before.copy(players: [...before.players, before.players.first]),
          expectedRevision: before.revision,
          action: 'Invalid',
        ),
        throwsA(isA<TournamentException>()),
      );
      expect(c.repository.load()!.encode(), before.encode());
      expect(c.repository.history().length, count);
    },
  );
  test('second connection cannot acquire ownership of an open event', () {
    final path = p.join(directory.path, 'event.meow');
    final c = fixture(path: path);
    addTearDown(c.dispose);
    expect(() => SqliteEventRepository(path), throwsA(isA<SqliteException>()));
  });
  test('failed backup preserves local results and exposes failure', () {
    final c = fixture(path: p.join(directory.path, 'event.meow'));
    addTearDown(c.dispose);
    final notDirectory = File(p.join(directory.path, 'ordinary-file'))
      ..writeAsStringSync('keep');
    c.change('Backup config', c.event!.copy(backupFolder: notDirectory.path));
    c.secondaryBackup();
    expect(c.backupWarning, contains('Saved locally'));
    expect(notDirectory.readAsStringSync(), 'keep');
    expect(c.repository.load()!.players.length, 8);
  });
  test(
    'opening an unrelated SQLite file refuses without changing its schema or bytes',
    () {
      final path = p.join(directory.path, 'unrelated.meow');
      final db = sqlite3.open(path);
      db.execute('CREATE TABLE unrelated (value TEXT)');
      db.execute("INSERT INTO unrelated VALUES('preserve me')");
      db.close();
      final original = File(path).readAsBytesSync();
      expect(
        () => SqliteEventRepository(path),
        throwsA(isA<TournamentException>()),
      );
      expect(File(path).readAsBytesSync(), original);
      final check = sqlite3.open(path);
      expect(
        check
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => r['name']),
        ['unrelated'],
      );
      check.close();
    },
  );
  test('future schema is refused without rewriting it', () {
    final path = p.join(directory.path, 'future.meow');
    final db = sqlite3.open(path);
    db.execute('PRAGMA user_version=999');
    db.close();
    expect(
      () => SqliteEventRepository(path),
      throwsA(isA<TournamentException>()),
    );
    final check = sqlite3.open(path);
    expect(check.select('PRAGMA user_version').first.values.first, 999);
    check.close();
  });
  test('preferences and interrupted drafts survive reopening', () {
    final path = p.join(directory.path, 'draft.meow');
    final c = fixture(path: path);
    c.repository.writePreference('player-draft-new', '{"name":"Half typed"}');
    c.dispose();
    final reopened = SqliteEventRepository(path);
    expect(reopened.readPreference('player-draft-new'), contains('Half typed'));
    reopened.close();
  });
  test(
    'mid-transaction SQL failure rolls back every affected table and audit row',
    () async {
      final path = p.join(directory.path, 'fault.meow');
      final c = fixture(path: path);
      c.post(await c.propose());
      final before = c.event!;
      c.dispose();
      final inject = sqlite3.open(path);
      inject.execute(
        r"CREATE TRIGGER fail_result BEFORE INSERT ON game WHEN json_extract(NEW.data, '$.outcome') = 'whiteWin' BEGIN SELECT RAISE(ABORT, 'injected write failure'); END",
      );
      inject.close();
      final repository = SqliteEventRepository(path);
      try {
        final first = before.sections.first;
        final round = first.rounds.first;
        final after = before.copy(
          sections: [
            first.copy(
              rounds: [
                round.copy(
                  games: [
                    round.games.first.copy(outcome: Outcome.whiteWin),
                    ...round.games.skip(1),
                  ],
                ),
              ],
            ),
            ...before.sections.skip(1),
          ],
        );
        expect(
          () => repository.commit(
            after,
            expectedRevision: before.revision,
            action: 'Fault',
          ),
          throwsA(isA<SqliteException>()),
        );
        expect(repository.load()!.encode(), before.encode());
        expect(
          repository.history().any((row) => row['action'] == 'Fault'),
          false,
        );
      } finally {
        repository.close();
      }
    },
  );
  test('undo cannot erase the fact that a round has started', () async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post(await c.propose());
    c.startRound(c.event!.sections.first.id);
    c.undo();
    expect(c.event!.sections.first.rounds.first.startedAt, isNotNull);
    expect(c.undo, throwsA(isA<TournamentException>()));
  });
}
