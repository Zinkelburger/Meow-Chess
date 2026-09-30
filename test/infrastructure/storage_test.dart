import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/workspace_actions.dart';
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
    expect(
      () => SqliteEventRepository(path),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('open in another window'),
        ),
      ),
    );
    // The refused opener must not disturb the owner.
    c.savePlayer(c.event!.players.first.copy(notes: 'Still writable'));
    expect(c.repository.load()!.players.first.notes, 'Still writable');
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
    final started = c.event!.encode(), audit = c.repository.history().length;
    // Refused unless the TD confirms removing the start; see history_test.
    expect(c.undo, throwsA(isA<TournamentException>()));
    expect(c.event!.encode(), started);
    expect(c.repository.load()!.encode(), started);
    expect(c.repository.history().length, audit);
  });

  test(
    'a transaction SQLite already rolled back reports its own cause',
    () async {
      final path = p.join(directory.path, 'auto-rollback.meow');
      final c = fixture(path: path);
      c.post(await c.propose());
      final before = c.event!;
      c.dispose();
      final inject = sqlite3.open(path);
      // RAISE(ROLLBACK) ends the transaction inside SQLite, as a full disk can.
      inject.execute(
        r"CREATE TRIGGER lose_txn BEFORE INSERT ON game WHEN json_extract(NEW.data, '$.outcome') = 'draw' BEGIN SELECT RAISE(ROLLBACK, 'injected rollback'); END",
      );
      inject.close();
      final reopened = TournamentController(SqliteEventRepository(path));
      addTearDown(reopened.dispose);
      expect(
        () => reopened.recordResult(before.games.first.id, Outcome.draw),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            contains('injected rollback'),
          ),
        ),
      );
      expect(reopened.repository.load()!.encode(), before.encode());
      // The connection is still usable after the failed command.
      reopened.recordResult(before.games.first.id, Outcome.whiteWin);
      expect(reopened.event!.revision, before.revision + 1);
    },
  );
  test('backups publish complete files only and never overwrite', () {
    final c = fixture(path: p.join(directory.path, 'event.meow'));
    addTearDown(c.dispose);
    final target = p.join(directory.path, 'copies', 'nested', 'copy.meow');
    c.repository.backup(target);
    final bytes = File(target).readAsBytesSync();
    expect(
      () => c.repository.backup(target),
      throwsA(isA<TournamentException>()),
    );
    expect(File(target).readAsBytesSync(), bytes);
    final leftovers = Directory(
      p.dirname(target),
    ).listSync().map((f) => p.basename(f.path));
    expect(leftovers, ['copy.meow']);
    final copy = SqliteEventRepository(target);
    addTearDown(copy.close);
    expect(copy.load()!.encode(), c.event!.encode());
  });
  test('a non-database file is refused and left byte-for-byte intact', () {
    final path = p.join(directory.path, 'notes.meow');
    File(path).writeAsStringSync('Round 1 pairings, not a database\n' * 200);
    final original = File(path).readAsBytesSync();
    expect(
      () => SqliteEventRepository(path),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('not a Meow-Chess event'),
        ),
      ),
    );
    expect(File(path).readAsBytesSync(), original);
  });
  test('undo history is durable across closing and reopening', () {
    final path = p.join(directory.path, 'undo.meow');
    final c = fixture(path: path);
    c.savePlayer(c.event!.players.first.copy(notes: 'Arrives late'));
    final label = c.undoLabel;
    c.dispose();
    final reopened = TournamentController(SqliteEventRepository(path));
    addTearDown(reopened.dispose);
    expect(reopened.undoLabel, label);
    reopened.undo();
    expect(reopened.event!.players.first.notes, isEmpty);
  });
  test(
    'a mixed day survives closing and reopening after every command',
    () async {
      final path = p.join(directory.path, 'day.meow');
      var c = fixture(count: 22, path: path);
      var commands = c.repository.history().length;
      void reopen() {
        final expected = c.event!.encode();
        c.dispose();
        c = TournamentController(SqliteEventRepository(path));
        expect(c.event!.encode(), expected);
        expect(c.repository.history().length, ++commands);
      }

      for (var round = 0; round < 3; round++) {
        c.post(await c.propose());
        reopen();
        for (final (i, g)
            in c.event!.games
                .where((g) => !g.outcome.resolved)
                .toList()
                .indexed) {
          c.recordResult(g.id, Outcome.values[1 + i % 6]);
          reopen();
        }
      }
      addTearDown(() => c.dispose());
      expect(c.event!.sections.every((s) => s.finished), true);
      expect(c.event!.revision, commands);
    },
  );
  test('a practice copy cannot undo back into the original event', () async {
    final real = fixture(path: p.join(directory.path, 'real.meow'));
    real.change(
      'Backups',
      real.event!.copy(backupFolder: p.join(directory.path, 'backups')),
    );
    final copyPath = p.join(directory.path, 'copy.meow');
    real.repository.backup(copyPath);
    real.dispose();
    await markPracticeCopy(copyPath);
    final copy = TournamentController(SqliteEventRepository(copyPath));
    addTearDown(copy.dispose);
    final marked = copy.event!.encode();
    expect(copy.undo, throwsA(isA<TournamentException>()));
    expect(copy.event!.encode(), marked);
    expect(copy.event!.backupFolder, isEmpty);
    expect(copy.event!.practice, true);
  });
}
