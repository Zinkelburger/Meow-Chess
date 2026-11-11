import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/common.dart';
import 'package:path/path.dart' as p;
import '../application/diagnostics.dart';
import '../application/event_repository.dart';
import '../application/full_path.dart';
import '../domain/history.dart';
import '../domain/model.dart';
import 'publish_file.dart';
import 'sqlite_platform.dart';

/// One owned connection per event. Foreign keys and FULL synchronous commits
/// protect acknowledged results; snapshots are produced by SQLite, never raw WAL copies.
class SqliteEventRepository implements EventRepository {
  /// The version of the file format, kept in SQLite's `user_version`. Every
  /// build refuses a file with a higher number than its own, so it goes up
  /// whenever a build starts saving anything an earlier build would drop or
  /// misread (docs/ARCHITECTURE.md, "File format version").
  ///
  /// 1: the first release. 2: history as a graph of saved states. 3: no
  /// change to the tables; stops releases up to 1.4.0, which rewrite a whole
  /// event from the fields they know, from opening later files.
  static const schemaVersion = 3;

  /// For tests: read the event back after every save and compare it with
  /// what was saved. Only in debug builds; a release never pays for it.
  static bool debugVerifyWrites = true;

  SqliteEventRepository(String path)
    : _path = path,
      _created = path == ':memory:' || !eventFileExists(path),
      _db = _open(path) {
    try {
      _db.execute('PRAGMA foreign_keys = ON');
      _db.execute('PRAGMA busy_timeout = 1000');
      final version =
          _db.select('PRAGMA user_version').first.values.first as int;
      if (version > schemaVersion) throw _newerVersion;
      _db.execute('PRAGMA locking_mode = EXCLUSIVE');
      // Merely choosing a file must not migrate an unrelated or damaged
      // database. These reads happen before persistent journal/schema changes;
      // exclusive locking mode retains their locks until ownership is acquired.
      Event? current;
      if (!_created) {
        _validateSchema(_db, version);
        current = load();
      }
      try {
        _db.execute('PRAGMA journal_mode = WAL');
      } on SqliteException catch (error) {
        // Only a refused sibling file justifies the fallback; anything else,
        // such as another program holding the file, is reported instead.
        if (!_siblingRefused(error)) rethrow;
        // WAL (and every rollback journal mode) creates a sibling file next to
        // this one. A macOS App Sandbox grant for a single externally-chosen
        // file does not cover creating that new filename in its folder, so
        // fall back to an in-memory journal, which stays within the file
        // already granted. A crash mid-commit can then damage the file.
        _db.execute('PRAGMA journal_mode = MEMORY');
        _crashProtected = false;
        Diagnostics.record(
          'open event',
          'crash protection unavailable',
          error: error,
          context: {'path': path},
        );
      }
      _db.execute('PRAGMA synchronous = FULL');
      // Taken even when there is nothing to write: this is what makes the
      // event ours, so a second window or program is refused.
      _db.execute('BEGIN EXCLUSIVE');
      // A file already in this format is opened without being rewritten.
      if (_created || version != schemaVersion) {
        _db.execute(_schema);
        if (version == 1) {
          // Version 1 kept only the last 100 undo snapshots, which cannot be
          // arranged into a graph; history starts from the state the file is in.
          _db.execute(
            'ALTER TABLE audit ADD COLUMN node INTEGER REFERENCES node(id)',
          );
          if (current != null) {
            _db.execute(
              'INSERT INTO audit(revision,action,timestamp,node) VALUES(?,?,?,?)',
              [
                current.revision,
                'Start history graph',
                _now(),
                _addNode(_db, null, 'Earlier changes', current),
              ],
            );
          }
          _db.execute('UPDATE audit SET before_state=NULL');
        }
        _db.execute('CREATE INDEX IF NOT EXISTS audit_node ON audit(node)');
        _db.execute('PRAGMA user_version = $schemaVersion');
      }
      _db.execute('COMMIT');
      _checkpoint();
      if (_path != ':memory:') {
        _ownershipPath = resolveEventPath(_path);
        _identity = eventFileIdentity(_path);
        _owners.add(this);
      }
    } catch (error) {
      _db.close();
      final busy =
          error is SqliteException &&
          (error.resultCode == 5 || error.resultCode == 6);
      // A file this constructor created must not stay behind as an empty or
      // half-initialized event. A busy file belongs to whoever created it.
      if (_created && path != ':memory:' && !busy) {
        for (final suffix in ['', '-wal', '-shm', '-journal']) {
          try {
            deleteEventFile('$path$suffix');
          } on FileSystemException {
            // The original failure is the one worth reporting.
          }
        }
      }
      if (error is SqliteException) {
        throw _openFailure(error, created: _created) ?? error;
      }
      rethrow;
    }
  }
  static final _owners = <SqliteEventRepository>{};

  static const _newerVersion = TournamentException(
    'This event was created by a newer version of Meow Chess. Update this '
    'copy of Meow Chess to open it.',
  );

