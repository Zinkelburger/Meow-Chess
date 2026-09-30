import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../domain/history.dart';
import '../domain/model.dart';
import '../domain/pairing.dart';
import 'event_repository.dart';

class PairingBatch {
  const PairingBatch(this.revision, this.rounds, this.issues);
  final int revision;
  final Map<String, Round> rounds;
  final Map<String, String> issues;
}

class TournamentController extends ChangeNotifier {
  TournamentController(this.repository) : event = repository.load();
  final EventRepository repository;
  Event? event;
  String? backupWarning;
  bool _closed = false;
  String newId() => const Uuid().v4();
  void create(String name, {bool practice = false}) => change(
    'Create event',
    Event(
      id: newId(),
      name: name,
      date: DateTime.now().toIso8601String().substring(0, 10),
      practice: practice,
    ),
  );

  /// Commits [next] as one audited revision. A command that changes nothing
  /// (a retried click, an unchanged dialog) is acknowledged without a revision.
  void change(String action, Event next) {
    if (_closed) throw const TournamentException('This event has closed.');
    if (event != null && next.encode() == event!.encode()) return;
    event = repository.commit(
      next,
      expectedRevision: event?.revision ?? 0,
      action: action,
    );
    _graph = null;
    notifyListeners();
  }

  void savePlayer(Player player) {
    final e = event!;
    final duplicate = e.players
        .where(
          (p) =>
              p.id != player.id &&
              player.memberId.isNotEmpty &&
              p.memberId == player.memberId,
        )
        .firstOrNull;
    if (duplicate != null) {
      throw TournamentException(
        'That US Chess ID belongs to ${duplicate.name}. Resolve the identity before adding another entry.',
      );
    }
    final exists = e.players.any((p) => p.id == player.id);
    change(
      exists ? 'Edit ${player.name}' : 'Register ${player.name}',
      e.copy(
        players: exists
            ? e.players.map((p) => p.id == player.id ? player : p).toList()
            : [...e.players, player],
      ),
    );
  }

  /// Adds new entries and returns how many rows were skipped as existing.
  /// A member ID is identity; a name only identifies someone when either side
  /// lacks an ID, so two members who share a name are both admitted.
  int importPlayers(List<Player> players) {
    final e = event!;
    final ids = e.players
        .where((p) => p.memberId.isNotEmpty)
        .map((p) => p.memberId)
        .toSet();
    // Name -> whether every entry with that name has a member ID.
    final names = <String, bool>{};
    void remember(Player p) {
      final key = p.name.trim().toLowerCase();
      names[key] = (names[key] ?? true) && p.memberId.isNotEmpty;
    }

    e.players.forEach(remember);
    final additions = <Player>[];
    for (final player in players) {
      if (player.memberId.isNotEmpty && ids.contains(player.memberId)) continue;
      final allIdentified = names[player.name.trim().toLowerCase()];
      if (allIdentified != null &&
          !(allIdentified && player.memberId.isNotEmpty)) {
        continue;
      }
      if (player.memberId.isNotEmpty) ids.add(player.memberId);
      remember(player);
      additions.add(player);
    }
    if (additions.isEmpty) {
      throw const TournamentException(
        'No new entries. Existing names and IDs are preserved.',
      );
    }
    change(
      'Import ${additions.length} players',
      e.copy(players: [...e.players, ...additions]),
    );
    return players.length - additions.length;
  }

  Section _section(String id) =>
      event!.sections.where((s) => s.id == id).firstOrNull ??
      (throw const TournamentException('That section no longer exists.'));
  Game _game(String id) =>
      event!.games.where((g) => g.id == id).firstOrNull ??
      (throw const TournamentException('The selected game no longer exists.'));

  List<Section> quadPreview() => makeQuads(event!, newId);
  void applyQuads(List<Section> sections, int expectedRevision) {
    if (event!.revision != expectedRevision) {
      throw const TournamentException(
        'The roster changed. Preview the groups again.',
      );
    }
    change('Make quads', event!.copy(sections: sections));
  }

