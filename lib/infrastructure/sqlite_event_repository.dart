import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;
import '../application/event_repository.dart';
import '../domain/model.dart';

/// One owned connection per event. Foreign keys and FULL synchronous commits
/// protect acknowledged results; snapshots are produced by SQLite, never raw WAL copies.
class SqliteEventRepository implements EventRepository {
  SqliteEventRepository(String path)
    : _created = path == ':memory:' || !File(path).existsSync(),
      _db = sqlite3.open(path) {
    try {
      _db.execute('PRAGMA foreign_keys = ON');
      _db.execute('PRAGMA busy_timeout = 1000');
      final version =
          _db.select('PRAGMA user_version').first.values.first as int;
      if (version > 1) {
        throw const TournamentException(
          'This event was created by a newer Meow-Chess version.',
        );
      }
      if (!_created &&
          _db
              .select(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='event'",
              )
              .isEmpty) {
        throw const TournamentException('This file is not a Meow-Chess event.');
      }
      _db.execute('PRAGMA locking_mode = EXCLUSIVE');
      _db.execute('PRAGMA journal_mode = WAL');
      _db.execute('PRAGMA synchronous = FULL');
      _db.execute('BEGIN EXCLUSIVE');
      _db.execute(
        '''CREATE TABLE IF NOT EXISTS event (id TEXT PRIMARY KEY, revision INTEGER NOT NULL, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS player (id TEXT PRIMARY KEY, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS section (id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS membership (section_id TEXT REFERENCES section(id), player_id TEXT UNIQUE REFERENCES player(id), ordinal INTEGER NOT NULL, PRIMARY KEY(section_id,player_id));
CREATE TABLE IF NOT EXISTS round (section_id TEXT REFERENCES section(id), number INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY(section_id,number));
CREATE TABLE IF NOT EXISTS game (id TEXT PRIMARY KEY, section_id TEXT, round_number INTEGER, white_id TEXT REFERENCES player(id), black_id TEXT REFERENCES player(id), data TEXT NOT NULL, CHECK(white_id != black_id), FOREIGN KEY(section_id,round_number) REFERENCES round(section_id,number));
CREATE TABLE IF NOT EXISTS bye (section_id TEXT, round_number INTEGER, player_id TEXT REFERENCES player(id), data TEXT NOT NULL, PRIMARY KEY(section_id,round_number,player_id), FOREIGN KEY(section_id,round_number) REFERENCES round(section_id,number));
CREATE TABLE IF NOT EXISTS audit (id INTEGER PRIMARY KEY, revision INTEGER NOT NULL, action TEXT NOT NULL, timestamp TEXT NOT NULL, before_state TEXT, undone INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS preference (key TEXT PRIMARY KEY, value TEXT NOT NULL);
PRAGMA user_version = 1;''',
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.close();
      rethrow;
    }
  }
  final bool _created;
  final Database _db;
  @override
  Event? load() {
    final row = _db.select('SELECT data FROM event').firstOrNull;
    if (row == null) return null;
    final j = jsonDecode(row['data']) as Json;
    j['players'] = [
      for (final p in _db.select('SELECT data FROM player ORDER BY rowid'))
        jsonDecode(p['data']),
    ];
    j['sections'] = [
      for (final s in _db.select(
        'SELECT id,data FROM section ORDER BY ordinal',
      ))
        {
          ...jsonDecode(s['data']) as Json,
          'players': [
            for (final m in _db.select(
              'SELECT player_id FROM membership WHERE section_id=? ORDER BY ordinal',
              [s['id']],
            ))
              m['player_id'],
          ],
          'rounds': [
            for (final r in _db.select(
              'SELECT number,data FROM round WHERE section_id=? ORDER BY number',
              [s['id']],
            ))
              {
                ...jsonDecode(r['data']) as Json,
                'games': [
                  for (final g in _db.select(
                    'SELECT data FROM game WHERE section_id=? AND round_number=? ORDER BY rowid',
                    [s['id'], r['number']],
                  ))
                    jsonDecode(g['data']),
                ],
                'byes': [
                  for (final b in _db.select(
                    'SELECT data FROM bye WHERE section_id=? AND round_number=? ORDER BY rowid',
                    [s['id'], r['number']],
                  ))
                    jsonDecode(b['data']),
                ],
              },
          ],
        },
    ];
    final e = Event.fromJson(j);
    validateEvent(e);
    return e;
  }

  void _write(Event event) {
    for (final table in [
      'game',
      'bye',
      'round',
      'membership',
      'section',
      'player',
      'event',
    ]) {
      _db.execute('DELETE FROM $table');
    }
    final meta = event.toJson()
      ..remove('players')
      ..remove('sections');
    _db.execute('INSERT INTO event VALUES(?,?,?)', [
      event.id,
      event.revision,
      jsonEncode(meta),
    ]);
    for (final player in event.players) {
      _db.execute('INSERT INTO player VALUES(?,?)', [
        player.id,
        jsonEncode(player.toJson()),
      ]);
    }
    for (final (index, s) in event.sections.indexed) {
      final data = s.toJson()
        ..remove('players')
        ..remove('rounds');
      _db.execute('INSERT INTO section VALUES(?,?,?)', [
        s.id,
        index,
        jsonEncode(data),
      ]);
      for (final (i, id) in s.players.indexed) {
        _db.execute('INSERT INTO membership VALUES(?,?,?)', [s.id, id, i]);
      }
      for (final r in s.rounds) {
        final data = r.toJson()
          ..remove('games')
          ..remove('byes');
        _db.execute('INSERT INTO round VALUES(?,?,?)', [
          s.id,
          r.number,
          jsonEncode(data),
        ]);
        for (final g in r.games) {
          _db.execute('INSERT INTO game VALUES(?,?,?,?,?,?)', [
            g.id,
            s.id,
            r.number,
            g.white,
            g.black,
            jsonEncode(g.toJson()),
          ]);
        }
        for (final b in r.byes) {
          _db.execute('INSERT INTO bye VALUES(?,?,?,?)', [
            s.id,
            r.number,
            b.player,
            jsonEncode(b.toJson()),
          ]);
        }
      }
    }
  }

  @override
  Event commit(
    Event next, {
    required int expectedRevision,
    required String action,
  }) {
    validateEvent(next);
    _db.execute('BEGIN IMMEDIATE');
    try {
      final before = load();
      if ((before?.revision ?? 0) != expectedRevision) {
        throw const TournamentException(
          'This event changed. Reload before applying this action.',
        );
      }
      if (before != null && before.id != next.id) {
        throw const TournamentException(
          'Cannot replace this file with a different event.',
        );
      }
      final committed = next.copy(
        revision: expectedRevision + 1,
        practice: (before?.practice ?? false) || next.practice,
      );
      _write(committed);
      _db.execute(
        'INSERT INTO audit(revision,action,timestamp,before_state) VALUES(?,?,?,?)',
        [
          committed.revision,
          action,
          DateTime.now().toUtc().toIso8601String(),
          before?.encode(),
        ],
      );
      // The audit remains permanent; only bounded undo snapshots are pruned.
      _db.execute(
        'UPDATE audit SET before_state=NULL WHERE id < (SELECT COALESCE(MAX(id),0)-100 FROM audit)',
      );
      _db.execute('COMMIT');
      return committed;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  String? get undoLabel =>
      _db
              .select(
                "SELECT action FROM audit WHERE undone=0 AND before_state IS NOT NULL AND action NOT LIKE 'Undo %' ORDER BY id DESC LIMIT 1",
              )
              .firstOrNull?['action']
          as String?;
  @override
  Event? undo() {
    final row = _db
        .select(
          "SELECT * FROM audit WHERE undone=0 AND before_state IS NOT NULL AND action NOT LIKE 'Undo %' ORDER BY id DESC LIMIT 1",
        )
        .firstOrNull;
    if (row == null) return null;
    final before = Event.decode(row['before_state']);
    final current = load()!;
    // Undo of a posted round is only safe before play. Corrections remain separate.
    final previousGames = before.games.map((g) => g.id).toSet();
    if (current.sections
        .expand((s) => s.rounds)
        .any(
          (r) => r.hasPlay && r.games.any((g) => !previousGames.contains(g.id)),
        )) {
      throw const TournamentException(
        'This action would remove a started round. Correct the affected games instead.',
      );
    }
    _db.execute('BEGIN IMMEDIATE');
    try {
      final restored = before.copy(
        revision: current.revision + 1,
        practice: current.practice || before.practice,
        sections: [
          for (final section in before.sections)
            section.copy(
              rounds: [
                for (final round in section.rounds)
                  round.copy(
                    startedAt: current.sections
                        .where((s) => s.id == section.id)
                        .firstOrNull
                        ?.rounds
                        .where((r) => r.number == round.number)
                        .firstOrNull
                        ?.startedAt,
                  ),
              ],
            ),
        ],
      );
      validateEvent(restored);
      _write(restored);
      _db.execute('UPDATE audit SET undone=1 WHERE id=?', [row['id']]);
      _db.execute(
        'INSERT INTO audit(revision,action,timestamp) VALUES(?,?,?)',
        [
          restored.revision,
          'Undo ${row['action']}',
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      _db.execute('COMMIT');
      return restored;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  List<Json> history() => [
    for (final r in _db.select(
      'SELECT revision,action,timestamp,undone FROM audit ORDER BY id DESC',
    ))
      Map<String, dynamic>.from(r),
  ];
  @override
  String? readPreference(String key) =>
      _db.select('SELECT value FROM preference WHERE key=?', [
            key,
          ]).firstOrNull?['value']
          as String?;
  @override
  void writePreference(String key, String value) => _db.execute(
    'INSERT INTO preference VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );
  @override
  void backup(String destination) {
    if (File(destination).existsSync()) {
      throw const TournamentException(
        'Choose a new backup filename; existing copies are never overwritten.',
      );
    }
    Directory(p.dirname(destination)).createSync(recursive: true);
    try {
      _db.execute('VACUUM INTO ?', [destination]);
      final check = sqlite3.open(destination, mode: OpenMode.readOnly);
      try {
        if (check.select('PRAGMA integrity_check').first.values.first != 'ok') {
          throw const TournamentException('Backup verification failed.');
        }
      } finally {
        check.close();
      }
    } catch (_) {
      final file = File(destination);
      if (file.existsSync()) file.deleteSync();
      rethrow;
    }
  }

  @override
  void close() => _db.close();
}