  static const _schema =
      '''CREATE TABLE IF NOT EXISTS event (id TEXT PRIMARY KEY, revision INTEGER NOT NULL, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS player (id TEXT PRIMARY KEY, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS section (id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS membership (section_id TEXT REFERENCES section(id), player_id TEXT UNIQUE REFERENCES player(id), ordinal INTEGER NOT NULL, PRIMARY KEY(section_id,player_id));
CREATE TABLE IF NOT EXISTS round (section_id TEXT REFERENCES section(id), number INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY(section_id,number));
CREATE TABLE IF NOT EXISTS game (id TEXT PRIMARY KEY, section_id TEXT, round_number INTEGER, white_id TEXT REFERENCES player(id), black_id TEXT REFERENCES player(id), data TEXT NOT NULL, CHECK(white_id != black_id), FOREIGN KEY(section_id,round_number) REFERENCES round(section_id,number));
CREATE TABLE IF NOT EXISTS bye (section_id TEXT, round_number INTEGER, player_id TEXT REFERENCES player(id), data TEXT NOT NULL, PRIMARY KEY(section_id,round_number,player_id), FOREIGN KEY(section_id,round_number) REFERENCES round(section_id,number));
CREATE TABLE IF NOT EXISTS node (id INTEGER PRIMARY KEY, parent INTEGER REFERENCES node(id), action TEXT NOT NULL, timestamp TEXT NOT NULL, state BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS audit (id INTEGER PRIMARY KEY, revision INTEGER NOT NULL, action TEXT NOT NULL, timestamp TEXT NOT NULL, node INTEGER REFERENCES node(id));
CREATE TABLE IF NOT EXISTS preference (key TEXT PRIMARY KEY, value TEXT NOT NULL);''';

  static CommonDatabase _open(String path) {
    try {
      return sqlite3.open(path);
    } on SqliteException catch (error) {
      throw _openFailure(error, created: !eventFileExists(path)) ?? error;
    }
  }

  /// SQLITE_PERM, SQLITE_READONLY, SQLITE_IOERR, SQLITE_CANTOPEN and
  /// SQLITE_AUTH: the journal's sibling file could not be created.
  static bool _siblingRefused(SqliteException error) =>
      const {3, 8, 10, 14, 23}.contains(error.resultCode);

  /// Plain wording for SQLite failures a director can act on.
  static TournamentException? _openFailure(
    SqliteException error, {
    required bool created,
  }) {
    switch (error.resultCode) {
      case 5 || 6: // SQLITE_BUSY, SQLITE_LOCKED
        return const TournamentException(
          'This event is open in another window or program. Close it there first.',
        );
      case 26: // SQLITE_NOTADB
        return const TournamentException(
          'This file is not a Meow-Chess event.',
        );
      case 14 || 8 when created: // SQLITE_CANTOPEN, SQLITE_READONLY
        return const TournamentException(
          'Meow-Chess cannot create a file in this folder. Choose a folder you can save files in.',
        );
      // SQLITE_CANTOPEN, or SQLITE_READONLY_DIRECTORY: an event saved with
      // crash protection needs its recovery file beside it, which the folder
      // (or the macOS App Sandbox) refused.
      case 14:
      case 8 when error.extendedResultCode == 1544:
        return const TournamentException(
          'Meow-Chess could not create this event\'s recovery file next to it, so it cannot open the event safely. Check that you can save files in the event\'s folder.',
        );
      case 8: // SQLITE_READONLY
        return const TournamentException(
          'This event file is read-only. Check its permissions, or copy it to a folder you can save files in.',
        );
    }
    return null;
  }

  /// False when the folder refused SQLite's recovery file and commits use an
  /// in-memory journal, which a crash or power loss mid-commit can corrupt.
  bool get crashProtected => _crashProtected;
  bool _crashProtected = true, _closed = false;

  /// Moves every committed page from the recovery file (the WAL) into the
  /// event file and empties the recovery file. After each save the .meow on
  /// its own is therefore complete, and nothing is left beside it that SQLite
  /// could later replay over a different file given the same name, such as a
  /// backup copied over the event after a crash. The commit is already durable
  /// in the WAL; failing here only postpones that.
  ///
  /// SQLite reports a checkpoint it could not finish as a busy row, not an
  /// error, so the row is checked: the WAL beside the .meow then still
  /// matters, and Diagnostics should say so.
  void _checkpoint() {
    try {
      final rows = _db.select('PRAGMA wal_checkpoint(TRUNCATE)');
      final busy = rows.isEmpty ? 0 : rows.first.values.first;
      if (busy != 0) {
        Diagnostics.record(
          'checkpoint event',
          'busy',
          context: {'path': _path},
        );
      }
    } on SqliteException catch (error) {
      Diagnostics.record(
        'checkpoint event',
        'failed',
        error: error,
        context: {'path': _path},
      );
    }
  }

