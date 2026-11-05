// A seeded, shrinking fuzzer over TournamentController: random tournament
// days of registration, pairing, results, corrections, re-pairing, history
// moves and reopening, every command checked against invariants that hold
// for any reachable state. See docs/TESTING.md, "Controller fuzzer".
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:meow_chess/application/event_repository.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/application/tournament_controller_core.dart'
    show LadderCommands;
import 'package:meow_chess/domain/history.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/rating_preview.dart';
import 'package:meow_chess/domain/recovery.dart';
import 'package:meow_chess/domain/standings.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

/// One step of a trace. [args] are raw choices, resolved against whatever
/// the event holds when the step runs, so any subsequence of a trace is
/// still a runnable trace. That is what lets the shrinker delete steps.
///
/// Identities are stable under deletion, so a fault that needs one
/// particular player still shrinks: [tag] is the step's index in the trace
/// as generated and never changes, every ID minted during the step derives
/// from it, and a choice among candidates is a rendezvous hash of the
/// argument and each candidate's identity ([Harness._pick]), which removing
/// an unrelated candidate cannot change.
class Act {
  const Act(this.kind, [this.args = const [], this.tag = 0]);
  final String kind;
  final List<int> args;
  final int tag;
  int arg(int i) => i < args.length ? args[i] : 0;
  Act withArgs(List<int> args) => Act(kind, args, tag);
  Map<String, Object> toJson() => {'k': kind, 't': tag, 'a': args};
  factory Act.fromJson(Map<String, dynamic> j) => Act(j['k'] as String, [
    for (final a in j['a'] as List) a as int,
  ], j['t'] as int);
  @override
  String toString() => '#$tag $kind ${jsonEncode(args)}';
}

/// A broken invariant. [id] names which one; two failures are "the same
/// bug" for shrinking when their [signature]s match.
class Violation implements Exception {
  Violation(this.id, this.message, {this.errorType = '', this.stack});
  final String id, message, errorType;
  final StackTrace? stack;
  String get signature => '$id/$errorType';
  @override
  String toString() =>
      '[$id]${errorType.isEmpty ? '' : ' $errorType'}: $message';
}

/// IDs minted during a step derive from its [Act.tag], so deleting other
/// steps never renames anything. Shared by every controller of one run.
class FuzzIds {
  var _step = -1, _next = 0;
  void begin(int tag) {
    _step = tag;
    _next = 0;
  }

  String call() => 'x${_step}_${_next++}';
}

/// The real controller with deterministic IDs. Pairing proposals still mint
/// their own game IDs on the isolate; traces never name a game by ID.
class FuzzController extends TournamentController {
  FuzzController(super.repository, this._ids, {this.pairInline = false});
  final FuzzIds _ids;

  /// Pair on the calling thread, for widget tests on a fake clock.
  final bool pairInline;
  @override
  String newId() => _ids();
  @override
  Future<PairingBatch> runProposal(
    Event snapshot,
    String? sectionId,
    bool onlyReady,
  ) => pairInline
      ? Future.value(proposeRounds(snapshot, sectionId, onlyReady))
      : super.runProposal(snapshot, sectionId, onlyReady);
}

/// Delegates to SQLite, but first notes whether the event the controller
/// asked to save is one [validateEvent] refuses. Such a commit is refused
/// safely by the repository, yet it means a command built an invalid event
/// instead of refusing it with its own explanation.
class _CheckedRepository implements EventRepository {
  _CheckedRepository(this.inner);
  final SqliteEventRepository inner;
  String? invalidCommit;

  @override
  Event commit(
    Event next, {
    required int expectedRevision,
    required String action,
  }) {
    try {
      validateEvent(next);
    } on TournamentException catch (e) {
      invalidCommit = '$action: ${e.message}';
    }
    return inner.commit(
      next,
      expectedRevision: expectedRevision,
      action: action,
    );
  }

  @override
  Event? load() => inner.load();
  @override
  Event checkout(
    int node, {
    required int expectedRevision,
    required String action,
  }) =>
      inner.checkout(node, expectedRevision: expectedRevision, action: action);
  @override
  HistoryGraph historyGraph() => inner.historyGraph();
  @override
  Event snapshot(int node) => inner.snapshot(node);
  @override
  List<Json> history() => inner.history();
  @override
  String? lastSaved() => inner.lastSaved();
  @override
  String? readPreference(String key) => inner.readPreference(key);
  @override
  void writePreference(String key, String value) =>
      inner.writePreference(key, value);
  @override
  void backup(String destination, {bool replaceExisting = false}) =>
      inner.backup(destination, replaceExisting: replaceExisting);
  @override
  List<int> snapshotBytes() => inner.snapshotBytes();
  @override
  void close() => inner.close();
}

String _content(Event e) => e.copy(revision: 0).encode();

/// Names that stress reports and exports: accents, CJK, punctuation that
/// CSV and DBF must handle, spreadsheet-formula prefixes, and the longest
/// names a roster might paste.
const _names = [
  'Ana Silva',
  'Bo Chen',
  'Zoë Ñúñez',
  'O\'Brien, Liam',
  '李小龙',
  'Wolfgang Amadeus Theophilus Mozart-Habsburg',
  '=HYPERLINK("x")',
  'Ali  Khan',
  'Émile Zola',
  'Mary-Kate "MK" Olsen',
  'Jo',
  'Ünal Öz',
  'Nguyễn Văn An',
  'A',
  'Smith, John Jr.',
  '@risk',
  'Tab\tName',
];

/// Formats a USCF club director runs. Knockout, ladder, bughouse and
/// Scheveningen have their own command families and are left for later.
/// Weighted toward the formats a US Chess club runs most.
const _formats = [
  Format.swiss, Format.swiss, Format.swiss, Format.swiss, //
  Format.quad, Format.quad, Format.roundRobin,
  Format.knockout, Format.ladder, Format.bughouse, Format.scheveningen,
];

const _outcomes = [
  Outcome.whiteWin, Outcome.blackWin, Outcome.draw, //
  Outcome.whiteWin, Outcome.blackWin, Outcome.draw,
  Outcome.whiteForfeit, Outcome.blackForfeit, Outcome.doubleForfeit,
  Outcome.unfinished, Outcome.disputed, Outcome.unreported,
];

