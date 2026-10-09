import 'dart:async';
import 'dart:isolate';
import 'dart:math' show Random;

import 'headless_foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/bye_policy.dart';
import '../domain/history.dart';
import '../domain/result_correction.dart';
import '../domain/rulings.dart';
import '../domain/model.dart';
import '../domain/member_observation.dart';
import '../domain/rating_update.dart';
import '../domain/pairing.dart';
import '../domain/us_chess.dart';
import 'event_repository.dart';
import 'diagnostics.dart';
import 'failures.dart';
import 'workspace_state_core.dart';

class PairingBatch {
  const PairingBatch(this.revision, this.rounds, this.issues);
  final int revision;
  final Map<String, Round> rounds;
  final Map<String, String> issues;
}

class TournamentControllerCore extends ChangeNotifier {
  TournamentControllerCore(this.repository) {
    try {
      event = repository.load();
    } catch (_) {
      // Construction did not return an owner who could release the connection.
      // A close failure must not hide the original invalid-event error.
      try {
        repository.close();
      } catch (_) {}
      rethrow;
    }
  }
  final EventRepository repository;
  late final _workspaceState = WorkspaceStateCore(repository);
  WorkspaceStateCore get workspaceState => _workspaceState;
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
    final context = <String, Object?>{
      'action': action,
      'eventId': next.id,
      'revision': event?.revision,
      'players': next.players.length,
    };
    Diagnostics.record('save event', 'started', context: context);
    try {
      if (_closed) throw const TournamentException('This event has closed.');
      if (event != null && next.encode() == event!.encode()) {
        Diagnostics.record('save event', 'unchanged', context: context);
        return;
      }
      _refuseNewDuplicateSectionName(event, next);
      event = repository.commit(
        next,
        expectedRevision: event?.revision ?? 0,
        action: action,
      );
      _graph = null;
      Diagnostics.record(
        'save event',
        'succeeded',
        context: {...context, 'revision': event!.revision},
      );
      notifyListeners();
    } catch (error, stack) {
      Diagnostics.record(
        'save event',
        'failed',
        context: context,
        error: error,
        stack: stack,
      );
      rethrow;
    }
  }

  /// Refuses a change that gives two sections the same name. Older files
  /// that already hold duplicates still open and save.
  static void _refuseNewDuplicateSectionName(Event? previous, Event next) {
    Map<String, int> count(Iterable<Section> sections) {
      final out = <String, int>{};
      for (final s in sections) {
        final key = s.name.trim().toLowerCase();
        out[key] = (out[key] ?? 0) + 1;
      }
      return out;
    }

    final before = count(previous?.sections ?? const []);
    for (final MapEntry(:key, :value) in count(next.sections).entries) {
      if (value > 1 && value > (before[key] ?? 0)) {
        // Name the section that already had it, as the TD knows it.
        final name = [
          ...?previous?.sections,
          ...next.sections,
        ].firstWhere((s) => s.name.trim().toLowerCase() == key).name.trim();
        throw TournamentException(
          'There is already a section called $name. Choose another name.',
        );
      }
    }
  }

  /// Rule 28H: after [savePlayer], advice the TD should see (the player now
  /// exceeds their section's rating ceiling). Cleared by the next save.
  String? playerNotice;

  void savePlayer(Player player) {
    final e = event!;
    playerNotice = null;
    final duplicate = e.players
        .where(
          (p) =>
              p.id != player.id &&
              (p.personId ?? p.id) != (player.personId ?? player.id) &&
              isMemberId(player.memberId) &&
              p.memberId == player.memberId,
        )
        .firstOrNull;
    if (duplicate != null) {
      throw TournamentException(
        'That US Chess ID belongs to ${duplicate.name}. Resolve the identity before adding another entry.',
      );
    }
    final previous = e.players.where((p) => p.id == player.id).firstOrNull;
    if (previous != null &&
        (previous.rating != player.rating ||
            previous.memberId != player.memberId) &&
        mapEquals(previous.ratingEvidence, player.ratingEvidence)) {
      player = player.copy(
        ratingEvidence: {
          'kind': 'TD-assigned',
          if (previous.memberId == player.memberId &&
              previous.ratingEvidence['registrationRating'] != null)
            'registrationRating': previous.ratingEvidence['registrationRating'],
        },
      );
    }
    if (previous == null ||
        previous.pairingRating != player.pairingRating ||
        previous.prizeRating != player.prizeRating ||
        previous.rating != player.rating) {
      _checkAssignedRatings(e, player);
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
    // Rule 28H: a revised rating can make the player ineligible for the
    // section. The save stands; the TD decides what to do.
    final section = e.sectionOf(player.id);
    if (previous != null &&
        section != null &&
        section.ratingCeiling > 0 &&
        player.effectivePairingRating >= section.ratingCeiling &&
        previous.effectivePairingRating != player.effectivePairingRating) {
      playerNotice =
          'Rating ${player.effectivePairingRating} is at or above the ${section.name} ceiling of ${section.ratingCeiling} (rule 28H). '
          'Move the player to an appropriate section, with half-point byes for rounds missed (28H2), or remove them (28H1).';
    }
  }

  /// Rules 28D2, 28D5, 28E1 and 28E2 for a TD-assigned pairing or prize
  /// rating. Throws when the assignment breaks the rule as written.
  void _checkAssignedRatings(Event e, Player player) {
    final assigned = [
      if (player.pairingRating > 0) ('pairing', player.pairingRating),
      if (player.prizeRating > 0) ('prize', player.prizeRating),
    ];
    if (assigned.isEmpty) return;
    final cause = player.ratingNote.trim();
    // Rule 28E1: never below the published rating, or the converted foreign
    // rating of a player without one.
    final foreign = player.rating == 0 && player.foreignRating > 0
        ? convertForeignRating(player.foreignFederation, player.foreignRating)
        : null;
    final floor = player.rating > 0 ? player.rating : foreign?.rating ?? 0;
    for (final (purpose, value) in assigned) {
      if (floor > 0 && value < floor) {
        throw TournamentException(
          'An assigned $purpose rating cannot be lower than '
          '${player.rating > 0 ? 'the published rating $floor' : 'the converted foreign rating $floor'} (rule 28E1).',
        );
      }
    }
    if (player.rating > 0 && cause.isEmpty) {
      throw const TournamentException(
        'State the cause for assigning a rating to a rated player (rule 28E2): superiority to the class, prize-driven results, an unlikely drop, or a previous lack of effort.',
      );
    }
    // Rules 28D2 / 28D5: an unverified or activity-based assignment to an
    // unrated player should not put them under 2200 where a class prize is
    // available. A stated cause records the verification (28D1).
    final prize = player.prizeRating > 0
        ? player.prizeRating
        : player.pairingRating;
    final section = e.sectionOf(player.id);
    if (player.rating == 0 &&
        prize < 2200 &&
        cause.isEmpty &&
        section != null &&
        _hasClassPrizeFor(section, prize)) {
      throw TournamentException(
        'An unrated player assigned $prize would be eligible for a class prize in ${section.name}. Rules 28D2 and 28D5 say an unverified assignment should not be under 2200; state the cause (for example the verified rating under 28D1) to proceed.',
      );
    }
  }

  static bool _hasClassPrizeFor(Section section, int rating) {
    final list = section.prizes['list'];
    if (list is! List) return false;
    for (final entry in list) {
      if (entry is! Map) continue;
      final kind = '${entry['kind'] ?? ''}'.toLowerCase();
      if (kind != 'class' && kind != 'under') continue;
      final min = (entry['min'] as num?)?.toInt() ?? 0;
      final max = (entry['max'] as num?)?.toInt() ?? 0;
      // Class ranges are inclusive; Under prizes exclude the ceiling.
      final below = kind == 'class' ? rating <= max : rating < max;
      if ((min == 0 || rating >= min) && (max == 0 || below)) return true;
    }
    return false;
  }

  /// Validates the entire approval against current state before a single commit.
  /// Both rating-review surfaces use this command, including undo/audit behavior.
  int applyReviewedRatings({
    required Event snapshot,
    required Map<String, MemberObservation> observations,
    required Set<String> playerIds,
    required String category,
  }) {
    final current = event!;
    if (current.id != snapshot.id) {
      throw const TournamentException('Event changed. Refresh again.');
    }
    final updates = <String, Player>{};
    for (final id in playerIds) {
      final player = current.players.where((p) => p.id == id).firstOrNull;
      final observation = observations[id];
      if (player == null || observation == null) {
        throw const TournamentException(
          'The reviewed player is no longer available. Refresh again.',
        );
      }
      final problem = ratingUpdateProblem(
        current: current,
        snapshot: snapshot,
        player: player,
        observation: observation,
        category: category,
      );
      if (problem != null) throw TournamentException(problem);
      updates[id] = applyRatingObservation(player, observation, category);
    }
    if (updates.isEmpty) return 0;
    change(
      'Apply ${updates.length} monthly supplement ratings',
      current.copy(
        players: [
          for (final player in current.players) updates[player.id] ?? player,
        ],
      ),
    );
    return updates.length;
  }

  /// Stores membership data and fills a missing state for the requested identity.
  /// A late response must never restore an edited ID or overwrite a newer check.
  bool recordMembership(String eventId, String playerId, Json observation) =>
      recordMemberships(eventId, {playerId: observation}).isNotEmpty;

  /// Records a batch of lookups as one revision and one undo step, keeping
  /// only observations that still match the player's ID and are not older
  /// than the stored check. Returns the players whose evidence was accepted.
  Set<String> recordMemberships(
    String eventId,
    Map<String, Json> observations,
  ) {
    final e = event;
    if (e == null || e.id != eventId) return const {};
    final updated = <String, Player>{};
    for (final MapEntry(key: playerId, value: observation)
        in observations.entries) {
      final player = e.players.where((p) => p.id == playerId).firstOrNull;
      if (player == null || player.memberId != observation['id']) continue;
      final checked = DateTime.tryParse('${observation['retrievedAt']}');
      final previous = DateTime.tryParse(
        '${player.membershipEvidence['retrievedAt']}',
      );
      if (checked == null || (previous != null && checked.isBefore(previous))) {
        continue;
      }
      final state = observation['state'] is String
          ? (observation['state'] as String).trim().toUpperCase()
          : '';
      updated[playerId] = player.copy(
        membershipEvidence: {
          for (final key in [
            'id',
            'name',
            'expiration',
            'status',
            'retrievedAt',
            'provider',
            'state',
          ])
            key: observation[key],
        },
        state: player.state.isEmpty && isStateCode(state) ? state : null,
      );
    }
    if (updated.isEmpty) return const {};
    change(
      updated.length == 1
          ? 'Check US Chess membership for ${updated.values.single.name}'
          : 'Check US Chess membership for ${updated.length} players',
      e.copy(players: [for (final p in e.players) updated[p.id] ?? p]),
    );
    return updated.keys.toSet();
  }

  /// Team membership is a roster label; it does not imply a pairing restriction.
  void assignTeam(Iterable<String> ids, String team) {
    final e = event!, selected = ids.toSet();
    for (final id in selected) {
      e.player(id);
    }
    change(
      'Assign team to ${selected.length} players',
      e.copy(
        players: [
          for (final p in e.players)
            selected.contains(p.id) ? p.copy(team: team.trim()) : p,
        ],
      ),
    );
  }

  /// A side game or ladder entry keeps this person's identity but starts a
  /// separate score and history. Ordinary registration still rejects duplicates.
  Player addSectionEntry(String playerId, String sectionId) {
    final e = event!,
        original = e.player(playerId),
        target = _section(sectionId);
    final person = original.personId ?? original.id;
    if (target.players.any((id) => (e.player(id).personId ?? id) == person)) {
      throw const TournamentException(
        'This person already has an entry in that section.',
      );
    }
    if (target.rounds.isNotEmpty) {
      throw const TournamentException(
        'Add separate entries before the target section starts.',
      );
    }
    final entry = Player.fromJson({
      ...original.toJson(),
      'id': newId(),
      'personId': person,
      'byes': <String, int>{},
      'withdrawn': false,
    });
    change(
      'Enter ${original.name} separately in ${target.name}',
      e.copy(
        players: [...e.players, entry],
        sections: [
          for (final s in e.sections)
            s.id == target.id ? s.copy(players: [...s.players, entry.id]) : s,
        ],
      ),
    );
    return entry;
  }

  /// A TD-selected game with independent entries and score, committed atomically.
  /// Finishing/forfeiting the main game frees that person for a side game.
  String addSideGame(String whiteId, String blackId, {String? sectionId}) {
    final e = event!;
    final white = e.player(whiteId), black = e.player(blackId);
    if ((white.personId ?? white.id) == (black.personId ?? black.id)) {
      throw const TournamentException('Choose two different people.');
    }
    final people = {white.personId ?? white.id, black.personId ?? black.id};
    if (e.games
        .where((game) => !game.outcome.resolved)
        .any(
          (game) => [game.white, game.black].any((id) {
            final player = e.player(id);
            return people.contains(player.personId ?? player.id);
          }),
        )) {
      throw const TournamentException(
        'Finish the players’ current games before pairing a side game.',
      );
    }
    final existing = sectionId == null
        ? e.sections.where((s) => s.sideGames).firstOrNull
        : _section(sectionId);
    if (existing != null && !existing.sideGames) {
      throw const TournamentException('Choose a side-games section.');
    }
    final nextBoard = e.sections.fold(1, (int next, Section s) {
      final end = s.boardStart + (s.players.length + 1) ~/ 2;
      return end > next ? end : next;
    });
    final taken = {for (final s in e.sections) s.name.trim().toLowerCase()};
    var name = 'Side Games';
    for (var n = 2; taken.contains(name.toLowerCase()); n++) {
      name = 'Side Games $n';
    }
    final section =
        existing ??
        Section(
          id: newId(),
          name: name,
          players: [],
          sideGames: true,
          plannedRounds: 1,
          boardStart: nextBoard,
        );
    final additions = <Player>[];
    Player entry(Player source) {
      final person = source.personId ?? source.id;
      final old = section.players
          .map(e.player)
          .where((p) => (p.personId ?? p.id) == person)
          .firstOrNull;
      if (old != null) return old;
      final added = Player.fromJson({
        ...source.toJson(),
        'id': newId(),
        'personId': person,
        'byes': <String, int>{},
        'withdrawn': false,
      });
      additions.add(added);
      return added;
    }

    final a = entry(white), b = entry(black);
    final last = section.rounds.lastOrNull;
    final append =
        last != null &&
        !last.complete &&
        !last.games.any(
          (g) =>
              g.white == a.id ||
              g.black == a.id ||
              g.white == b.id ||
              g.black == b.id,
        ) &&
        !last.byes.any((bye) => bye.player == a.id || bye.player == b.id);
    final occupiedBoards = e.sections
        .expand((s) => s.unresolvedRounds)
        .expand((r) => r.games)
        .map((g) => g.board)
        .toSet();
    var board = section.boardStart;
    while (occupiedBoards.contains(board)) {
      board++;
    }
    final game = Game(id: newId(), white: a.id, black: b.id, board: board);
    final round = append
        ? last.copy(games: [...last.games, game])
        : Round(
            number: section.rounds.length + 1,
            games: [game],
            policy: 'td-side-games',
            note: 'TD-selected side game',
            postedAt: DateTime.now().toUtc().toIso8601String(),
          );
    final updated = section.copy(
      players: [...section.players, ...additions.map((p) => p.id)],
      plannedRounds: round.number,
      rounds: append
          ? [...section.rounds.take(section.rounds.length - 1), round]
          : [...section.rounds, round],
    );
    change(
      'Pair side game: ${white.name} – ${black.name}',
      e.copy(
        players: [...e.players, ...additions],
        sections: existing == null
            ? [...e.sections, updated]
            : [for (final s in e.sections) s.id == section.id ? updated : s],
      ),
    );
    secondaryBackup();
    return section.id;
  }

  void avoidPair(String a, String b, bool avoid) {
    final e = event!;
    if (a == b) {
      throw const TournamentException('Choose two different players.');
    }
    e.player(a);
    e.player(b);
    change(
      '${avoid ? 'Add' : 'Remove'} do-not-pair request',
      e.copy(
        players: [
          for (final p in e.players)
            if (p.id == a || p.id == b)
              p.copy(
                avoid: avoid
                    ? {...p.avoid, p.id == a ? b : a}
                    : p.avoid.difference({p.id == a ? b : a}),
              )
            else
              p,
        ],
      ),
    );
  }

  /// Adds new entries and returns how many rows were skipped as existing.
  /// A member ID is identity; a name only identifies someone when either side
  /// lacks an ID, so two members who share a name are both admitted.
  int importPlayers(List<Player> players) {
    final e = event!;
    final additions = newEntries(e.players, players);
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
    bool assignUnassigned = true,
  }) {
    final e = event!;
    final free = e.players
        .where((p) => !p.withdrawn && e.sectionOf(p.id) == null)
        .map((p) => p.id)
        .toList();
    change(
      'Create $name',
      e.copy(
        sections: [
          ...e.sections,
          Section(
            id: newId(),
            name: name,
            players: assignUnassigned ? free : [],
            format: format,
            plannedRounds: rounds,
            boardStart: nextBoard(e.sections),
            doubleGames: doubleGames,
          ),
        ],
      ),
    );
  }

  /// Rule 30A: assigns a round-robin or quad section's pairing numbers by
  /// lot. The shuffle is seeded and the seed is in the audited action, so the
  /// draw can be reproduced; posted rounds fix the numbers.
  void drawLots(String sectionId, {int? seed}) {
    final e = event!;
    final section = e.sections.where((s) => s.id == sectionId).firstOrNull;
    if (section == null) {
      throw const TournamentException('This section no longer exists.');
    }
    if (section.format == Format.swiss || section.sideGames) {
      throw const TournamentException(
        'Numbers by lot apply to round robins and quads.',
      );
    }
    if (section.rounds.isNotEmpty) {
      throw const TournamentException(
        'Pairing numbers are fixed once a round is posted.',
      );
    }
    if (section.players.length < 2) {
      throw const TournamentException('Add players before drawing lots.');
    }
    final drawn = seed ?? Random().nextInt(1 << 31);
    final players = [...section.players]..shuffle(Random(drawn));
    change(
      'Draw lots for ${section.name} (seed $drawn)',
      e.copy(
        sections: [
          for (final x in e.sections)
            x.id == section.id ? x.copy(players: players, quadPairings: []) : x,
        ],
      ),
    );
  }

  /// Puts exactly [players] into new sections before they play: one
  /// [format] section called [name], or for [Format.quad] groups of four by
  /// rating with any leftovers in a small Swiss. Players leave the unpaired
  /// sections they were in, and a section left empty by this is removed.
  /// An empty [players] makes an empty section. Returns the new ids.
  List<String> createSections(
    List<String> players, {
    required Format format,
    String name = '',
    int rounds = 3,
    bool doubleGames = false,
    bool sideGames = false,
    int? boardStart,
    String timeControl = '',
  }) {
    final e = event!, pool = players.toSet();
    for (final id in pool) {
      final p = e.player(id), from = e.sectionOf(id);
      if (p.withdrawn) {
        throw TournamentException(
          '${p.name} has withdrawn. Reinstate them first.',
        );
      }
      if (from != null && from.rounds.isNotEmpty) {
        throw TournamentException(
          '${from.name} has been paired. Move ${p.name} from there instead.',
        );
      }
    }
    final emptied = sectionsEmptiedBy(e, pool);
    final kept = [
      for (final s in e.sections)
        if (!emptied.contains(s.id))
          s.players.any(pool.contains)
              // A manual quad schedule names roster slots, which shift.
              ? s.copy(
                  players: s.players.where((id) => !pool.contains(id)).toList(),
                  quadPairings: const [],
                )
              : s,
    ];
    var board = boardStart ?? nextBoard(kept);
    final entrants = [
      for (final p in e.players)
        if (pool.contains(p.id)) p,
    ];
    final created = <Section>[];
    String label;
    if (format == Format.quad) {
      final groups = planQuads(entrants, taken: kept.map((s) => s.name));
      for (final group in groups) {
        created.add(
          Section(
            id: newId(),
            name: group.name,
            players: [for (final p in group.players) p.id],
            format: group.format,
            boardStart: board,
            timeControl: timeControl,
          ),
        );
        board += (group.players.length + 1) ~/ 2;
      }
      label = 'Make ${created.length} sections';
    } else {
      final title = name.trim();
      if (title.isEmpty) {
        throw const TournamentException('Enter the section name.');
      }
      if (kept.any((s) => s.name.toLowerCase() == title.toLowerCase())) {
        throw TournamentException('There is already a section called $title.');
      }
      if (rounds < 1 || rounds > 32) {
        throw const TournamentException(
          'Number of rounds must be between 1 and 32.',
        );
      }
      created.add(
        Section(
          id: newId(),
          name: title,
          players: [for (final p in entrants) p.id],
          format: format,
          plannedRounds: rounds,
          boardStart: board,
          doubleGames: doubleGames,
          sideGames: sideGames,
          timeControl: timeControl,
        ),
      );
      label = 'Create $title';
    }
    change(label, e.copy(sections: [...kept, ...created]));
    return [for (final s in created) s.id];
  }

  /// Removing an unplayed section keeps its entrants in the event roster.
  void removeSection(String id) {
    final section = _section(id);
    if (section.rounds.isNotEmpty) {
      throw const TournamentException(
        'Sections with posted rounds cannot be deleted.',
      );
    }
    change(
      'Delete ${section.name}',
      event!.copy(sections: event!.sections.where((s) => s.id != id).toList()),
    );
  }

  Future<PairingBatch> propose({
    String? sectionId,
    bool onlyReady = false,
  }) async {
    final snapshot = event!;
    return Isolate.run(() {
      final rounds = <String, Round>{}, issues = <String, String>{};
      for (final s in snapshot.sections.where(
        (s) =>
            s.players.isNotEmpty &&
            !s.sideGames &&
            (!onlyReady || !hasFixedQuadSchedule(s)) &&
            (sectionId == null || s.id == sectionId) &&
            !s.finished &&
            (!onlyReady ||
                (s.rounds.length < s.plannedRounds &&
                    !s.rounds
                        .expand((r) => r.games)
                        .any(
                          (g) =>
                              !g.outcome.resolved &&
                              g.pairingAssumption == null,
                        ))),
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
    // Rule 29E2 TIP: one coin toss decides board one of every section, so
    // the toss the first Swiss round used is recorded on the event.
    final tossed =
        e.colorToss.isEmpty &&
        batch.rounds.values.any(
          (r) => r.policy == swissPolicy && r.number == 1,
        );
    final colorToss = tossed ? effectiveColorToss(e) : e.colorToss;
    // Board numbers reserve physical space across independently progressing sections.
    final busy = <int, String>{};
    for (final s in updated) {
      final boards = s.unresolvedRounds
          .expand((r) => r.games)
          .map((g) => g.board)
          .toSet();
      for (final board in boards) {
        final prior = busy[board];
        if (prior != null) {
          throw TournamentException(
            'Board $board is already reserved by $prior. Adjust board ranges.',
          );
        }
        busy[board] = s.name;
      }
    }
    for (final r in batch.rounds.values) {
      checkPairingRequests(e, r.games);
    }
    change(
      'Create pairings for ${batch.rounds.length} section${batch.rounds.length == 1 ? '' : 's'}',
      e.copy(sections: updated, colorToss: colorToss),
    );
    secondaryBackup();
  }

  void startRound(String sectionId) => startRounds([sectionId]);

  /// Starts the current round of each section as one revision: the first
  /// unfinished one. Entering a quad result saves the schedule through that
  /// round, so the current round can come before the last saved one.
  void startRounds(Iterable<String> sectionIds) {
    final e = event!, ids = sectionIds.toSet();
    if (ids.isEmpty) {
      throw const TournamentException('No round is waiting to start.');
    }
    final current = <String, int>{};
    for (final id in ids) {
      final section = _section(id);
      if (section.rounds.isEmpty) {
        throw const TournamentException('Post a round before starting it.');
      }
      final open = section.rounds.indexWhere((r) => !r.complete);
      if (open < 0) {
        throw const TournamentException('This round is already complete.');
      }
      final round = section.rounds[open];
      final last = open == section.rounds.length - 1;
      // The last round may have results entered before its start; an earlier
      // one with play is still being played under a later posted round.
      if (last ? round.startedAt != null : round.hasPlay) {
        throw last
            ? const TournamentException('This round has already started.')
            : TournamentException(
                '${section.name}: earlier games are still unresolved. A pairing assumption permits posting, not simultaneous play.',
              );
      }
      current[id] = open;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    change(
      ids.length == 1 ? 'Start round' : 'Start round in ${ids.length} sections',
      e.copy(
        sections: e.sections
            .map(
              (s) => !ids.contains(s.id)
                  ? s
                  : s.copy(
                      rounds: [
                        for (final (i, r) in s.rounds.indexed)
                          i == current[s.id] ? r.copy(startedAt: now) : r,
                      ],
                    ),
            )
            .toList(),
      ),
    );
  }

  _Projection? _projection;
  _Projection get _projected {
    final e = event!, cached = _projection;
    if (cached != null && identical(cached.source, e)) return cached;
    final sections = <Section>[], issues = <String, String>{};
    for (final s in e.sections) {
      final (:rounds, :issue) = projectQuad(e, s);
      sections.add(s.copy(rounds: rounds));
      if (issue != null) issues[s.id] = issue;
    }
    return _projection = (
      source: e,
      projected: e.copy(sections: sections),
      issues: issues,
    );
  }

  /// Read-only schedule projection, computed once per revision. Browsing
  /// pairings does not post rounds.
  Event get pairingEvent => _projected.projected;

  /// Why a quad's remaining rounds cannot be shown, by section ID.
  Map<String, String> get quadScheduleIssues => _projected.issues;

  ResultCorrection reviewResult(String gameId) =>
      ResultCorrection(_materialize(gameId).$1, gameId);

  bool correctionHasDependencies(String gameId) =>
      reviewResult(gameId).hasDependencies;

  /// Result and reopening are one durable command. Never apply a stale review.
  void correctResult(
    ResultCorrection review,
    Outcome outcome, {
    String reason = '',
    int? reopenFrom,
    bool confirmedUnstarted = false,
    bool? adjudicated,
  }) {
    if (event!.id != review.event.id ||
        event!.revision != review.event.revision) {
      throw const TournamentException(
        'The event changed while this review was open. Close it and review the correction again.',
      );
    }
    final next = _withIrrevocableByeRule(
      review.apply(
        outcome,
        reason: reason,
        reopenFrom: reopenFrom,
        confirmedUnstarted: confirmedUnstarted,
        adjudicated: adjudicated,
      ),
      review.gameId,
    );
    change(
      'Correct ${review.section.name} round ${review.round.number}, board ${review.game.board}: '
      '${review.game.outcome.label} → ${outcome.label}'
      '${reopenFrom == null ? '' : ', unpair from round $reopenFrom'}'
      '${reason.trim().isEmpty ? '' : ' · ${reason.trim()}'}',
      next,
    );
  }

  /// Saves the projected quad rounds through the one holding [gameId], so its
  /// result has a posted round to live in. Later rounds stay projected and can
  /// still take requested byes and withdrawals.
  (Event, Game) _materialize(String gameId) {
    final e = event!;
    if (e.games.where((g) => g.id == gameId).firstOrNull case final game?) {
      return (e, game);
    }
    for (final projected in pairingEvent.sections) {
      final round = projected.rounds
          .where((r) => r.games.any((g) => g.id == gameId))
          .firstOrNull;
      if (round == null) continue;
      final now = DateTime.now().toUtc().toIso8601String();
      final next = e.copy(
        sections: [
          for (final s in e.sections)
            s.id != projected.id
                ? s
                : s.copy(
                    rounds: [
                      ...s.rounds,
                      for (final r in projected.rounds.sublist(
                        s.rounds.length,
                        round.number,
                      ))
                        r.copy(postedAt: now),
                    ],
                  ),
        ],
      );
      return (next, round.games.firstWhere((g) => g.id == gameId));
    }
    throw const TournamentException('The selected game no longer exists.');
  }

  /// Rule 22C5: once a result is in, a win by a player who cancelled an
  /// irrevocable bye for that round counts as a draw for prizes.
  static Event _withIrrevocableByeRule(Event e, String gameId) => e.copy(
    sections: [
      for (final s in e.sections)
        s.copy(
          rounds: [
            for (final r in s.rounds)
              r.games.any((g) => g.id == gameId)
                  ? r.copy(
                      games: [
                        for (final g in r.games)
                          g.id == gameId
                              ? applyIrrevocableByeRule(e, g, r.number)
                              : g,
                      ],
                    )
                  : r,
          ],
        ),
    ],
  );

  void recordResult(String gameId, Outcome outcome, {String reason = ''}) {
    final (e, game) = _materialize(gameId);
    if (game.outcome == outcome && game.note == reason) return;
    if (correctionHasDependencies(gameId) && reason.trim().isEmpty) {
      throw const TournamentException(
        'Explain the correction: later posted rounds will be retained and need review.',
      );
    }
    change(
      'Result, board ${game.board}',
      _withIrrevocableByeRule(
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
        gameId,
      ),
    );
  }

  void setPairingAssumption(String gameId, Outcome assumption, String reason) {
    final (e, game) = _materialize(gameId);
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

  /// Reserves, changes or cancels (negative [points]) a future bye. Rules
  /// 22C1–22C4 limit half-point byes by the section's [ByePolicy];
  /// zero-point byes are always allowed. [irrevocable] true declares the
  /// bye irrevocable (22C4), false withdraws the declaration, null keeps
  /// it, so a cancelled irrevocable bye still counts under 22C5.
  void reserveBye(String playerId, int round, int points, {bool? irrevocable}) {
    final e = event!;
    final s = e.sectionOf(playerId);
    if (s != null && round <= s.rounds.length) {
      throw const TournamentException(
        'That round is posted. Correct the existing game or replace the unstarted pairing.',
      );
    }
    final player = e.player(playerId);
    final byes = {...player.byes};
    final declared = {...player.irrevocableByes};
    if (irrevocable == true) declared.add(round);
    if (irrevocable == false) declared.remove(round);
    if (points < 0) {
      byes.remove(round);
    } else {
      if (points == 1 && s != null) {
        final problem = ByePolicy.fromJson(
          s.byeRules,
        ).halfByeProblem(player, round, declared: declared.contains(round));
        if (problem != null) throw TournamentException(problem);
      }
      byes[round] = points;
    }
    savePlayer(player.copy(byes: byes, irrevocableByes: declared));
  }

  /// Rules 29H3 and 29H4: when the last posted round of [sectionId] still has
  /// unreported games at pairing time, score each as a double forfeit
  /// (`doubleForfeit`, 29H3) or hold both players out of the next round with
  /// half-point byes (`halfPointByes`, 29H4), in one revision. Returns the
  /// boards treated.
  List<int> holdOutNonReporters(String sectionId, {required String treatment}) {
    final e = event!, s = _section(sectionId);
    if (!const {'doubleForfeit', 'halfPointByes'}.contains(treatment)) {
      throw const TournamentException(
        'Choose doubleForfeit (rule 29H3) or halfPointByes (rule 29H4).',
      );
    }
    final round = s.rounds.lastOrNull;
    if (round == null) {
      throw const TournamentException('No round is posted in this section.');
    }
    final unreported = round.games
        .where((g) => g.outcome == Outcome.unreported)
        .toList();
    if (unreported.isEmpty) {
      throw TournamentException(
        'Every game in round ${round.number} has a result.',
      );
    }
    final next = round.number + 1;
    var players = e.players;
    var games = round.games;
    if (treatment == 'doubleForfeit') {
      games = [
        for (final g in games)
          unreported.contains(g)
              ? g.copy(
                  outcome: Outcome.doubleForfeit,
                  note:
                      'Rule 29H3: result not reported by pairing time; both players scored as losses. The real result, when learned, may be recorded as an extra rated game (28M4).',
                  pairingAssumption: null,
                  pairingReason: '',
                )
              : g,
      ];
    } else {
      if (next > s.plannedRounds) {
        throw TournamentException(
          'Round ${round.number} is the last round, so there is no next round to hold them out of. Use the double forfeit (rule 29H3).',
        );
      }
      final policy = ByePolicy.fromJson(s.byeRules);
      final held = <String, Player>{};
      for (final g in unreported) {
        for (final id in [g.white, g.black]) {
          final p = held[id] ?? e.player(id);
          final problem = policy.halfByeProblem(p, next, declared: true);
          if (problem != null) {
            throw TournamentException(
              'Half-point byes are not available for round $next (rule 29H4): $problem',
            );
          }
          held[id] = p.copy(byes: {...p.byes, next: 1});
        }
      }
      players = [for (final p in players) held[p.id] ?? p];
      games = [
        for (final g in games)
          unreported.contains(g)
              ? g.copy(
                  note:
                      'Rule 29H4: result not reported by pairing time; both players hold half-point byes for round $next.',
                )
              : g,
      ];
    }
    change(
      treatment == 'doubleForfeit'
          ? 'Double forfeit ${unreported.length == 1 ? 'board ${unreported.single.board}' : '${unreported.length} unreported boards'} in ${s.name} round ${round.number} (29H3)'
          : 'Hold ${unreported.length * 2} non-reporters out of ${s.name} round $next with half-point byes (29H4)',
      e.copy(
        players: players,
        sections: [
          for (final x in e.sections)
            x.id == s.id
                ? x.copy(
                    rounds: [
                      for (final r in x.rounds)
                        r.number == round.number ? r.copy(games: games) : r,
                    ],
                  )
                : x,
        ],
      ),
    );
    return [for (final g in unreported) g.board];
  }

  /// Rules 13I, 20K, 18G, 21H–21L: records a ruling, penalty, appeal or
  /// adjudication in the event's log. Returns the entry's ID.
  String logRuling({
    required String kind,
    required String text,
    int round = 0,
    String section = '',
    List<String> players = const [],
    String decidedBy = '',
    String outcome = '',
  }) {
    final e = event!;
    if (!rulingKinds.containsKey(kind)) {
      throw TournamentException(
        'The kind must be one of ${rulingKinds.keys.join(', ')}.',
      );
    }
    if (text.trim().isEmpty) {
      throw const TournamentException('Describe the ruling.');
    }
    if (section.isNotEmpty) _section(section);
    for (final id in players) {
      e.player(id);
    }
    final entry = <String, dynamic>{
      'id': newId(),
      'at': DateTime.now().toUtc().toIso8601String(),
      'kind': kind,
      'round': round,
      'section': section,
      'players': players,
      'text': text.trim(),
      'decidedBy': decidedBy.trim(),
      'outcome': outcome.trim(),
    };
    change(
      'Log ${rulingKinds[kind]!.toLowerCase()}',
      e.copy(rulings: [...e.rulings, entry]),
    );
    return entry['id'] as String;
  }

  void removeRuling(String id) {
    final e = event!;
    if (!e.rulings.any((r) => r['id'] == id)) {
      throw const TournamentException('That log entry no longer exists.');
    }
    change(
      'Remove log entry',
      e.copy(rulings: [...e.rulings.where((r) => r['id'] != id)]),
    );
  }

  /// Saves a complete quad schedule, including unplayed posted rounds, in one
  /// revision. Played rounds and pairing assumptions retain their participants.
  void editQuadPairings(
    String sectionId,
    List<List<String>> pairings,
    int expectedRevision,
  ) {
    final e = event!, s = _section(sectionId);
    if (e.revision != expectedRevision) {
      throw const TournamentException(
        'The event changed. Reopen the quad editor and review again.',
      );
    }
    if (s.format != Format.quad || s.players.length != 4 || s.sideGames) {
      throw const TournamentException(
        'Choose a quad with exactly four players.',
      );
    }
    if (pairings.length != 3 ||
        pairings.any(
          (r) =>
              r.length != 4 ||
              r.toSet().length != 4 ||
              !r.toSet().containsAll(s.players),
        )) {
      throw const TournamentException(
        'Each round must include all four quad players exactly once.',
      );
    }
    final opponents = <String>{};
    for (final (index, row) in pairings.indexed) {
      for (var board = 0; board < 2; board++) {
        final a = row[board * 2], b = row[board * 2 + 1];
        final slots = [s.players.indexOf(a), s.players.indexOf(b)]..sort();
        if (!opponents.add(slots.join('-'))) {
          throw TournamentException(
            'Round ${index + 1} repeats ${e.player(a).name} vs ${e.player(b).name}. Adjust the other unplayed round so everyone meets once.',
          );
        }
        if (pairingRestricted(e, a, b)) {
          throw TournamentException(
            '${e.player(a).name} and ${e.player(b).name} have a do-not-pair request.',
          );
        }
      }
    }
    final rounds = <Round>[];
    for (final r in s.rounds) {
      final row = pairings[r.number - 1];
      final boards = r.games
          .where((g) => g.leg == 1)
          .map((g) => g.board)
          .toList();
      if (r.byes.isNotEmpty ||
          boards.length != 2 ||
          r.games.length != (s.doubleGames ? 4 : 2)) {
        throw const TournamentException(
          'This quad has a custom round. Review its pairings separately.',
        );
      }
      // A game whose players change gets a new ID, so a stale reference to
      // the old pairing is refused instead of scoring different players.
      Game reseat(Game g) {
        final slot = boards.indexOf(g.board) * 2, second = g.leg == 2 ? 1 : 0;
        final white = row[slot + second], black = row[slot + 1 - second];
        return white == g.white && black == g.black
            ? g
            : g.copy(id: newId(), white: white, black: black);
      }

      final games = r.games.map(reseat).toList();
      final changed = games.indexed.any(
        (entry) => !identical(entry.$2, r.games[entry.$1]),
      );
      if (changed &&
          (r.hasPlay || r.games.any((g) => g.pairingAssumption != null))) {
        throw TournamentException(
          'Round ${r.number} has started or has a result or pairing assumption. Keep its pairings unchanged.',
        );
      }
      rounds.add(
        changed
            ? r.copy(
                games: games,
                revision: r.revision + 1,
                note: 'Manual quad pairings',
              )
            : r,
      );
    }
    final slots = [
      for (final row in pairings) [for (final id in row) s.players.indexOf(id)],
    ];
    change(
      'Edit ${s.name} pairings',
      e.copy(
        sections: [
          for (final section in e.sections)
            section.id == s.id
                ? section.copy(quadPairings: slots, rounds: rounds)
                : section,
        ],
      ),
    );
  }

  /// Exchanges roster slots atomically; posted schedules cannot be rewritten.
  void swapPlayers(String first, String second, int expectedRevision) {
    final e = event!;
    if (e.revision != expectedRevision) {
      throw const TournamentException(
        'The event changed. Review the swap again.',
      );
    }
    e.player(first);
    e.player(second);
    final a = e.sectionOf(first), b = e.sectionOf(second);
    if (first == second || a == null || b == null || a.id == b.id) {
      throw const TournamentException(
        'Choose players in two different sections.',
      );
    }
    if (a.rounds.isNotEmpty || b.rounds.isNotEmpty) {
      throw const TournamentException(
        'Swap players before posting rounds. Existing pairings cannot be changed by a roster swap.',
      );
    }
    change(
      'Swap ${e.player(first).name} and ${e.player(second).name}',
      e.copy(
        sections: [
          for (final s in e.sections)
            s.copy(
              players: [
                for (final id in s.players)
                  id == first
                      ? second
                      : id == second
                      ? first
                      : id,
              ],
            ),
        ],
      ),
    );
  }

  /// Withdraws or reinstates several players as one undoable change.
  void setWithdrawn(Iterable<String> ids, bool withdrawn) {
    final e = event!, chosen = ids.toSet();
    for (final id in chosen) {
      e.player(id);
    }
    final verb = withdrawn ? 'Withdraw' : 'Reinstate';
    change(
      chosen.length == 1
          ? '$verb ${e.player(chosen.single).name}'
          : '$verb ${chosen.length} players',
      e.copy(
        players: [
          for (final p in e.players)
            chosen.contains(p.id) ? p.copy(withdrawn: withdrawn) : p,
        ],
      ),
    );
  }

  /// Takes entries that never played out of the event entirely, along with
  /// every reference to them. Played entries are withdrawn instead.
  void removePlayers(Iterable<String> ids) {
    final e = event!, gone = ids.toSet();
    if (gone.isEmpty) return;
    for (final id in gone) {
      if (removeBlocker(e, id) case final problem?) {
        throw TournamentException(problem);
      }
    }
    final touched = {
      for (final s in e.sections)
        if (s.players.any(gone.contains)) s.id,
    };
    change(
      gone.length == 1
          ? 'Remove ${e.player(gone.single).name}'
          : 'Remove ${gone.length} players',
      e.copy(
        players: [
          for (final p in e.players)
            if (!gone.contains(p.id))
              p.avoid.any(gone.contains)
                  ? p.copy(avoid: p.avoid.difference(gone))
                  : p,
        ],
        sections: [
          for (final s in e.sections)
            touched.contains(s.id)
                // A manual quad schedule names roster slots, which shift.
                ? s.copy(
                    players: s.players
                        .where((id) => !gone.contains(id))
                        .toList(),
                    quadPairings: const [],
                  )
                : s,
        ],
        // Only pre-play moves can name them; drop them from those records.
        transitions: [
          for (final t in e.transitions)
            if (!(t['players'] as List).any(gone.contains))
              t
            else if ((t['players'] as List).any((id) => !gone.contains(id)))
              {
                ...t,
                'players': [
                  for (final id in t['players'] as List)
                    if (!gone.contains(id)) id,
                ],
              },
        ],
      ),
    );
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
    final changed = <String>{};
    final sections = e.sections.map((s) {
      final players = s.id == targetId
          ? members
          : s.players.where((id) => !ids.contains(id)).toList();
      if (listEquals(players, s.players)) {
        return s.id == targetId && played ? s.copy(format: Format.swiss) : s;
      }
      changed.add(s.id);
      return s.copy(
        players: players,
        format: s.id == targetId && played ? Format.swiss : null,
        // A manual quad schedule names roster slots, which shift.
        quadPairings: const [],
      );
    }).toList();
    // Board ranges stay where the TD put them. A section whose roster grew
    // into another's range moves after every range and every live board.
    (int, int) range(Section s) =>
        (s.boardStart, s.boardStart + (s.players.length + 1) ~/ 2);
    bool overlaps((int, int) a, (int, int) b) =>
        a.$1 < a.$2 && b.$1 < b.$2 && a.$1 < b.$2 && b.$1 < a.$2;
    final before = {for (final s in e.sections) s.id: range(s)};
    final allocated = [...sections];
    for (final (i, s) in allocated.indexed) {
      if (!changed.contains(s.id)) continue;
      final others = [
        for (final o in allocated)
          if (o.id != s.id) o,
      ];
      final collides = others.any(
        (o) =>
            overlaps(range(s), range(o)) &&
            !overlaps(before[s.id]!, before[o.id]!),
      );
      if (!collides) continue;
      final live = others
          .expand((o) => o.unresolvedRounds)
          .expand((r) => r.games)
          .fold(0, (int max, g) => g.board > max ? g.board : max);
      final free = nextBoard(others);
      allocated[i] = s.copy(boardStart: free > live ? free : live + 1);
    }
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
    if (r.games.any((g) => g.pairingAssumption != null)) {
      throw const TournamentException(
        'This round has a pairing assumption. Preserve its participants and review the result separately.',
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
    checkPairingRequests(e, games);
    final previous = {for (final game in r.games) game.id: game};
    final replacements = [
      for (final game in games)
        // A saved editor identifies a game, not a physical board. Reusing its
        // ID for different participants or colors would let a stale editor
        // record a result against the replacement matchup.
        if (previous[game.id] case final old?
            when old.white != game.white ||
                old.black != game.black ||
                old.leg != game.leg)
          game.copy(id: newId())
        else
          game,
    ];
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
                                    games: replacements,
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

  /// History lives in the event file, so a closed event cannot read it.
  void _refuseClosed(String action) {
    if (!_closed) return;
    const error = TournamentException('This event has closed.');
    Diagnostics.record(
      'save event',
      'failed',
      context: {'action': action},
      error: error,
    );
    throw error;
  }

  void undo({bool acceptLosses = false}) {
    _refuseClosed('Undo');
    if (!canUndo) return;
    _move(graph.back!, 'Undo $undoLabel', acceptLosses);
  }

  void redo({bool acceptLosses = false}) {
    _refuseClosed('Redo');
    if (!canRedo) return;
    _move(graph.forward!, 'Redo $redoLabel', acceptLosses);
  }

  void restore(int node, {bool acceptLosses = false}) {
    _refuseClosed('Restore #$node');
    if (node == graph.head) return;
    _move(
      node,
      'Restore #$node · ${graph.nodes[node]?.action ?? ''}',
      acceptLosses,
    );
  }

  void _move(int node, String action, bool acceptLosses) {
    final context = <String, Object?>{
      'action': action,
      'eventId': event?.id,
      'revision': event?.revision,
      'node': node,
    };
    Diagnostics.record('save event', 'started', context: context);
    try {
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
      Diagnostics.record(
        'save event',
        'succeeded',
        context: {...context, 'revision': event!.revision},
      );
      notifyListeners();
    } catch (error, stack) {
      Diagnostics.record(
        'save event',
        'failed',
        context: context,
        error: error,
        stack: stack,
      );
      rethrow;
    }
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
      repository.writePreference(
        'lastBackup',
        '${e.revision}|$destination|${DateTime.now().toUtc().toIso8601String()}',
      );
      backupWarning = null;
    } catch (error) {
      backupWarning =
          'Saved to the event file, but the backup copy failed. ${plainMessage(error)}';
    }
    notifyListeners();
  }

  void releaseResources() {
    _closed = true;
    workspaceState.dispose();
    repository.close();
  }

  @override
  void dispose() {
    releaseResources();
    super.dispose();
  }
}

/// The quad projection of one event revision, keyed by that revision's object.
typedef _Projection = ({
  Event source,
  Event projected,
  Map<String, String> issues,
});