  /// Checks active databases and their journals using metadata only. Opening
  /// and then closing a raw file descriptor could release this process's
  /// POSIX SQLite locks, even if the descriptor was opened just for inspection.
  static bool ownsPath(String path) {
    // An external move/delete must not prevent inspecting other owners.
    String? resolved(String filename) => resolveEventPath(filename);

    final absolute = p.normalize(p.absolute(path));
    final target = resolved(path);
    for (final owner in _owners) {
      final paths = {
        p.normalize(p.absolute(owner._path)),
        if (owner._ownershipPath case final String original) original,
        if (resolved(owner._path) case final String canonical) canonical,
      };
      for (final base in paths) {
        for (final suffix in ['', '-wal', '-shm', '-journal']) {
          final candidate = '$base$suffix';
          if (p.equals(absolute, candidate) ||
              (target != null && p.equals(target, candidate))) {
            return true;
          }
          if (target != null && sameEventFile(target, candidate)) return true;
        }
      }
    }
    return false;
  }

  final bool _created;
  final String _path;
  String? _ownershipPath;

  /// What identified the file when it was opened ([eventFileIdentity]).
  String? _identity;

  /// Set when a save fails because the file's drive or folder has gone; a
  /// later save that succeeds clears it.
  bool _unreachable = false;

  @override
  EventFileProblem? checkFile() {
    if (_closed || _path == ':memory:') return null;
    if (_unreachable) return EventFileProblem.unreachable;
    final now = eventFileIdentity(_path);
    if (now != null && now == _identity) return null;
    return now == null && !eventFolderReachable(_path)
        ? EventFileProblem.unreachable
        : EventFileProblem.moved;
  }

  /// The repository that has [path] open in this process, if one does.
  static SqliteEventRepository? _ownerOf(String path) {
    final target = resolveEventPath(path) ?? p.normalize(p.absolute(path));
    for (final owner in _owners) {
      final held =
          resolveEventPath(owner._path) ??
          owner._ownershipPath ??
          p.normalize(p.absolute(owner._path));
      if (p.equals(target, held) || sameEventFile(target, held)) return owner;
    }
    return null;
  }

  /// The event stored at [path], read without opening it for writing: no
  /// file is created at a missing path, and the file is neither migrated nor
  /// changed in any other way. Null when there is no file or no event in it.
  /// Throws as opening does for a file that is not a readable event.
  static Event? peek(String path) {
    if (path == ':memory:' || !eventFileExists(path)) return null;
    // A second handle on a file this process has open could release its
    // locks when closed; the open event is already in memory.
    if (_ownerOf(path) case final owner?) return owner._known;
    final CommonDatabase db;
    try {
      db = openEventForReading(path);
    } on SqliteException catch (error) {
      throw _openFailure(error, created: false) ?? error;
    }
    try {
      final version =
          db.select('PRAGMA user_version').first.values.first as int;
      if (version > schemaVersion) throw _newerVersion;
      _validateSchema(db, version);
      return _read(db);
    } on SqliteException catch (error) {
      throw _openFailure(error, created: false) ?? error;
    } finally {
      db.close();
    }
  }

  static void _validateSchema(CommonDatabase db, int version) {
    const invalid = TournamentException(
      'This file is not a valid Meow-Chess event database.',
    );
    if (version < 1 || version > schemaVersion) throw invalid;
    final expected = {
      'event': ['id', 'revision', 'data'],
      'player': ['id', 'data'],
      'section': ['id', 'ordinal', 'data'],
      'membership': ['section_id', 'player_id', 'ordinal'],
      'round': ['section_id', 'number', 'data'],
      'game': [
        'id',
        'section_id',
        'round_number',
        'white_id',
        'black_id',
        'data',
      ],
      'bye': ['section_id', 'round_number', 'player_id', 'data'],
      'preference': ['key', 'value'],
      if (version >= 2)
        'node': ['id', 'parent', 'action', 'timestamp', 'state'],
    };
    final tables = db
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((row) => row['name'])
        .toSet();
    List<String> columns(String table) => [
      for (final row in db.select('PRAGMA table_info($table)'))
        row['name'] as String,
    ];
    for (final entry in expected.entries) {
      // Ordinary writes use positional INSERTs, so column order matters too.
      if (!tables.contains(entry.key) ||
          !_sameColumns(columns(entry.key), entry.value)) {
        throw invalid;
      }
    }
    final audit = columns('audit');
    final auditBase = ['id', 'revision', 'action', 'timestamp'];
    final legacyAudit = [...auditBase, 'before_state', 'undone'];
    if (!tables.contains('audit') ||
        (version == 1
            ? !_sameColumns(audit, legacyAudit)
            : !_sameColumns(audit, [...auditBase, 'node']) &&
                  !_sameColumns(audit, [...legacyAudit, 'node']))) {
      throw invalid;
    }
    if (db.select('SELECT id FROM event LIMIT 2').length > 1) throw invalid;
  }

  static bool _sameColumns(List<String> actual, List<String> expected) =>
      actual.length == expected.length &&
      actual.indexed.every((entry) => entry.$2 == expected[entry.$1]);

  /// SQLite may already have rolled back (for example after a failed COMMIT on
  /// a full disk); a second ROLLBACK would then mask the original error.
  void _rollback() {
    if (!_db.autocommit) _db.execute('ROLLBACK');
  }

  final CommonDatabase _db;

  /// The rows the stored event is saved as, so a save writes only the rows
  /// that differ. Dropped whenever a save fails, and then read back.
  _Rows? _stored;