/// Executes traces against a fresh event file and checks every invariant.
class Harness {
  Harness(this.directory, {this.strict = false});

  /// Treat an invalid event refused by the repository as a violation.
  final bool strict;
  final Directory directory;
  late final String path = '${directory.path}/fuzz.meow';
  final _ids = FuzzIds();
  late _CheckedRepository _repo;
  late FuzzController c;

  /// Invalid events a command tried to save (refused by the repository).
  /// Reported, not failed, unless the run is strict.
  final soft = <String>[];
  var commands = 0, refused = 0, skipped = 0;

  /// Per command: [accepted, refused], to see what a campaign reached.
  final tally = <String, List<int>>{};

  /// Per command: refusal message → count, to see why steps are wasted.
  final reasons = <String, Map<String, int>>{};
  var maxRounds = 0;

  void open() {
    _repo = _CheckedRepository(SqliteEventRepository(path));
    c = FuzzController(_repo, _ids);
  }

  void close() => c.dispose();

  Event get e => c.event!;

  /// Runs every step, stopping at the first violation, which is rethrown
  /// with the index of the step that caused it.
  Future<void> run(
    Iterable<Act> trace, {
    void Function(int, Act)? onStep,
  }) async {
    var steps = 0;
    open();
    try {
      _call('create', () => c.create('Fuzz Open'));
      for (final (i, act) in trace.indexed) {
        onStep?.call(i, act);
        steps = i + 1;
        final before = e;
        _ids.begin(act.tag);
        try {
          await _step(act);
          _checkState(before);
          if (i % 25 == 24) _checkRecoverable();
        } on Violation catch (v) {
          throw TraceFailure(i, act, v);
        }
      }
      try {
        _checkRecoverable();
      } on Violation catch (v) {
        throw TraceFailure(steps, const Act('finalHistory', [], -1), v);
      }
      // The file on disk is the event: closing and reopening changes nothing.
      final last = _content(e);
      close();
      open();
      if (_content(e) != last) {
        throw TraceFailure(
          steps,
          const Act('finalReopen', [], -1),
          Violation(
            'reopen',
            'Reopened file differs from the event in memory.',
          ),
        );
      }
    } finally {
      close();
    }
  }

  // ---------------------------------------------------------------------
  // Command wrapper: the per-command invariants.

  /// Calls one controller command. A [TournamentException] is a refusal and
  /// must leave the event exactly as it was; any other error is a crash.
  /// An accepted command commits at most one revision, and memory, the
  /// saved rows and the history graph's current node all agree after it.
  T? _call<T>(
    String name,
    T Function() command, {
    bool history = false,
    bool mustRefuse = false,
  }) {
    commands++;
    final before = c.event,
        beforeContent = before == null ? null : _content(before);
    _repo.invalidCommit = null;
    T? result;
    var ok = true;
    try {
      result = command();
    } on TournamentException catch (x) {
      ok = false;
      refused++;
      final why = (reasons[name] ??= {});
      why[x.message] = (why[x.message] ?? 0) + 1;
    } on Violation {
      rethrow;
    } catch (error, stack) {
      throw Violation(
        'crash',
        '$name threw $error',
        errorType: '${error.runtimeType}',
        stack: stack,
      );
    }
    (tally[name] ??= [0, 0])[ok ? 0 : 1]++;
    if (_repo.invalidCommit case final invalid?) {
      if (strict) {
        throw Violation(
          'invalid-commit',
          'The repository refused an invalid event: $invalid',
        );
      }
      soft.add(invalid);
    }
    final after = c.event!;
    if (!ok) {
      if (before == null ||
          after.revision != before.revision ||
          _content(after) != beforeContent) {
        throw Violation(
          'refusal-changed',
          '$name was refused but changed the event.',
        );
      }
    } else {
      final delta = after.revision - (before?.revision ?? 0);
      if (delta < 0 || delta > 1) {
        throw Violation('revisions', '$name advanced the revision by $delta.');
      }
      if (delta == 0 &&
          beforeContent != null &&
          _content(after) != beforeContent) {
        throw Violation(
          'unsaved-change',
          '$name changed the event without a revision.',
        );
      }
      if (delta == 1 && !history && _content(after) == beforeContent) {
        throw Violation(
          'empty-revision',
          '$name spent a revision on no change.',
        );
      }
      if (mustRefuse) {
        throw Violation(
          'stale-accepted',
          '$name accepted a stale review or proposal.',
        );
      }
    }
    if (ok) _committed.add(_content(after));
    _checkPersistence(name);
    return result;
  }

  /// Moves through history to [target] and checks the move: the losses the
  /// UI would show are the play the move removes; a move that loses play is
  /// refused unless accepted, and one that does not is never refused; and
  /// the event lands exactly on the target's saved state.
  void _historyMove(
    String name,
    int? target,
    bool accept,
    void Function() move,
  ) {
    if (target == null || target == c.graph.head) {
      _call(name, move, history: true);
      return;
    }
    final saved = _repo.snapshot(target);
    final losses = c.lossesTo(target);
    final lost = playLost(e, saved);
    if (losses.join('\n') != lost.join('\n')) {
      throw Violation(
        'losses',
        '$name: the losses shown differ from the play removed.',
      );
    }
    final rev = e.revision;
    final mustRefuse = losses.isNotEmpty && !accept;
    _call(name, move, history: true, mustRefuse: mustRefuse);
    if (e.revision == rev && !mustRefuse && !e.practice) {
      throw Violation(
        'history-refused',
        '$name to a state without lost play was refused.',
      );
    }
    if (e.revision != rev && _content(e) != _content(saved)) {
      throw Violation(
        'history-target',
        '$name did not land on the saved state it targeted.',
      );
    }
  }

  /// Every state ever committed is still in the history, and every saved
  /// state is a valid event: going back can always reach any of them.
  void _checkRecoverable() {
    final kept = <String>{};
    for (final node in c.graph.nodes.keys) {
      final saved = _repo.snapshot(node);
      try {
        validateEvent(saved);
      } on TournamentException catch (x) {
        throw Violation(
          'invalid-snapshot',
          'History node $node is invalid: ${x.message}',
        );
      }
      kept.add(_content(saved));
    }
    final lost = _committed.difference(kept);
    if (lost.isNotEmpty) {
      throw Violation(
        'unrecoverable',
        '${lost.length} committed states are no longer in the history.',
      );
    }
    _checkRecoveryPoints();
  }

