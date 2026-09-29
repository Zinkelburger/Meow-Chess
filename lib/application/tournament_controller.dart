import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
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
  void change(String action, Event next) {
    if (_closed) throw const TournamentException('This event has closed.');
    event = repository.commit(
      next,
      expectedRevision: event?.revision ?? 0,
      action: action,
    );
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

  void importPlayers(List<Player> players) {
    final e = event!;
    final ids = e.players
        .where((p) => p.memberId.isNotEmpty)
        .map((p) => p.memberId)
        .toSet();
    final names = e.players.map((p) => p.name.trim().toLowerCase()).toSet();
    final additions = <Player>[];
    for (final player in players) {
      if (player.memberId.isNotEmpty && !ids.add(player.memberId)) continue;
      if (!names.add(player.name.trim().toLowerCase())) continue;
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
  }

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
        .where((p) => e.sectionOf(p.id) == null)
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
    final game = e.games.where((g) => g.id == gameId).firstOrNull;
    if (game == null) {
      throw const TournamentException('The selected game no longer exists.');
    }
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
                                  ? g.copy(outcome: outcome, note: reason)
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
    final target = e.sections.firstWhere((s) => s.id == targetId);
    final sources = e.sections
        .where((s) => s.players.any(ids.contains))
        .toList();
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
    final sections = e.sections
        .map(
          (s) => s.id == targetId
              ? s.copy(players: members, format: Format.swiss)
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
    final s = e.sections.firstWhere((s) => s.id == sectionId);
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

  void undo() {
    final restored = repository.undo();
    if (restored != null) {
      event = restored;
      notifyListeners();
    }
  }

  String? get undoLabel => repository.undoLabel;
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