  /// The event as last read or saved: what a copy is made from when the file
  /// itself can no longer be read.
  Event? _known;

  @override
  Event? load() {
    final event = _read(_db);
    _known = event;
    _stored = event == null ? null : _Rows(event);
    return event;
  }

  static Event? _read(CommonDatabase db) {
    final row = db.select('SELECT data FROM event').firstOrNull;
    if (row == null) return null;
    final j = jsonDecode(row['data'] as String) as Json;
    j['players'] = [
      for (final p in db.select('SELECT data FROM player ORDER BY rowid'))
        jsonDecode(p['data'] as String),
    ];
    j['sections'] = [
      for (final s in db.select('SELECT id,data FROM section ORDER BY ordinal'))
        {
          ...jsonDecode(s['data'] as String) as Json,
          'players': [
            for (final m in db.select(
              'SELECT player_id FROM membership WHERE section_id=? ORDER BY ordinal',
              [s['id']],
            ))
              m['player_id'],
          ],
          'rounds': [
            for (final r in db.select(
              'SELECT number,data FROM round WHERE section_id=? ORDER BY number',
              [s['id']],
            ))
              {
                ...jsonDecode(r['data'] as String) as Json,
                'games': [
                  for (final g in db.select(
                    'SELECT data FROM game WHERE section_id=? AND round_number=? ORDER BY rowid',
                    [s['id'], r['number']],
                  ))
                    jsonDecode(g['data'] as String),
                ],
                'byes': [
                  for (final b in db.select(
                    'SELECT data FROM bye WHERE section_id=? AND round_number=? ORDER BY rowid',
                    [s['id'], r['number']],
                  ))
                    jsonDecode(b['data'] as String),
                ],
              },
          ],
        },
    ];
    final e = Event.fromJson(j);
    validateEvent(e);
    return e;
  }

  /// The stored event's rows: the ones remembered from the last save when
  /// they are still the stored revision, otherwise read from the file.
  _Rows? _current() {
    final row = _db.select('SELECT id,revision FROM event').firstOrNull;
    if (row == null) return null;
    final stored = _stored;
    if (stored != null &&
        stored.id == row['id'] &&
        stored.revision == row['revision']) {
      return stored;
    }
    return _Rows(_read(_db)!);
  }

  /// Replaces every row with [rows].
  static void _writeAll(CommonDatabase db, _Rows rows) {
    for (final table in [
      'game',
      'bye',
      'round',
      'membership',
      'section',
      'player',
      'event',
    ]) {
      db.execute('DELETE FROM $table');
    }
    db.execute('INSERT INTO event VALUES(?,?,?)', [
      rows.id,
      rows.revision,
      rows.meta,
    ]);
    for (final MapEntry(key: id, value: data) in rows.players.entries) {
      db.execute('INSERT INTO player VALUES(?,?)', [id, data]);
    }
    for (final MapEntry(key: id, value: (ordinal, data))
        in rows.sections.entries) {
      db.execute('INSERT INTO section VALUES(?,?,?)', [id, ordinal, data]);
    }
    for (final MapEntry(key: (section, player), value: ordinal)
        in rows.membership.entries) {
      db.execute('INSERT INTO membership VALUES(?,?,?)', [
        section,
        player,
        ordinal,
      ]);
    }
    for (final MapEntry(key: (section, number), value: data)
        in rows.rounds.entries) {
      db.execute('INSERT INTO round VALUES(?,?,?)', [section, number, data]);
    }
    for (final MapEntry(key: (section, number), value: games)
        in rows.games.entries) {
      for (final MapEntry(key: id, value: (white, black, data))
          in games.entries) {
        db.execute('INSERT INTO game VALUES(?,?,?,?,?,?)', [
          id,
          section,
          number,
          white,
          black,
          data,
        ]);
      }
    }
    for (final MapEntry(key: (section, number), value: byes)
        in rows.byes.entries) {
      for (final MapEntry(key: player, value: data) in byes.entries) {
        db.execute('INSERT INTO bye VALUES(?,?,?,?)', [
          section,
          number,
          player,
          data,
        ]);
      }
    }
  }