  /// Recovery points say true things: "Before round N pairings" is a state
  /// with N - 1 rounds that the next step paired, and so on. Every round on
  /// the board can be gone back before, and a limited walk is a prefix.
  void _checkRecoveryPoints() {
    final points = c.recoveryPoints();
    Never wrong(RecoveryPoint p, String why) =>
        throw Violation('recovery-point', '"${p.mark}" (node ${p.node}): $why');
    int rounds(Event e, String id) =>
        e.sections.where((s) => s.id == id).firstOrNull?.rounds.length ?? 0;
    final covered = <String, Set<int>>{};
    for (final p in points) {
      if (c.graph.nodes[p.step]?.parent != p.node) {
        wrong(p, 'not the step parent');
      }
      final before = _repo.snapshot(p.node), after = _repo.snapshot(p.step);
      final m = p.mark;
      switch (m.kind) {
        case RecoveryKind.pairing:
          for (final id in m.sectionIds) {
            if (rounds(before, id) != m.round - 1 ||
                rounds(after, id) < m.round) {
              wrong(
                p,
                'section $id went ${rounds(before, id)} → ${rounds(after, id)} rounds',
              );
            }
            for (var r = m.round; r <= rounds(after, id); r++) {
              (covered[id] ??= {}).add(r);
            }
          }
        case RecoveryKind.unpairing:
          for (final id in m.sectionIds) {
            if (rounds(before, id) < m.round ||
                rounds(after, id) != m.round - 1) {
              wrong(
                p,
                'section $id went ${rounds(before, id)} → ${rounds(after, id)} rounds',
              );
            }
          }
        case RecoveryKind.import:
          if (after.players.length - before.players.length != m.players) {
            wrong(
              p,
              '${before.players.length} → ${after.players.length} players',
            );
          }
        case RecoveryKind.transfer:
          if (after.transitions.length <= before.transitions.length) {
            wrong(p, 'no move recorded');
          }
      }
    }
    for (final s in e.sections.where((s) => !s.sideGames)) {
      for (var r = 1; r <= s.rounds.length; r++) {
        if (!(covered[s.id] ?? const {}).contains(r)) {
          throw Violation(
            'recovery-coverage',
            '${s.name} round $r has no "before pairings" point.',
          );
        }
      }
    }
    final some = c.recoveryPoints(limit: 3);
    for (final (i, p) in some.take(min(3, points.length)).indexed) {
      if (p.node != points[i].node || p.mark.title != points[i].mark.title) {
        throw Violation(
          'recovery-limit',
          'A limited walk is not a prefix of the full one.',
        );
      }
    }
  }

  final _committed = <String>{};

  void _checkPersistence(String name) {
    final saved = _repo.load();
    if (saved == null || saved.encode() != e.encode()) {
      throw Violation(
        'persistence',
        'After $name the saved rows differ from the event in memory.',
      );
    }
    final graph = c.graph;
    final head = graph.head;
    if (head == null || _content(_repo.snapshot(head)) != _content(e)) {
      throw Violation(
        'history-head',
        'After $name the current history node is not the current event.',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Whole-state invariants, checked after every step.

  void _checkState(Event before) {
    final e = this.e;
    for (final s in e.sections) {
      maxRounds = max(maxRounds, s.rounds.length);
    }
    try {
      validateEvent(e);
    } on TournamentException catch (x) {
      throw Violation('invalid-event', x.message);
    }
    _total('history summary', () => summarizeStep(before, e));
    _total('play lost', () => playLost(before, e));
    _total('wall chart', () => wallChart(e));
    _total('crosstable', () => crosstable(e));
    _total('standings CSV', () => standingsCsv(e));
    _total('prize report', () => prizeReport(e));
    final issues = _total('rating issues', () => ratingIssues(e));
    if (issues != null && issues.every((i) => !i.blocking)) {
      // The preflight said the report can be made, so it must be.
      try {
        ratingPackage(e);
      } catch (error, stack) {
        throw Violation(
          'preflight-lied',
          'Preflight passed but the rating report failed: $error',
          errorType: '${error.runtimeType}',
          stack: stack,
        );
      }
    }
    for (final s in e.sections) {
      final rows = _total('standings ${s.name}', () => standings(e, s));
      if (rows != null) _checkStandings(e, s, rows);
      for (final id in s.players) {
        _total('rating preview', () => previewRating(e, s, e.player(id)));
      }
    }
  }

  /// A derived view may refuse plainly, never crash.
  T? _total<T>(String name, T Function() view) {
    try {
      return view();
    } on TournamentException {
      return null;
    } catch (error, stack) {
      throw Violation(
        'view-crash',
        '$name threw $error',
        errorType: '${error.runtimeType}',
        stack: stack,
      );
    }
  }

  /// Points are conserved: each player's score is their game scores plus
  /// their byes, and ranks only tie on equal keys.
  void _checkStandings(Event e, Section s, List<Standing> rows) {
    final simple =
        !s.sideGames &&
        !s.doubleGames &&
        (s.format == Format.swiss ||
            s.format == Format.roundRobin ||
            s.format == Format.quad) &&
        !e.transitions.any(
          (t) => t['target'] == s.id || (t['source'] ?? '') == s.id,
        ) &&
        !e.players.any(
          (p) => s.players.contains(p.id) && p.reentryOf.isNotEmpty,
        );
    if (simple) {
      final expected = <String, int>{};
      for (final r in s.rounds) {
        for (final g in r.games.where((g) => g.outcome.resolved)) {
          expected[g.white] = (expected[g.white] ?? 0) + g.outcome.whiteScore;
          expected[g.black] = (expected[g.black] ?? 0) + g.outcome.blackScore;
        }
        for (final b in r.byes) {
          expected[b.player] = (expected[b.player] ?? 0) + b.points;
        }
      }
      for (final row in rows) {
        final want = expected[row.player.id] ?? 0;
        if (row.points != want) {
          throw Violation(
            'points',
            '${s.name}: ${row.player.name} has ${row.points} half-points; games and byes give $want.',
          );
        }
      }
    }
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].rank < rows[i - 1].rank) {
        throw Violation('ranks', '${s.name}: ranks decrease at row $i.');
      }
    }
  }