  void addSection(
    String name,
    Format format,
    int rounds, {
    bool doubleGames = false,
  }) {
    final e = event!;
    final free = e.players
        .where((p) => !p.withdrawn && e.sectionOf(p.id) == null)
        .map((p) => p.id)
        .toList();
    final nextBoard = e.sections.fold(1, (int max, Section s) {
      final end = s.boardStart + (s.players.length + 1) ~/ 2;
      return end > max ? end : max;
    });
    change(
      'Create $name',
      e.copy(
        sections: [
          ...e.sections,
          Section(
            id: newId(),
            name: name,
            players: free,
            format: format,
            plannedRounds: rounds,
            boardStart: nextBoard,
            doubleGames: doubleGames,
          ),
        ],
      ),
    );
  }

  Future<PairingBatch> propose({String? sectionId}) async {
    final snapshot = event!;
    return Isolate.run(() {
      final rounds = <String, Round>{}, issues = <String, String>{};
      for (final s in snapshot.sections.where(
        (s) =>
            s.players.isNotEmpty &&
            (sectionId == null || s.id == sectionId) &&
            !s.finished,
      )) {
        try {
          rounds[s.id] = proposeRound(snapshot, s, () => const Uuid().v4());
        } on TournamentException catch (e) {
          issues[s.id] = e.message;
        }
      }
      return PairingBatch(snapshot.revision, rounds, issues);
    });
  }

  void post(PairingBatch batch) {
    final e = event!;
    if (batch.revision != e.revision) {
      throw const TournamentException(
        'The event changed while pairing. Generate a fresh proposal.',
      );
    }
    if (batch.rounds.isEmpty) {
      throw const TournamentException('No sections are ready to post.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = e.sections.map((s) {
      final r = batch.rounds[s.id];
      return r == null
          ? s
          : s.copy(
              // Record the format actually paired, so an odd-sized quad stays
              // a Swiss once play begins.
              format: pairingFormat(s),
              rounds: [
                ...s.rounds,
                r.copy(postedAt: now),
              ],
            );
    }).toList();
    // Board numbers reserve physical space across independently progressing sections.
    final busy = <int, String>{};
    for (final s in updated) {
      if (s.rounds.isEmpty) continue;
      final r = s.rounds.last;
      if (r.complete) continue;
      for (final g in r.games.where((g) => g.leg == 1)) {
        final prior = busy[g.board];
        if (prior != null) {
          throw TournamentException(
            'Board ${g.board} is already reserved by $prior. Adjust board ranges.',
          );
        }
        busy[g.board] = s.name;
      }
    }
    change(
      'Post ${batch.rounds.length} section${batch.rounds.length == 1 ? '' : 's'}',
      e.copy(sections: updated),
    );
    secondaryBackup();
  }

  void startRound(String sectionId) {
    final e = event!;
    final section = _section(sectionId);
    if (section.rounds.isEmpty) {
      throw const TournamentException('Post a round before starting it.');
    }
    if (section.rounds.last.startedAt != null) {
      throw const TournamentException('This round has already started.');
    }
    if (section.rounds.last.complete) {
      throw const TournamentException('This round is already complete.');
    }
    if (section.rounds
        .take(section.rounds.length - 1)
        .any((r) => !r.complete)) {
      throw const TournamentException(
        'Earlier games are still unresolved. A pairing assumption permits posting, not simultaneous play.',
      );
    }
    change(
      'Start round',
      e.copy(
        sections: e.sections
            .map(
              (s) => s.id != sectionId
                  ? s
                  : s.copy(
                      rounds: [
                        ...s.rounds.take(s.rounds.length - 1),
                        s.rounds.last.copy(
                          startedAt: DateTime.now().toUtc().toIso8601String(),
                        ),
                      ],
                    ),
            )
            .toList(),
      ),
    );
  }

  bool correctionHasDependencies(String gameId) {
    for (final s in event!.sections) {
      for (final (i, r) in s.rounds.indexed) {
        if (r.games.any((g) => g.id == gameId)) return i < s.rounds.length - 1;
      }
    }
    return false;
  }