  /// Saves [after] over [before], writing only the rows that differ: entering
  /// one result rewrites that game, not every player and game of the event.
  /// Players, games and byes are read back in the order they were inserted,
  /// so a change that reorders them (rather than adding at the end, changing
  /// in place or removing) rewrites everything instead.
  void _store(_Rows? before, _Rows after) {
    if (before == null || !before.keepsOrderIn(after)) {
      _writeAll(_db, after);
    } else {
      // Rows that refer to others go first when removing, last when adding.
      for (final MapEntry(key: round, value: games) in before.games.entries) {
        final kept = after.games[round];
        for (final id in games.keys) {
          if (kept == null || !kept.containsKey(id)) {
            _db.execute('DELETE FROM game WHERE id=?', [id]);
          }
        }
      }
      for (final MapEntry(key: round, value: byes) in before.byes.entries) {
        final kept = after.byes[round];
        for (final player in byes.keys) {
          if (kept == null || !kept.containsKey(player)) {
            _db.execute(
              'DELETE FROM bye WHERE section_id=? AND round_number=? AND player_id=?',
              [round.$1, round.$2, player],
            );
          }
        }
      }
      for (final round in before.rounds.keys) {
        if (!after.rounds.containsKey(round)) {
          _db.execute('DELETE FROM round WHERE section_id=? AND number=?', [
            round.$1,
            round.$2,
          ]);
        }
      }
      for (final member in before.membership.keys) {
        if (!after.membership.containsKey(member)) {
          _db.execute(
            'DELETE FROM membership WHERE section_id=? AND player_id=?',
            [member.$1, member.$2],
          );
        }
      }
      for (final id in before.sections.keys) {
        if (!after.sections.containsKey(id)) {
          _db.execute('DELETE FROM section WHERE id=?', [id]);
        }
      }
      for (final id in before.players.keys) {
        if (!after.players.containsKey(id)) {
          _db.execute('DELETE FROM player WHERE id=?', [id]);
        }
      }
      _db.execute('UPDATE event SET revision=?, data=? WHERE id=?', [
        after.revision,
        after.meta,
        after.id,
      ]);
      for (final MapEntry(key: id, value: data) in after.players.entries) {
        final old = before.players[id];
        if (old == null) {
          _db.execute('INSERT INTO player VALUES(?,?)', [id, data]);
        } else if (old != data) {
          _db.execute('UPDATE player SET data=? WHERE id=?', [data, id]);
        }
      }
      for (final MapEntry(key: id, value: row) in after.sections.entries) {
        final old = before.sections[id];
        if (old == null) {
          _db.execute('INSERT INTO section VALUES(?,?,?)', [
            id,
            row.$1,
            row.$2,
          ]);
        } else if (old != row) {
          _db.execute('UPDATE section SET ordinal=?, data=? WHERE id=?', [
            row.$1,
            row.$2,
            id,
          ]);
        }
      }
      for (final MapEntry(key: member, value: ordinal)
          in after.membership.entries) {
        final old = before.membership[member];
        if (old == null) {
          _db.execute('INSERT INTO membership VALUES(?,?,?)', [
            member.$1,
            member.$2,
            ordinal,
          ]);
        } else if (old != ordinal) {
          _db.execute(
            'UPDATE membership SET ordinal=? WHERE section_id=? AND player_id=?',
            [ordinal, member.$1, member.$2],
          );
        }
      }
      for (final MapEntry(key: round, value: data) in after.rounds.entries) {
        final old = before.rounds[round];
        if (old == null) {
          _db.execute('INSERT INTO round VALUES(?,?,?)', [
            round.$1,
            round.$2,
            data,
          ]);
        } else if (old != data) {
          _db.execute(
            'UPDATE round SET data=? WHERE section_id=? AND number=?',
            [data, round.$1, round.$2],
          );
        }
      }
      for (final MapEntry(key: round, value: games) in after.games.entries) {
        final had = before.games[round];
        for (final MapEntry(key: id, value: row) in games.entries) {
          final old = had?[id];
          if (old == null) {
            _db.execute('INSERT INTO game VALUES(?,?,?,?,?,?)', [
              id,
              round.$1,
              round.$2,
              row.$1,
              row.$2,
              row.$3,
            ]);
          } else if (old != row) {
            _db.execute(
              'UPDATE game SET white_id=?, black_id=?, data=? WHERE id=?',
              [row.$1, row.$2, row.$3, id],
            );
          }
        }
      }
      for (final MapEntry(key: round, value: byes) in after.byes.entries) {
        final had = before.byes[round];
        for (final MapEntry(key: player, value: data) in byes.entries) {
          final old = had?[player];
          if (old == null) {
            _db.execute('INSERT INTO bye VALUES(?,?,?,?)', [
              round.$1,
              round.$2,
              player,
              data,
            ]);
          } else if (old != data) {
            _db.execute(
              'UPDATE bye SET data=? WHERE section_id=? AND round_number=? AND player_id=?',
              [data, round.$1, round.$2, player],
            );
          }
        }
      }
    }
    assert(() {
      if (!debugVerifyWrites) return true;
      final read = _Rows(_read(_db)!);
      return read.meta == after.meta && read.sameTournamentRows(after);
    }(), 'The event read back differs from the event saved.');
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

  /// Full snapshots, compressed, so any node opens without replaying others.
  /// One costs about 80 bytes per player and 35 per game: 300 players through
  /// five rounds, every result entered singly, come to about 18 MB.
  static int _addNode(
    CommonDatabase db,
    int? parent,
    String action,
    Event state,
  ) {
    db.execute(
      'INSERT INTO node(parent,action,timestamp,state) VALUES(?,?,?,?)',
      [parent, action, _now(), zlibEncode(utf8.encode(state.encode()))],
    );
    return db.lastInsertRowId;
  }

  @override
  Event snapshot(int node) {
    final row = _db.select('SELECT state FROM node WHERE id=?', [
      node,
    ]).firstOrNull;
    if (row == null) {
      throw const TournamentException('That point in history is missing.');
    }
    return Event.decode(utf8.decode(zlibDecode(row['state'] as List<int>)));
  }

  /// SQLITE_IOERR or SQLITE_CANTOPEN while the event is open: the file's
  /// drive or folder has gone.
  static bool _deviceGone(SqliteException error) =>
      error.resultCode == 10 || error.resultCode == 14;

  /// Runs [write] as one transaction that saves a new revision, then empties
  /// the recovery file. Nothing is remembered as stored unless it committed.
  Event _save(Event Function(_Rows? before) write) {
    try {
      _db.execute('BEGIN IMMEDIATE');
      final Event saved;
      try {
        saved = write(_current());
        _db.execute('COMMIT');
      } catch (_) {
        _stored = null;
        try {
          _rollback();
        } on SqliteException {
          // The failure being reported is the one worth knowing.
        }
        rethrow;
      }
      _known = saved;
      _unreachable = false;
      _checkpoint();
      eventStorageChanged();
      return saved;
    } on SqliteException catch (error) {
      if (!_deviceGone(error)) rethrow;
      _unreachable = true;
      throw const EventFileUnreachable();
    }
  }

  @override
  Event commit(
    Event next, {
    required int expectedRevision,
    required String action,
  }) {
    validateEvent(next);
    return _save((before) {
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
      final rows = _Rows(committed);
      _store(before, rows);
      final head = _head();
      final int node;
      if (head != null && before != null && before.differsOnlyInBackups(rows)) {
        // Where backups go is this computer's setting: logged, but not a
        // point in the tournament's history.
        node = head;
      } else {
        // Redoing a step by hand returns to its node instead of branching a twin.
        final children = head == null
            ? const <int>[]
            : [
                for (final r in _db.select(
                  'SELECT id FROM node WHERE parent=? ORDER BY id',
                  [head],
                ))
                  r['id'] as int,
              ];
        final content = children.isEmpty ? '' : tournamentContent(committed);
        node =
            children
                .where((id) => tournamentContent(snapshot(id)) == content)
                .firstOrNull ??
            _addNode(_db, head, action, committed);
      }
      _db.execute(
        'INSERT INTO audit(revision,action,timestamp,node) VALUES(?,?,?,?)',
        [committed.revision, action, _now(), node],
      );
      _stored = rows;
      return committed;
    });
  }

  @override
  Event checkout(
    int node, {
    required int expectedRevision,
    required String action,
  }) => _save((current) {
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
      // History never changes where this computer keeps its backups.
      backupFolder: current.backupFolder,
      lastBackupRevision: current.lastBackupRevision,
    );
    validateEvent(restored);
    final rows = _Rows(restored);
    _store(current, rows);
    _db.execute(
      'INSERT INTO audit(revision,action,timestamp,node) VALUES(?,?,?,?)',
      [restored.revision, action, _now(), node],
    );
    _stored = rows;
    return restored;
  });