  /// Checks a round just posted against the state it was paired from.
  /// [kept] names games a 29G3 repair kept as they were; a kept board with a
  /// result may name a player who has since withdrawn.
  void _checkPosted(
    Event before,
    Section s,
    Round round, {
    Set<String> kept = const {},
  }) {
    if (s.format != Format.swiss || round.policy == 'td-side-games') return;
    final explained = round.explanations.join(' ');
    final played = <String>{
      for (final r in s.rounds)
        for (final g in r.games.where((g) => g.outcome.played))
          ([g.white, g.black]..sort()).join('/'),
    };
    final allocated = <String>{
      for (final r in s.rounds)
        for (final b in r.byes.where((b) => b.allocated)) b.player,
    };
    for (final g in round.games) {
      // A kept board may name a player who withdrew after it was scored,
      // never one still waiting to start.
      if (kept.contains(g.id) && g.outcome != Outcome.unreported) continue;
      for (final id in [g.white, g.black]) {
        final p = before.player(id);
        if (p.withdrawn) {
          throw Violation(
            'paired-withdrawn',
            'Round ${round.number} paired withdrawn ${p.name}.',
          );
        }
        if (p.byes.containsKey(round.number)) {
          throw Violation(
            'paired-bye',
            'Round ${round.number} paired ${p.name}, who reserved a bye.',
          );
        }
      }
      final pair = ([g.white, g.black]..sort()).join('/');
      if (played.contains(pair) && !explained.contains('27A1')) {
        throw Violation(
          'repeat-pairing',
          'Round ${round.number} repeats a played pairing without 27A1: '
              '${before.player(g.white).name} – ${before.player(g.black).name}'
              '${kept.contains(g.id) ? ' (kept by the re-pairing)' : ''}.',
        );
      }
    }
    for (final b in round.byes.where((b) => b.allocated)) {
      if (allocated.contains(b.player) && !b.reason.contains('28L3')) {
        throw Violation(
          'second-bye',
          'Round ${round.number} gave a second full-point bye without 28L3.',
        );
      }
    }
    final seen = <String>[
      for (final g in round.games) ...[g.white, g.black],
      for (final b in round.byes) b.player,
    ];
    final eligible = [
      for (final id in s.players)
        if (!before.player(id).withdrawn) id,
    ];
    // Everyone eligible appears exactly once: in a game or with a bye.
    if (seen.toSet().length != seen.length || !eligible.every(seen.contains)) {
      throw Violation(
        'round-roster',
        'Round ${round.number} of ${s.name} does not hold every active player once.',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Choices, resolved against the current event.

  /// The candidate whose identity hashes lowest with [arg]: rendezvous
  /// hashing, so the choice survives the deletion of any other candidate.
  X? _pick<X extends Object>(List<X> xs, int arg) {
    X? best;
    int? low;
    for (final x in xs) {
      final h = _mix(arg, _key(x));
      if (low == null || h < low) {
        best = x;
        low = h;
      }
    }
    return best;
  }

  /// A coin flip per candidate that is stable in the same way.
  bool _flip(Object x, int arg) => _mix(arg, _key(x)).isOdd;

  final _gameKeys = <String, String>{};
  String _key(Object x) => switch (x) {
    Player p => p.id,
    Section s => s.id,
    Game g => _gameKeys[g.id] ?? g.id,
    _ => '$x',
  };

  /// The same hash, for the UI fuzzer's choices.
  static int mixForUi(int arg, String key) => _mix(arg, key);

  /// FNV-1a over [key] seeded with [arg], then a murmur3 finalizer.
  static int _mix(int arg, String key) {
    var h = 0x811c9dc5 ^ (arg & 0xffffffff);
    for (final u in key.codeUnits) {
      h = ((h ^ u) * 0x01000193) & 0xffffffff;
    }
    h ^= h >> 16;
    h = (h * 0x85ebca6b) & 0xffffffff;
    h ^= h >> 13;
    h = (h * 0xc2b2ae35) & 0xffffffff;
    return h ^ (h >> 16);
  }

  List<Player> get _players => e.players;
  List<Section> get _sections => e.sections.where((s) => !s.sideGames).toList();

  /// Games, identified by section, round and players: proposals mint
  /// random game IDs, and boards move when a round is re-paired.
  List<Game> _games({bool Function(Game)? where}) {
    final out = <Game>[];
    for (final s in e.sections) {
      for (final r in s.rounds) {
        for (final g in r.games) {
          _gameKeys[g.id] =
              '${s.id}/${r.number}/${g.white}/${g.black}/${g.leg}';
          if (where == null || where(g)) out.add(g);
        }
      }
    }
    return out;
  }

  Player _newPlayer(int nameArg, int ratingArg, int memberArg) {
    final id = _ids();
    final rating = ratingArg % 7 == 0 ? 0 : 100 + ratingArg.abs() % 2600;
    // A small ID pool so duplicate registrations happen.
    final member = memberArg % 3 == 0
        ? ''
        : '${12340000 + memberArg.abs() % 40}';
    return Player(
      id: id,
      name: '${_names[nameArg.abs() % _names.length]} ${id.substring(1)}',
      rating: rating,
      memberId: member,
      checkedIn: nameArg.isEven,
    );
  }

  void _skip() => skipped++;

  static bool _readyToPair(Section s) =>
      s.players.isNotEmpty &&
      !s.sideGames &&
      s.format != Format.ladder &&
      (s.format == Format.knockout || s.rounds.length < s.plannedRounds) &&
      s.rounds.every((r) => r.complete);

  Future<void> _step(Act a) async {
    _games(); // names every game for _pick
    switch (a.kind) {
      case 'register':
        _call(
          'register',
          () => c.savePlayer(_newPlayer(a.arg(0), a.arg(1), a.arg(2))),
        );
      case 'import':
        final n = 1 + a.arg(0).abs() % 12;
        _call(
          'import',
          () => c.importPlayers([
            for (var i = 0; i < n; i++)
              _newPlayer(a.arg(1) + i, a.arg(2) * (i + 1), a.arg(3) + i),
          ]),
        );
      case 'editRating':
        final p = _pick(_players, a.arg(0));
        if (p == null) return _skip();
        _call(
          'editRating',
          () => c.savePlayer(p.copy(rating: a.arg(1).abs() % 2800)),
        );
      case 'addSection':
        final format = _formats[a.arg(0).abs() % _formats.length];
        final rounds = format == Format.quad ? 3 : 2 + a.arg(1).abs() % 5;
        _call(
          'addSection',
          () => c.addSection(
            'Section ${a.arg(2).abs() % 6}',
            format,
            rounds,
            assignUnassigned: a.arg(3).isEven,
          ),
        );
      case 'applyQuads':
        _call('applyQuads', () => c.applyQuads(c.quadPreview(), e.revision));
      case 'move':
        final p = _pick(_players, a.arg(0)), s = _pick(_sections, a.arg(1));
        if (p == null || s == null) return _skip();
        _call(
          'move',
          () => c.movePlayers(
            [p.id],
            s.id,
            reason: a.arg(2).isEven ? '' : 'Moved up',
          ),
        );
      case 'remove':
        final p = _pick(_players, a.arg(0));
        if (p == null) return _skip();
        _call('remove', () => c.removePlayers([p.id]));
      case 'bye':
        final p = _pick(_players, a.arg(0));
        if (p == null) return _skip();
        final posted = e.sectionOf(p.id)?.rounds.length ?? 0;
        final round = posted + 1 + a.arg(1).abs() % 3;
        final points = a.arg(2).abs() % 4 - 1;
        _call(
          'bye',
          () => c.reserveBye(
            p.id,
            round,
            points,
            irrevocable: a.arg(3) % 3 == 0 ? true : null,
          ),
        );
      case 'avoid':
        final p = _pick(_players, a.arg(0)), q = _pick(_players, a.arg(1));
        if (p == null || q == null) return _skip();
        _call('avoid', () => c.avoidPair(p.id, q.id, a.arg(2).isEven));
      case 'team':
        final p = _pick(_players, a.arg(0));
        if (p == null) return _skip();
        _call(
          'team',
          () => c.assignTeam([
            p.id,
          ], ['', 'Knights', 'Rooks'][a.arg(1).abs() % 3]),
        );
      case 'withdraw':
        final p = _pick(_players, a.arg(0));
        if (p == null) return _skip();
        _call('withdraw', () => c.setWithdrawn([p.id], a.arg(1) % 4 != 0));
      case 'removeSection':
        final s = _pick(_sections, a.arg(0));
        if (s == null) return _skip();
        _call('removeSection', () => c.removeSection(s.id));
      case 'details':
        _call(
          'details',
          () => c.change(
            'Edit event details',
            e.copy(
              tdId: '12345678',
              affiliateId: 'A6012345',
              timeControl: 'G/30;d5',
              city: 'Boston',
              state: 'MA',
              zip: '02116',
              date: '2026-10-03',
            ),
          ),
        );
      case 'pair':
        // Mostly a section that is ready, sometimes all, sometimes any.
        final ready = [
          for (final s in _sections)
            if (_readyToPair(s)) s,
        ];
        final s = switch (a.arg(0) % 6) {
          0 => null,
          1 => _pick(_sections, a.arg(0)),
          _ => _pick(ready, a.arg(0)) ?? _pick(_sections, a.arg(0)),
        };
        final before = e;
        final batch = await _propose(s?.id, a.arg(1).isEven);
        if (batch == null) return;
        _call('post', () => c.post(batch));
        if (e.revision == before.revision) return;
        for (final s in e.sections) {
          final was = before.sections.where((x) => x.id == s.id).firstOrNull;
          if (was != null && s.rounds.length == was.rounds.length + 1) {
            _checkPosted(before, was, s.rounds.last);
          }
        }
      case 'start':
        final waiting = [
          for (final s in _sections)
            if (s.rounds.isNotEmpty &&
                s.rounds.last.startedAt == null &&
                !s.rounds.last.hasPlay)
              s,
        ];
        final s = a.arg(1) % 5 == 0
            ? _pick(_sections, a.arg(0))
            : _pick(waiting, a.arg(0));
        if (s == null) return _skip();
        _call('start', () => c.startRound(s.id));
      case 'result':
        // Mostly the current round's empty boards, as at the score table.
        final open = _games(where: (g) => !g.outcome.resolved);
        final g = _pick(
          open.isEmpty || a.arg(2) % 5 == 0 ? _games() : open,
          a.arg(0),
        );
        if (g == null) return _skip();
        _call(
          'result',
          () => c.recordResult(
            g.id,
            _outcomes[a.arg(1).abs() % _outcomes.length],
          ),
        );
      case 'resultWithReason':
        final g = _pick(_games(), a.arg(0));
        if (g == null) return _skip();
        _call(
          'resultWithReason',
          () => c.recordResult(
            g.id,
            _outcomes[a.arg(1).abs() % _outcomes.length],
            reason: 'Players agreed the scoresheet was wrong',
          ),
        );
      case 'assume':
        final g = _pick(_games(where: (g) => !g.outcome.resolved), a.arg(0));
        if (g == null) return _skip();
        _call(
          'assume',
          () => c.setPairingAssumption(
            g.id,
            [Outcome.whiteWin, Outcome.draw, Outcome.blackWin][a.arg(1).abs() %
                3],
            'Adjourned to the side room',
          ),
        );
      case 'holdOut':
        final s = _pick(_sections, a.arg(0));
        if (s == null) return _skip();
        _call(
          'holdOut',
          () => c.holdOutNonReporters(
            s.id,
            treatment: NonReporterTreatment.values[a.arg(1).abs() % 2],
          ),
        );
      case 'sideGame':
        final p = _pick(_players, a.arg(0)), q = _pick(_players, a.arg(1));
        if (p == null || q == null) return _skip();
        _call('sideGame', () => c.addSideGame(p.id, q.id));
      case 'ruling':
        final p = _pick(_players, a.arg(1));
        _call(
          'ruling',
          () => c.logRuling(
            kind: rulingKindsList[a.arg(0).abs() % rulingKindsList.length],
            text: 'Illegal move claim on board 3',
            players: [?p?.id],
          ),
        );
      case 'correct':
        final g = _pick(_games(where: (g) => g.outcome.resolved), a.arg(0));
        if (g == null) return _skip();
        final review = _call('review', () => c.reviewResult(g.id));
        if (review == null) return;
        final later = review.later.map((r) => r.number).toList();
        final reopen = a.arg(2).isEven ? null : _pick(later, a.arg(3));
        _call(
          'correct',
          () => c.correctResult(
            review,
            _outcomes[a.arg(1).abs() % 9],
            reason: 'Wrong result reported',
            reopenFrom: reopen,
            confirmedUnstarted: a.arg(4) % 4 != 0,
          ),
        );
      case 'repair':
        final s = _pick(_sections, a.arg(0));
        if (s == null || s.rounds.isEmpty) return _skip();
        final games = [...s.rounds.last.games]
          ..sort((x, y) => x.board.compareTo(y.board));
        final keep = [
          for (final (i, g) in games.indexed)
            if (_flip(g, a.arg(1) + i)) g.id,
        ];
        _call(
          'repair',
          () => c.repairUnstarted(
            s.id,
            keep,
            a.arg(2) % 5 == 0 ? '' : 'Late withdrawal',
          ),
        );
      case 'partners':
        // Bughouse: partner the section's players in a stable shuffled order.
        final s = _pick([
          for (final s in _sections)
            if (s.format == Format.bughouse && s.rounds.isEmpty) s,
        ], a.arg(0));
        if (s == null) return _skip();
        final order = [...s.players]
          ..sort((x, y) => _mix(a.arg(1), x).compareTo(_mix(a.arg(1), y)));
        _call(
          'partners',
          () => c.setPartners(s.id, [
            for (var i = 0; i + 1 < order.length; i += 2)
              [order[i], order[i + 1]],
          ]),
        );
      case 'homeTeam':
        // Scheveningen: name side A, after teams are assigned.
        final s = _pick([
          for (final s in _sections)
            if (s.format == Format.scheveningen && s.rounds.isEmpty) s,
        ], a.arg(0));
        if (s == null) return _skip();
        for (final id in s.players) {
          _call(
            'team',
            () => c.assignTeam([
              id,
            ], _mix(a.arg(1), id).isEven ? 'Knights' : 'Rooks'),
          );
        }
        _call(
          'homeTeam',
          () => c.change(
            'Set home team',
            e.copy(
              sections: [
                for (final x in e.sections)
                  x.id == s.id ? x.copy(homeTeam: 'Knights') : x,
              ],
            ),
          ),
        );
      case 'ladderGame':
        final s = _pick([
          for (final s in _sections)
            if (s.format == Format.ladder && s.players.length > 1) s,
        ], a.arg(0));
        if (s == null) return _skip();
        // Challengers mostly reach up a few rungs, as ladder rules expect.
        final i = 1 + a.arg(1).abs() % (s.players.length - 1);
        final j = max(0, i - 1 - a.arg(2).abs() % 3);
        _call(
          'ladderGame',
          () => c.recordLadderGame(
            s.id,
            s.players[i],
            s.players[j],
            _outcomes[a.arg(3).abs() % 9],
            challengerWhite: a.arg(4).isEven,
          ),
        );
      case 'ladderOrder':
        final s = _pick([
          for (final s in _sections)
            if (s.format == Format.ladder && s.players.length > 1) s,
        ], a.arg(0));
        if (s == null) return _skip();
        final order = [...s.players];
        final i = a.arg(1).abs() % order.length,
            j = a.arg(2).abs() % order.length;
        order[i] = s.players[j];
        order[j] = s.players[i];
        _call(
          'ladderOrder',
          () => c.setLadderOrder(s.id, order, 'Late arrival placed by rating'),
        );
      case 'advance':
        // Knockout: the TD decides a drawn match.
        final s = _pick([
          for (final s in _sections)
            if (s.format == Format.knockout && s.rounds.isNotEmpty) s,
        ], a.arg(0));
        if (s == null) return _skip();
        final g = _pick(s.rounds.last.games, a.arg(1));
        if (g == null) return _skip();
        _call(
          'advance',
          () => c.advanceKnockout(
            s.id,
            g.board,
            a.arg(2).isEven ? g.white : g.black,
            reason: 'Armageddon won',
          ),
        );
      case 'withdrawWaiting':
        // A player leaves before their board starts, and the TD has not yet
        // re-paired: the opponent's board still names them.
        final waiting = _games(
          where: (g) =>
              g.outcome == Outcome.unreported && g.pairingAssumption == null,
        );
        final g = _pick(waiting, a.arg(0));
        if (g == null) return _skip();
        _call(
          'withdraw',
          () => c.setWithdrawn([a.arg(1).isEven ? g.white : g.black], true),
        );
      case 'lateWithdraw':
        // Rule 29G3: a player withdraws after posting; the TD keeps the
        // boards that started and re-pairs the waiting ones.
        final s = _pick([
          for (final s in _sections)
            if (s.format == Format.swiss &&
                s.rounds.isNotEmpty &&
                s.rounds.last.games.any((g) => g.outcome == Outcome.unreported))
              s,
        ], a.arg(0));
        if (s == null) return _skip();
        final games = [...s.rounds.last.games]
          ..sort((x, y) => x.board.compareTo(y.board));
        final waiting = [
          for (final g in games)
            if (g.outcome == Outcome.unreported && g.pairingAssumption == null)
              g,
        ];
        final victim = _pick(waiting, a.arg(1));
        if (victim == null) return _skip();
        _call(
          'withdraw',
          () => c.setWithdrawn([
            a.arg(2).isEven ? victim.white : victim.black,
          ], true),
        );
        final before = e;
        final keep = [
          for (final (i, g) in games.indexed)
            if (g.id != victim.id &&
                (!waiting.contains(g) || _flip(g, a.arg(3) + i)))
              g.id,
        ];
        _call(
          'lateWithdraw',
          () => c.repairUnstarted(s.id, keep, 'Withdrew after pairings'),
        );
        if (e.revision != before.revision) {
          final now = e.sections.firstWhere((x) => x.id == s.id);
          final was = now.copy(
            rounds: now.rounds.take(now.rounds.length - 1).toList(),
          );
          _checkPosted(before, was, now.rounds.last, kept: {...keep});
        }
      case 'replace':
        final s = _pick(_sections, a.arg(0));
        if (s == null || s.rounds.isEmpty) return _skip();
        // Mostly a round nobody has started, which can still be replaced.
        final waiting = [
          for (final r in s.rounds)
            if (!r.hasPlay) r.number,
        ];
        final n = a.arg(1) % 4 != 0 && waiting.isNotEmpty
            ? _pick(waiting, a.arg(1))!
            : 1 + a.arg(1).abs() % s.rounds.length;
        final games = [...s.rounds[n - 1].games]
          ..sort((x, y) => x.board.compareTo(y.board));
        if (games.isEmpty) return _skip();
        final replaced = [...games];
        final i = a.arg(2).abs() % games.length;
        if (a.arg(3).isEven || games.length < 2) {
          // Swap colors on one board.
          replaced[i] = games[i].copy(
            white: games[i].black,
            black: games[i].white,
          );
        } else {
          // Swap the black players of two boards.
          final j =
              (i + 1 + a.arg(4).abs() % (games.length - 1)) % games.length;
          replaced[i] = games[i].copy(black: games[j].black);
          replaced[j] = games[j].copy(black: games[i].black);
        }
        _call(
          'replace',
          () => c.replacePairing(s.id, n, replaced, 'Board order corrected'),
        );
      case 'undo':
        final accept = a.arg(0).isEven;
        _historyMove(
          'undo',
          c.graph.back,
          accept,
          () => c.undo(acceptLosses: accept),
        );
      case 'redo':
        final accept = a.arg(0).isEven;
        _historyMove(
          'redo',
          c.graph.forward,
          accept,
          () => c.redo(acceptLosses: accept),
        );
      case 'restore':
        final nodes = c.graph.nodes.keys.toList()..sort();
        final node = _pick(nodes, a.arg(0));
        if (node == null) return _skip();
        final accept = a.arg(1).isEven;
        _historyMove(
          'restore',
          node,
          accept,
          () => c.restore(node, acceptLosses: accept),
        );
      case 'roundTrip':
        // Undo then Redo is the identity, on content and on the graph.
        if (!c.canUndo) return _skip();
        final from = _content(e), head = c.graph.head;
        _historyMove(
          'undo',
          c.graph.back,
          true,
          () => c.undo(acceptLosses: true),
        );
        _historyMove(
          'redo',
          c.graph.forward,
          true,
          () => c.redo(acceptLosses: true),
        );
        if (_content(e) != from || c.graph.head != head) {
          throw Violation(
            'round-trip',
            'Undo then Redo did not return to the same version.',
          );
        }
      case 'stalePost':
        final batch = await _propose(null, false);
        if (batch == null || batch.rounds.isEmpty) return _skip();
        final p = _pick(_players, a.arg(0));
        if (p == null) return _skip();
        final rev = e.revision;
        _call('stale edit', () => c.assignTeam([p.id], 'Stale ${e.revision}'));
        if (e.revision == rev) return;
        _call('stalePost', () => c.post(batch), mustRefuse: true);
      case 'staleCorrect':
        final g = _pick(_games(where: (g) => g.outcome.resolved), a.arg(0));
        final p = _pick(_players, a.arg(1));
        if (g == null || p == null) return _skip();
        final review = _call('review', () => c.reviewResult(g.id));
        if (review == null) return;
        final rev = e.revision;
        _call('stale edit', () => c.assignTeam([p.id], 'Stale ${e.revision}'));
        if (e.revision == rev) return;
        _call(
          'staleCorrect',
          () => c.correctResult(review, Outcome.draw, reason: 'stale'),
          mustRefuse: true,
        );
      case 'reopen':
        final last = _content(e);
        close();
        open();
        if (_content(e) != last) {
          throw Violation(
            'reopen',
            'Reopened file differs from the event in memory.',
          );
        }
      default:
        throw ArgumentError('Unknown step ${a.kind}');
    }
  }

  Future<PairingBatch?> _propose(String? sectionId, bool onlyReady) async {
    commands++;
    final before = _content(e), rev = e.revision;
    try {
      return await c.propose(sectionId: sectionId, onlyReady: onlyReady);
    } on TournamentException {
      refused++;
      return null;
    } catch (error, stack) {
      throw Violation(
        'crash',
        'propose threw $error',
        errorType: '${error.runtimeType}',
        stack: stack,
      );
    } finally {
      if (e.revision != rev || _content(e) != before) {
        throw Violation(
          'propose-changed',
          'Proposing pairings changed the event.',
        );
      }
    }
  }
}

final rulingKindsList = ['ruling', 'penalty', 'appeal', 'adjudication'];

class TraceFailure implements Exception {
  TraceFailure(this.step, this.act, this.violation);
  final int step;
  final Act act;
  final Violation violation;
  @override
  String toString() => 'step $step $act: $violation';
}

// -----------------------------------------------------------------------
// Generation: a Markov chain over tournament phases.

/// Step weights by phase. Setup builds rosters and sections; play pairs and
/// scores; chaos is the repair engine a TD reaches for after a mistake.
const _setup = {
  'register': 6,
  'import': 3,
  'editRating': 2,
  'addSection': 3,
  'applyQuads': 1,
  'move': 2,
  'remove': 1,
  'bye': 3,
  'avoid': 1,
  'team': 1,
  'withdraw': 1,
  'removeSection': 1,
  'details': 1,
  'partners': 2,
  'homeTeam': 2,
  'pair': 4,
};
const _play = {
  'pair': 5,
  'start': 2,
  'result': 20,
  'assume': 1,
  'holdOut': 1,
  'sideGame': 1,
  'ruling': 1,
  'bye': 2,
  'withdraw': 2,
  'register': 1,
  'reopen': 1,
  'ladderGame': 2,
  'ladderOrder': 1,
  'advance': 1,
};
const _nextEvent = {
  'import': 4,
  'register': 2,
  'addSection': 6,
  'applyQuads': 1,
  'move': 1,
  'details': 1,
  'pair': 3,
  'ladderGame': 1,
};
const _chaos = {
  'lateWithdraw': 3,
  'withdrawWaiting': 2,
  'correct': 5,
  'resultWithReason': 2,
  'repair': 3,
  'replace': 3,
  'undo': 4,
  'redo': 2,
  'roundTrip': 2,
  'restore': 3,
  'stalePost': 2,
  'staleCorrect': 2,
  'withdraw': 2,
  'remove': 1,
  'move': 1,
  'reopen': 1,
};

/// Play weights follow the hall: while boards are open the TD enters
/// results; once a section is ready, pairing and starting the next round.
Map<String, int> _adjustedPlay(Event e) {
  final open = e.games.any((g) => !g.outcome.resolved);
  final ready = e.sections.any(Harness._readyToPair);
  final unstarted = e.sections.any(
    (s) =>
        s.rounds.isNotEmpty &&
        s.rounds.last.startedAt == null &&
        !s.rounds.last.hasPlay,
  );
  return {
    ..._play,
    'pair': ready ? 12 : 1,
    'result': open ? 20 : 2,
    'start': unstarted ? 4 : 0,
    'holdOut': open ? 1 : 0,
    'assume': open ? 1 : 0,
  };
}

String _weighted(Random rng, Map<String, int> weights) {
  var roll = rng.nextInt(weights.values.fold(0, (a, b) => a + b));
  for (final MapEntry(:key, :value) in weights.entries) {
    if ((roll -= value) < 0) return key;
  }
  throw StateError('unreachable');
}

/// The next step for the state [e] is in.
Act generate(Random rng, Event e, int tag) {
  final paired = e.sections.any((s) => s.rounds.isNotEmpty);
  // Every section played out: like a club's next event, add sections and
  // players rather than knock on closed rounds.
  final idle =
      paired &&
      !e.games.any((g) => !g.outcome.resolved) &&
      !e.sections.any(Harness._readyToPair);
  final phase = rng.nextInt(100) < (paired ? 18 : 4)
      ? _chaos
      : idle
      ? _nextEvent
      : (!paired && e.players.length < 6) ||
            rng.nextInt(100) < (paired ? 8 : 70)
      ? _setup
      : _adjustedPlay(e);
  return Act(_weighted(rng, phase), [
    for (var i = 0; i < 5; i++) rng.nextInt(1 << 16),
  ], tag);
}

/// Generates and runs one seeded trace of [steps] steps. Returns the trace
/// and the failure, if any.
Future<(List<Act>, TraceFailure?, Harness)> fuzzOnce(
  int seed,
  int steps,
  Directory dir, {
  bool strict = false,
}) async {
  final rng = Random(seed);
  final trace = <Act>[];
  final h = Harness(dir, strict: strict);
  // Generation needs the live event, so it runs inside the harness loop.
  final generated = _GeneratingTrace(rng, steps, trace, h);
  try {
    await h.run(generated);
    return (trace, null, h);
  } on TraceFailure catch (f) {
    return (trace.take(f.step + 1).toList(), f, h);
  }
}

/// A trace that generates each step from the live event just before it runs.
class _GeneratingTrace extends Iterable<Act> {
  _GeneratingTrace(this.rng, this.steps, this.out, this.h);
  final Random rng;
  final int steps;
  final List<Act> out;
  final Harness h;
  @override
  Iterator<Act> get iterator => _Gen(this);
}

class _Gen implements Iterator<Act> {
  _Gen(this.t);
  final _GeneratingTrace t;
  Act? _current;
  @override
  Act get current => _current!;
  @override
  bool moveNext() {
    if (t.out.length >= t.steps) return false;
    _current = generate(t.rng, t.h.e, t.out.length);
    t.out.add(_current!);
    return true;
  }
}

// -----------------------------------------------------------------------
// Shrinking.

/// Replays [trace] in a fresh event; the failure, or null if it passes.
Future<TraceFailure?> replay(
  List<Act> trace,
  Directory parent, {
  bool strict = false,
}) async {
  final dir = parent.createTempSync('replay-');
  try {
    await Harness(dir, strict: strict).run(trace);
    return null;
  } on TraceFailure catch (f) {
    return f;
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Delta debugging (Zeller's ddmin) over steps, then over each step's
/// arguments: the smallest trace that still fails with [signature].
Future<List<Act>> shrink(
  List<Act> trace,
  String signature,
  Directory parent, {
  int budget = 400,
  bool strict = false,
}) => shrinkWith(trace, (t) async {
  final f = await replay(t, parent, strict: strict);
  return f != null && f.violation.signature == signature;
}, budget: budget);

/// [shrink] for any runner: [fails] says whether a trace still fails the
/// same way.
Future<List<Act>> shrinkWith(
  List<Act> trace,
  Future<bool> Function(List<Act>) failsSame, {
  int budget = 400,
}) async {
  var runs = 0;
  Future<bool> fails(List<Act> t) async =>
      runs++ < budget && await failsSame(t);

  var current = trace;
  var n = 2;
  while (current.length >= 2 && runs < budget) {
    final chunk = (current.length / n).ceil();
    var reduced = false;
    for (var start = 0; start < current.length; start += chunk) {
      final complement = [
        ...current.take(start),
        ...current.skip(start + chunk),
      ];
      if (complement.isNotEmpty && await fails(complement)) {
        current = complement;
        n = max(n - 1, 2);
        reduced = true;
        break;
      }
    }
    if (!reduced) {
      if (n >= current.length) break;
      n = min(n * 2, current.length);
    }
  }
  // Single-step deletions catch what chunking missed.
  for (var i = current.length - 1; i >= 0 && runs < budget; i--) {
    final without = [...current]..removeAt(i);
    if (without.isNotEmpty && await fails(without)) current = without;
  }
  // Smaller arguments read better: try zeroing each.
  for (var i = 0; i < current.length && runs < budget; i++) {
    for (var j = 0; j < current[i].args.length; j++) {
      if (current[i].args[j] == 0) continue;
      final simpler = [...current];
      simpler[i] = current[i].withArgs([...current[i].args]..[j] = 0);
      if (await fails(simpler)) current = simpler;
    }
  }
  return current;
}
