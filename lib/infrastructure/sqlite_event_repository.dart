import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;
import '../application/diagnostics.dart';
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
      _db = _open(path) {
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
      _db.execute('PRAGMA locking_mode = EXCLUSIVE');
      // Merely choosing a file must not migrate an unrelated or damaged
      // database. These reads happen before persistent journal/schema changes;
      // exclusive locking mode retains their locks until ownership is acquired.
      Event? current;
      if (!_created) {
        _validateExistingSchema(version);
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
      _checkpoint();
      if (_path != ':memory:') {
        _ownershipPath = File(_path).resolveSymbolicLinksSync();
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
            final leftover = File('$path$suffix');
            if (leftover.existsSync()) leftover.deleteSync();
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

  static Database _open(String path) {
    try {
      return sqlite3.open(path);
    } on SqliteException catch (error) {
      throw _openFailure(error, created: !File(path).existsSync()) ?? error;
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

  /// Copies committed pages from the WAL into the event file, so the .meow on
  /// its own is complete even if the app is killed or the file is copied while
  /// open. The commit is already durable in the WAL; failing here only
  /// postpones that.
  void _checkpoint() {
    try {
      _db.execute('PRAGMA wal_checkpoint(PASSIVE)');
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
    String? resolved(String filename) {
      try {
        return File(filename).resolveSymbolicLinksSync();
      } on FileSystemException {
        // An external move/delete must not prevent inspecting other owners.
        return null;
      }
    }

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
          if (target == null) continue;
          try {
            if (FileSystemEntity.identicalSync(target, candidate)) return true;
          } on FileSystemException {
            // Journal creation/removal and external renames can race a stat.
          }
        }
      }
    }
    return false;
  }

  final bool _created;
  final String _path;
  String? _ownershipPath;

  void _validateExistingSchema(int version) {
    const invalid = TournamentException(
      'This file is not a valid Meow-Chess event database.',
    );
    if (version != 1 && version != 2) throw invalid;
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
      if (version == 2)
        'node': ['id', 'parent', 'action', 'timestamp', 'state'],
    };
    final tables = _db
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((row) => row['name'])
        .toSet();
    List<String> columns(String table) => [
      for (final row in _db.select('PRAGMA table_info($table)'))
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
    if (_db.select('SELECT id FROM event LIMIT 2').length > 1) throw invalid;
  }

  static bool _sameColumns(List<String> actual, List<String> expected) =>
      actual.length == expected.length &&
      actual.indexed.every((entry) => entry.$2 == expected[entry.$1]);

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
      _checkpoint();
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
      _checkpoint();
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
    validateBackupDestination(destination);
    if (!replaceExisting && File(destination).existsSync()) throw exists;
    final replacing = replaceExisting && File(destination).existsSync();
    createDirectoryDurably(p.dirname(destination));
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

  /// Reject active databases and recovery files before staging and publication.
  static void validateBackupDestination(String destination) {
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
  static Database? _lockReplacement(String destination) {
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
    Database? check;
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
    try {
      _db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } on SqliteException catch (error) {
      Diagnostics.record(
        'checkpoint event',
        'failed',
        error: error,
        context: {'path': _path},
      );
    }
    _db.close();
    _owners.remove(this);
  }
}