  @override
  HistoryGraph historyGraph() => HistoryGraph([
    for (final r in _db.select(
      'SELECT id,parent,action,timestamp,(SELECT MAX(a.id) FROM audit a WHERE a.node=node.id) AS visit FROM node',
    ))
      HistoryNode(
        id: r['id'] as int,
        parent: r['parent'] as int?,
        action: r['action'] as String,
        timestamp: r['timestamp'] as String,
        lastVisit: (r['visit'] ?? 0) as int,
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
  String? lastSaved() =>
      _db
              .select('SELECT timestamp FROM audit ORDER BY id DESC LIMIT 1')
              .firstOrNull?['timestamp']
          as String?;
  @override
  String? readPreference(String key) =>
      _db.select('SELECT value FROM preference WHERE key=?', [
            key,
          ]).firstOrNull?['value']
          as String?;
  @override
  void writePreference(String key, String value) => _setting(
    'INSERT INTO preference VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );

  @override
  void deletePreference(String key) =>
      _setting('DELETE FROM preference WHERE key=?', [key]);

  /// A preference is a save like any other: it leaves the recovery file
  /// empty, and a drive that has gone is reported in plain words.
  void _setting(String sql, List<Object?> parameters) {
    try {
      _db.execute(sql, parameters);
    } on SqliteException catch (error) {
      if (!_deviceGone(error)) rethrow;
      _unreachable = true;
      throw const EventFileUnreachable();
    }
    _checkpoint();
    eventStorageChanged();
  }

  /// Publishes a verified, independently openable snapshot at [destination].
  /// The copy is built and checked under a temporary sibling name, so a crash
  /// never leaves a partial file under the requested name.
  @override
  void backup(String destination, {bool replaceExisting = false}) {
    const exists = TournamentException(
      'Choose a new backup filename; existing copies are never overwritten.',
    );
    validateBackupDestination(destination);
    if (!replaceExisting && File(destination).existsSync()) throw exists;
    final replacing = replaceExisting && File(destination).existsSync();
    createDirectoryDurably(p.dirname(destination));
    final staging = File(
      '$destination.$pid-${DateTime.now().microsecondsSinceEpoch}.partial',
    );
    try {
      try {
        _db.execute('VACUUM INTO ?', [staging.path]);
      } on SqliteException catch (error) {
        // The event's own file cannot be read any more (its drive has gone,
        // or it is damaged): a copy of the event as last saved, without its
        // earlier history, is worth far more than no copy.
        final event = _known;
        if (event == null || _readable()) rethrow;
        deleteEventFile(staging.path);
        _writeWithoutHistory(staging.path, event);
        Diagnostics.record(
          'copy event',
          'saved without history',
          error: error,
          context: {'path': _path, 'revision': event.revision},
        );
      }
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
        void publish() =>
            publishFile(staging.path, destination, replaceExisting: replacing);
        if (replacing) {
          _replace(destination, publish);
        } else {
          publish();
        }
      } on FileSystemException {
        if (!replacing &&
            staging.existsSync() &&
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

  /// Whether the whole event file can still be read.
  bool _readable() {
    try {
      return _db.select('PRAGMA quick_check(1)').first.values.first == 'ok';
    } on SqliteException {
      return false;
    }
  }

  /// A new event file at [path] holding [event] as it stands, its history
  /// starting there.
  static void _writeWithoutHistory(String path, Event event) {
    final db = sqlite3.open(path);
    try {
      db.execute('PRAGMA synchronous = FULL');
      db.execute('BEGIN EXCLUSIVE');
      db.execute(_schema);
      db.execute('CREATE INDEX IF NOT EXISTS audit_node ON audit(node)');
      _writeAll(db, _Rows(event));
      db.execute(
        'INSERT INTO audit(revision,action,timestamp,node) VALUES(?,?,?,?)',
        [
          event.revision,
          'Copy saved without earlier history',
          _now(),
          _addNode(db, null, 'Earlier changes', event),
        ],
      );
      db.execute('PRAGMA user_version = $schemaVersion');
      db.execute('COMMIT');
    } finally {
      db.close();
    }
  }

  @override
  List<int> snapshotBytes() {
    final staging = scratchEventPath();
    try {
      _db.execute('VACUUM INTO ?', [staging]);
      final check = sqlite3.open(staging, mode: OpenMode.readOnly);
      try {
        if (check.select('PRAGMA integrity_check').first.values.first != 'ok') {
          throw const TournamentException('Copy verification failed.');
        }
      } finally {
        check.close();
      }
      return readEventFile(staging)!;
    } finally {
      deleteEventFile(staging);
    }
  }

  /// Reject active databases and recovery files before staging and publication.
  static void validateBackupDestination(String destination) {
    // A name that is not a full path here, such as a folder chosen on another
    // kind of computer, would land wherever the app happened to be started.
    if (!isFullPathHere(destination)) {
      throw const TournamentException('Choose a full path for the copy.');
    }
    final name = p.basename(destination).toLowerCase();
    if (ownsPath(destination) ||
        ['-wal', '-shm', '-journal'].any(name.endsWith)) {
      throw const TournamentException(
        'This is an open event file or a database recovery file. Choose another location for the copy.',
      );
    }
  }

  /// Native selected-file publication can await Foundation while retaining the
  /// same SQLite replacement lock used by portable, synchronous backups.
  static Future<void> replaceBackup(
    String destination,
    Future<void> Function(bool replaceExisting) publish, {
    bool? replaceExisting,
  }) async {
    validateBackupDestination(destination);
    final replacing =
        (replaceExisting ?? true) && File(destination).existsSync();
    final lock = replacing ? _lockReplacement(destination) : null;
    try {
      // An absent target has no SQLite lock. Native publication must remain
      // exclusive if another file appears while awaiting coordination.
      await publish(replacing);
    } finally {
      lock?.close();
    }
  }

  static void _replace(String destination, void Function() publish) {
    validateBackupDestination(destination);
    final lock = _lockReplacement(destination);
    try {
      publish();
    } finally {
      lock?.close();
    }
  }

  /// Keep SQLite ownership until POSIX publication; a preflight check alone
  /// leaves a window in which another process can acquire the old database.
  /// Closing the handle rolls back its read-only exclusive transaction.
  static CommonDatabase? _lockReplacement(String destination) {
    final resolved = File(destination).existsSync()
        ? File(destination).resolveSymbolicLinksSync()
        : destination;
    bool present(String suffix) =>
        FileSystemEntity.typeSync('$resolved$suffix', followLinks: false) !=
        FileSystemEntityType.notFound;
    const unavailable = TournamentException(
      'This event may be open or awaiting recovery. Open and close it before replacing it.',
    );
    final wal = File('$resolved-wal');
    if (present('-journal') ||
        (present('-wal') && (!wal.existsSync() || wal.lengthSync() != 0))) {
      throw unavailable;
    }
    if (!File(resolved).existsSync()) {
      if (present('-wal') || present('-shm')) throw unavailable;
      return null;
    }
    CommonDatabase? check;
    try {
      try {
        check = sqlite3.open(resolved, mode: OpenMode.readWrite);
        check.execute('PRAGMA busy_timeout = 1000');
        // Check even when no sidecars exist: DELETE-mode readers and reserved
        // writers need not have created a journal. No raw File handle is
        // closed here because POSIX close could release SQLite's locks.
        check.select('SELECT name FROM sqlite_master LIMIT 1');
        if (check.select('PRAGMA journal_mode = DELETE').first.values.first !=
            'delete') {
          throw unavailable;
        }
        check.execute('BEGIN EXCLUSIVE');
      } on SqliteException catch (error) {
        if (error.resultCode != 26 || present('-wal') || present('-shm')) {
          throw unavailable;
        }
        // A user-confirmed ordinary file may be replaced as before.
        check?.close();
        check = null;
      }
      if (Platform.isWindows) {
        // SQLite handles disallow delete sharing on Windows. Closing ours is
        // required for MoveFileEx; any competing open handle blocks the move.
        check?.close();
        check = null;
      }
      return check;
    } catch (_) {
      check?.close();
      rethrow;
    }
  }

  /// Folds the WAL into the event file first, so the .meow alone holds every
  /// commit once the event is closed.
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _checkpoint();
    _db.close();
    _owners.remove(this);
    eventStorageChanged();
  }
}

/// An event as the rows it is stored in: one per player, section, membership,
/// round, game and bye, each with its JSON text, in stored order. Comparing
/// two of these tells a save which rows to write.
class _Rows {
  _Rows(Event event)
    : id = event.id,
      revision = event.revision,
      practice = event.practice,
      backupFolder = event.backupFolder,
      lastBackupRevision = event.lastBackupRevision {
    final json = event.toJson()
      ..remove('players')
      ..remove('sections');
    meta = jsonEncode(json);
    tournamentMeta = jsonEncode(
      json..removeWhere((key, _) => computerEventFields.contains(key)),
    );
    for (final player in event.players) {
      players[player.id] = jsonEncode(player.toJson());
    }
    for (final (index, s) in event.sections.indexed) {
      sections[s.id] = (
        index,
        jsonEncode(
          s.toJson()
            ..remove('players')
            ..remove('rounds'),
        ),
      );
      for (final (i, player) in s.players.indexed) {
        membership[(s.id, player)] = i;
      }
      for (final r in s.rounds) {
        final round = (s.id, r.number);
        rounds[round] = jsonEncode(
          r.toJson()
            ..remove('games')
            ..remove('byes'),
        );
        games[round] = {
          for (final g in r.games)
            g.id: (g.white, g.black, jsonEncode(g.toJson())),
        };
        byes[round] = {
          for (final b in r.byes) b.player: jsonEncode(b.toJson()),
        };
      }
    }
  }

  final String id;
  final int revision;
  final bool practice;
  final String backupFolder;
  final int? lastBackupRevision;

  /// The event row: everything but players and sections.
  late final String meta;

  /// [meta] without the revision and where backups go.
  late final String tournamentMeta;
  final players = <String, String>{};
  final sections = <String, (int, String)>{};
  final membership = <(String, String), int>{};
  final rounds = <(String, int), String>{};
  final games = <(String, int), Map<String, (String, String, String)>>{};
  final byes = <(String, int), Map<String, String>>{};

  static bool _same<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) return false;
    final other = b.entries.iterator;
    for (final entry in a.entries) {
      other.moveNext();
      if (entry.key != other.current.key ||
          entry.value != other.current.value) {
        return false;
      }
    }
    return true;
  }

  static bool _sameGroups<K, V>(
    Map<(String, int), Map<K, V>> a,
    Map<(String, int), Map<K, V>> b,
  ) =>
      a.length == b.length &&
      a.entries.every((entry) {
        final other = b[entry.key];
        return other != null && _same(entry.value, other);
      });

  /// Whether every row but the event's own is the same, in the same order.
  bool sameTournamentRows(_Rows other) =>
      _same(players, other.players) &&
      _same(sections, other.sections) &&
      _same(membership, other.membership) &&
      _same(rounds, other.rounds) &&
      _sameGroups(games, other.games) &&
      _sameGroups(byes, other.byes);

  /// Whether [other] is this event with only its backup settings changed.
  bool differsOnlyInBackups(_Rows other) =>
      (backupFolder != other.backupFolder ||
          lastBackupRevision != other.lastBackupRevision) &&
      tournamentMeta == other.tournamentMeta &&
      sameTournamentRows(other);

  /// Whether the rows kept from [before] come in the same order in [after]
  /// and every new one comes after them: the order they are read back in
  /// when the new ones are simply inserted.
  static bool _appends<K>(Map<K, Object?> before, Map<K, Object?> after) {
    final kept = before.keys.where(after.containsKey).iterator;
    var added = false;
    for (final key in after.keys) {
      if (!before.containsKey(key)) {
        added = true;
      } else if (added || !kept.moveNext() || kept.current != key) {
        return false;
      }
    }
    return true;
  }

  /// Whether saving [after] over this needs no row moved: players, and the
  /// games and byes of each round, are stored in insertion order.
  bool keepsOrderIn(_Rows after) =>
      id == after.id &&
      _appends(players, after.players) &&
      after.games.entries.every(
        (round) => _appends(games[round.key] ?? const {}, round.value),
      ) &&
      after.byes.entries.every(
        (round) => _appends(byes[round.key] ?? const {}, round.value),
      );
}
