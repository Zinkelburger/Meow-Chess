import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;
import '../application/event_repository.dart';
import '../domain/history.dart';
import '../domain/model.dart';
import 'publish_file.dart';

/// One owned connection per event. Foreign keys and FULL synchronous commits
/// protect acknowledged results; snapshots are produced by SQLite, never raw WAL copies.
class SqliteEventRepository implements EventRepository {
  SqliteEventRepository(String path)
    : _path = path,
      _created = path == ':memory:' || !File(path).existsSync(),
      _db = sqlite3.open(path) {
    try {
      _db.execute('PRAGMA foreign_keys = ON');
      _db.execute('PRAGMA busy_timeout = 1000');
      final version =
          _db.select('PRAGMA user_version').first.values.first as int;
      if (version > 2) {
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
CREATE TABLE IF NOT EXISTS node (id INTEGER PRIMARY KEY, parent INTEGER REFERENCES node(id), action TEXT NOT NULL, timestamp TEXT NOT NULL, state BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS audit (id INTEGER PRIMARY KEY, revision INTEGER NOT NULL, action TEXT NOT NULL, timestamp TEXT NOT NULL, node INTEGER REFERENCES node(id));
CREATE TABLE IF NOT EXISTS preference (key TEXT PRIMARY KEY, value TEXT NOT NULL);''',
      );
      if (version == 1) {
        // Version 1 kept only the last 100 undo snapshots, which cannot be
        // arranged into a graph; history starts from the state the file is in.
        _db.execute(
          'ALTER TABLE audit ADD COLUMN node INTEGER REFERENCES node(id)',
        );
        final current = load();
        if (current != null) {
          _db.execute(
            'INSERT INTO audit(revision,action,timestamp,node) VALUES(?,?,?,?)',
            [
              current.revision,
              'Start history graph',
              _now(),
              _addNode(null, 'Earlier changes', current),
            ],
          );
        }
        _db.execute('UPDATE audit SET before_state=NULL');
      }
      _db.execute('CREATE INDEX IF NOT EXISTS audit_node ON audit(node)');
      _db.execute('PRAGMA user_version = 2');
      _db.execute('COMMIT');
    } catch (error) {
      _db.close();
      if (error is SqliteException) {
        switch (error.resultCode) {
          case 5 || 6: // SQLITE_BUSY, SQLITE_LOCKED
            throw const TournamentException(
              'This event is open in another window or program. Close it there first.',
            );
          case 26: // SQLITE_NOTADB
            throw const TournamentException(
              'This file is not a Meow-Chess event.',
            );
        }
      }
      rethrow;
    }
  }
  final bool _created;
  final String _path;

  /// SQLite may already have rolled back (for example after a failed COMMIT on
  /// a full disk); a second ROLLBACK would then mask the original error.
  void _rollback() {
    if (!_db.autocommit) _db.execute('ROLLBACK');
  }

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

  static String _now() => DateTime.now().toUtc().toIso8601String();

  /// The node the stored event is at: the one named by the latest audit row.
  int? _head() =>
      _db
              .select(
                'SELECT node FROM audit WHERE node IS NOT NULL ORDER BY id DESC LIMIT 1',
              )
              .firstOrNull?['node']
          as int?;

  /// Full snapshots, compressed: a day of commands stays a few megabytes and
  /// any node opens without replaying others.
  int _addNode(int? parent, String action, Event state) {
    _db.execute(
      'INSERT INTO node(parent,action,timestamp,state) VALUES(?,?,?,?)',
      [parent, action, _now(), zlib.encode(utf8.encode(state.encode()))],
    );
    return _db.lastInsertRowId;
  }

  static String _content(Event e) => e.copy(revision: 0).encode();

  @override
  Event snapshot(int node) {
    final row = _db.select('SELECT state FROM node WHERE id=?', [
      node,
    ]).firstOrNull;
    if (row == null) {
      throw const TournamentException('That point in history is missing.');
    }
    return Event.decode(utf8.decode(zlib.decode(row['state'] as List<int>)));
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
      final head = _head();
      // Redoing a step by hand returns to its node instead of branching a twin.
      final content = _content(committed);
      final twin = head == null
          ? null
          : _db
                .select('SELECT id FROM node WHERE parent=? ORDER BY id', [
                  head,
                ])
                .map((r) => r['id'] as int)
                .where((id) => _content(snapshot(id)) == content)
                .firstOrNull;
      _db.execute(
        'INSERT INTO audit(revision,action,timestamp,node) VALUES(?,?,?,?)',
        [
          committed.revision,
          action,
          _now(),
          twin ?? _addNode(head, action, committed),
        ],
      );
      _db.execute('COMMIT');
      return committed;
    } catch (_) {
      _rollback();
      rethrow;
    }
  }

  @override
  Event checkout(
    int node, {
    required int expectedRevision,
    required String action,
  }) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final current = load();
      if (current == null || current.revision != expectedRevision) {
        throw const TournamentException(
          'This event changed. Reload before applying this action.',
        );
      }
      final target = snapshot(node);
      if (target.id != current.id) {
        throw const TournamentException(
          'That point in history belongs to a different event.',
        );
      }
      final restored = target.copy(
        revision: current.revision + 1,
        practice: current.practice || target.practice,
      );
      validateEvent(restored);
      _write(restored);
      _db.execute(
        'INSERT INTO audit(revision,action,timestamp,node) VALUES(?,?,?,?)',
        [restored.revision, action, _now(), node],
      );
      _db.execute('COMMIT');
      return restored;
    } catch (_) {
      _rollback();
      rethrow;
    }
  }

  @override
  HistoryGraph historyGraph() => HistoryGraph([
    for (final r in _db.select(
      'SELECT id,parent,action,timestamp,(SELECT MAX(a.id) FROM audit a WHERE a.node=node.id) AS visit FROM node',
    ))
      HistoryNode(
        id: r['id'],
        parent: r['parent'],
        action: r['action'],
        timestamp: r['timestamp'],
        lastVisit: r['visit'] ?? 0,
      ),
  ], _head());

  /// The permanent log: every command and every move through history.
  @override
  List<Json> history() => [
    for (final r in _db.select(
      'SELECT revision,action,timestamp,node FROM audit ORDER BY id DESC',
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

  /// Publishes a verified, independently openable snapshot at [destination].
  /// The copy is built and checked under a temporary sibling name, so a crash
  /// never leaves a partial file under the requested name.
  @override
  void backup(String destination, {bool replaceExisting = false}) {
    const exists = TournamentException(
      'Choose a new backup filename; existing copies are never overwritten.',
    );
    if (!replaceExisting && File(destination).existsSync()) throw exists;
    if (replaceExisting) _checkReplacement(destination);
    Directory(p.dirname(destination)).createSync(recursive: true);
    final staging = File(
      '$destination.$pid-${DateTime.now().microsecondsSinceEpoch}.partial',
    );
    try {
      _db.execute('VACUUM INTO ?', [staging.path]);
      final check = sqlite3.open(staging.path, mode: OpenMode.readOnly);
      try {
        if (check.select('PRAGMA integrity_check').first.values.first != 'ok') {
          throw const TournamentException('Backup verification failed.');
        }
      } finally {
        check.close();
      }
      // VACUUM INTO is consistent but not necessarily durable; sync first.
      final handle = staging.openSync(mode: FileMode.append);
      try {
        handle.flushSync();
      } finally {
        handle.closeSync();
      }
      try {
        if (replaceExisting) _checkReplacement(destination);
        publishFile(
          staging.path,
          destination,
          replaceExisting: replaceExisting,
        );
      } on FileSystemException {
        if (!replaceExisting &&
            FileSystemEntity.typeSync(destination, followLinks: false) !=
                FileSystemEntityType.notFound) {
          throw exists;
        }
        rethrow;
      }
    } finally {
      if (staging.existsSync()) staging.deleteSync();
    }
  }

  void _checkReplacement(String destination) {
    if (_path != ':memory:' &&
        (p.equals(p.absolute(_path), p.absolute(destination)) ||
            (File(destination).existsSync() &&
                FileSystemEntity.identicalSync(_path, destination)))) {
      throw const TournamentException(
        'This is the open event file. Choose another location for the copy.',
      );
    }
    // Replacing a database underneath a live writer or an unrecovered WAL
    // would detach its contents from its journal. Never remove those journals.
    final resolved = File(destination).existsSync()
        ? File(destination).resolveSymbolicLinksSync()
        : destination;
    bool hasJournals() => ['-wal', '-shm', '-journal'].any(
      (suffix) =>
          FileSystemEntity.typeSync('$resolved$suffix', followLinks: false) !=
          FileSystemEntityType.notFound,
    );
    if (!hasJournals()) return;
    const unavailable = TournamentException(
      'This event may be open or awaiting recovery. Open and close it before replacing it.',
    );
    // Only clean up an empty WAL left by inspection. Nonempty recovery data
    // must be recovered through opening the event before attempting Replace.
    final wal = File('$resolved-wal');
    if (FileSystemEntity.typeSync('$resolved-journal', followLinks: false) !=
            FileSystemEntityType.notFound ||
        (wal.existsSync() && wal.lengthSync() != 0) ||
        !File(resolved).existsSync()) {
      throw unavailable;
    }
    final handle = File(resolved).openSync();
    try {
      if (String.fromCharCodes(handle.readSync(16)) !=
          'SQLite format 3\u0000') {
        throw unavailable;
      }
    } finally {
      handle.closeSync();
    }
    // Let SQLite manage its own journals. Switching out of WAL requires an
    // exclusive lock, so a live writer or reader prevents replacement.
    Database? check;
    try {
      check = sqlite3.open(resolved, mode: OpenMode.readWrite);
      check.execute('PRAGMA busy_timeout = 1000');
      check.execute('BEGIN EXCLUSIVE');
      check.select('SELECT name FROM sqlite_master LIMIT 1');
      check.execute('COMMIT');
      if (check.select('PRAGMA journal_mode = DELETE').first.values.first !=
          'delete') {
        throw unavailable;
      }
    } on SqliteException {
      throw unavailable;
    } finally {
      check?.close();
    }
    if (hasJournals()) throw unavailable;
  }

  @override
  void close() => _db.close();
}