  void recordResult(String gameId, Outcome outcome, {String reason = ''}) {
    final e = event!;
    final game = _game(gameId);
    if (game.outcome == outcome && game.note == reason) return;
    if (correctionHasDependencies(gameId) && reason.trim().isEmpty) {
      throw const TournamentException(
        'Explain the correction: later posted rounds will be retained and need review.',
      );
    }
    change(
      'Result, board ${game.board}',
      e.copy(
        sections: e.sections
            .map(
              (s) => s.copy(
                rounds: s.rounds
                    .map(
                      (r) => r.copy(
                        games: r.games
                            .map(
                              (g) => g.id == gameId
                                  ? g.copy(
                                      outcome: outcome,
                                      note: reason,
                                      // An assumption stands in only until
                                      // the game is resolved.
                                      pairingAssumption: outcome.resolved
                                          ? null
                                          : g.pairingAssumption,
                                      pairingReason: outcome.resolved
                                          ? ''
                                          : g.pairingReason,
                                    )
                                  : g,
                            )
                            .toList(),
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
  }

  void setPairingAssumption(String gameId, Outcome assumption, String reason) {
    final e = event!;
    final game = _game(gameId);
    if (game.outcome.resolved || !assumption.played || reason.trim().isEmpty) {
      throw const TournamentException(
        'Choose a win, draw or loss assumption for an unresolved game and record the TD’s reason.',
      );
    }
    change(
      'Temporary pairing treatment, board ${game.board}',
      e.copy(
        sections: [
          for (final s in e.sections)
            s.copy(
              rounds: [
                for (final r in s.rounds)
                  r.copy(
                    games: [
                      for (final g in r.games)
                        g.id == gameId
                            ? g.copy(
                                pairingAssumption: assumption,
                                pairingReason: reason,
                              )
                            : g,
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }

  void reserveBye(String playerId, int round, int points) {
    final e = event!;
    final s = e.sectionOf(playerId);
    if (s != null && round <= s.rounds.length) {
      throw const TournamentException(
        'That round is posted. Correct the existing game or replace the unstarted pairing.',
      );
    }
    final player = e.player(playerId);
    final byes = {...player.byes};
    if (points < 0) {
      byes.remove(round);
    } else {
      byes[round] = points;
    }
    savePlayer(player.copy(byes: byes));
  }

  void movePlayers(List<String> ids, String targetId, {String reason = ''}) {
    final e = event!;
    final target = _section(targetId);
    final unknown = ids.where((id) => !e.players.any((p) => p.id == id));
    if (unknown.isNotEmpty) {
      throw const TournamentException('A selected player no longer exists.');
    }
    final sources = e.sections
        .where((s) => s.id != targetId && s.players.any(ids.contains))
        .toList();
    // A round-robin schedule is derived from its full roster, so removing only
    // some players after play would silently re-pair earlier opponents.
    for (final s in sources) {
      if (s.format != Format.swiss &&
          s.rounds.isNotEmpty &&
          !s.players.every(ids.contains)) {
        throw TournamentException(
          '${s.name} is a ${s.format == Format.quad ? 'quad' : 'round robin'} with games played. Move all of its players together, or none.',
        );
      }
    }
    final affected = {...sources, target};
    if (affected.any((s) => s.rounds.any((r) => !r.complete))) {
      throw const TournamentException(
        'Complete the current games before a section transition.',
      );
    }
    if (affected.any((s) => s.rounds.length != target.rounds.length)) {
      throw const TournamentException(
        'These sections have different round progress. Resolve the schedule before combining.',
      );
    }
    if (affected.any((s) => s.rounds.isNotEmpty) && reason.trim().isEmpty) {
      throw const TournamentException(
        'Record the transition reason. Original games remain attributed to their source section; rating export needs a validated mapping.',
      );
    }
    final members = {...target.players, ...ids}.toList();
    // Before any play a move is only a roster edit; afterwards the merged
    // section's schedule no longer holds, so it continues as a Swiss.
    final played = affected.any((s) => s.rounds.isNotEmpty);
    final sections = e.sections
        .map(
          (s) => s.id == targetId
              ? s.copy(
                  players: members,
                  format: played ? Format.swiss : s.format,
                )
              : s.copy(
                  players: s.players.where((id) => !ids.contains(id)).toList(),
                ),
        )
        .toList();
    // Reallocate only future board ranges, keeping every historical game intact.
    var board = 1;
    final allocated = sections.map((s) {
      final out = s.copy(boardStart: board);
      board += (s.players.length + 1) ~/ 2;
      return out;
    }).toList();
    change(
      'Move ${ids.length} players to ${target.name}',
      e.copy(
        sections: allocated,
        transitions: [
          ...e.transitions,
          {
            'players': ids,
            'target': targetId,
            'effectiveRound': target.rounds.length + 1,
            'reason': reason,
            'revision': e.revision,
          },
        ],
      ),
    );
  }

  void replacePairing(
    String sectionId,
    int number,
    List<Game> games,
    String reason,
  ) {
    final e = event!;
    final s = _section(sectionId);
    if (number < 1 || number > s.rounds.length) {
      throw const TournamentException('That round has not been posted.');
    }
    final r = s.rounds[number - 1];
    if (r.hasPlay) {
      throw const TournamentException(
        'This round has started. Preserve its participants and correct results separately.',
      );
    }
    if (reason.trim().isEmpty) {
      throw const TournamentException(
        'Record why the posted pairing is changing.',
      );
    }
    final oldIds = r.games.expand((g) => [g.white, g.black]).toList()..sort();
    final newIds = games.expand((g) => [g.white, g.black]).toList()..sort();
    if (!listEquals(oldIds, newIds)) {
      throw const TournamentException(
        'Replacement must preserve the participants.',
      );
    }
    change(
      'Replace round $number pairings',
      e.copy(
        sections: e.sections
            .map(
              (s) => s.id != sectionId
                  ? s
                  : s.copy(
                      rounds: s.rounds
                          .map(
                            (r) => r.number == number
                                ? r.copy(
                                    games: games,
                                    revision: r.revision + 1,
                                    note: reason,
                                  )
                                : r,
                          )
                          .toList(),
                    ),
            )
            .toList(),
      ),
    );
  }

  HistoryGraph? _graph;
  HistoryGraph get graph => _graph ??= repository.historyGraph();

  /// The step Back would undo, and the one Forward would redo.
  String? get undoLabel =>
      graph.back == null ? null : graph.nodes[graph.head]?.action;
  String? get redoLabel => graph.nodes[graph.forward]?.action;
  bool get canUndo => graph.back != null;
  bool get canRedo => graph.forward != null;

  /// What happened at the board that moving to [node] would take away. The
  /// UI confirms these; nothing is lost for good, because the state being
  /// left stays in the graph.
  List<String> lossesTo(int node) =>
      playLost(event!, repository.snapshot(node));

  void undo({bool acceptLosses = false}) {
    if (!canUndo) return;
    _move(graph.back!, 'Undo $undoLabel', acceptLosses);
  }

  void redo({bool acceptLosses = false}) {
    if (!canRedo) return;
    _move(graph.forward!, 'Redo $redoLabel', acceptLosses);
  }

  void restore(int node, {bool acceptLosses = false}) {
    if (node == graph.head) return;
    _move(
      node,
      'Restore #$node · ${graph.nodes[node]?.action ?? ''}',
      acceptLosses,
    );
  }

  void _move(int node, String action, bool acceptLosses) {
    if (_closed) throw const TournamentException('This event has closed.');
    final target = repository.snapshot(node);
    // History before a copy was marked practice belongs to the original
    // event; restoring it would also restore that event's backup folder.
    if (event!.practice && !target.practice) {
      throw const TournamentException(
        'This practice copy cannot go back to before it was copied.',
      );
    }
    final lost = playLost(event!, target);
    if (lost.isNotEmpty && !acceptLosses) {
      throw TournamentException(
        'Going there removes play already recorded: ${lost.join('; ')}.',
      );
    }
    event = repository.checkout(
      node,
      expectedRevision: event!.revision,
      action: action,
    );
    _graph = null;
    notifyListeners();
  }

  void secondaryBackup() {
    final e = event!;
    if (e.backupFolder.isEmpty) return;
    try {
      final destination = p.join(
        e.backupFolder,
        '${e.id}-r${e.revision}-${DateTime.now().microsecondsSinceEpoch}.meow',
      );
      repository.backup(destination);
      repository.writePreference('lastBackup', '${e.revision}|$destination');
      backupWarning = null;
    } catch (error) {
      backupWarning = 'Saved locally, but secondary backup failed: $error';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    repository.close();
    super.dispose();
  }
}
