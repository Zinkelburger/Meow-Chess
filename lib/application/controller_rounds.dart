part of 'tournament_controller_core.dart';

/// Pairing rounds: proposing, posting, starting and replacing them, and
/// TD-selected side games.
mixin _RoundCommands on _CommandContext {
  /// Proposes the next round of [sectionId], or of every section that can be
  /// paired, on a background isolate. With [onlyReady], sections waiting on
  /// results or following a fixed quad schedule are left out.
  Future<PairingBatch> propose({
    String? sectionId,
    bool onlyReady = false,
  }) async => _proposeInBackground(event!, sectionId, onlyReady);

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
          boardStart: nextBoard(e.sections),
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
      if (r == null) return s;
      final posted = s.copy(
        // Record the format actually paired, so an odd-sized quad stays
        // a Swiss once play begins.
        format: pairingFormat(s),
        rounds: [
          ...s.rounds,
          r.copy(postedAt: now),
        ],
      );
      // A knockout freezes its seeding at round 1 and records the bracket
      // round just posted.
      return posted.format == Format.knockout
          ? knockoutAfterPost(e, posted)
          : posted;
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

  /// Rule 29G3: re-pairs the boards of the latest round that have not
  /// started, keeping the games in [keep], for example after a player
  /// withdrew once pairings were posted. Withdraw the player first; the
  /// waiting players are re-paired as a separate group by the normal
  /// methods. Returns the new round's explanations.
  List<String> repairUnstarted(
    String sectionId,
    List<String> keep,
    String reason,
  ) {
    final e = event!;
    final s = _section(sectionId);
    if (reason.trim().isEmpty) {
      throw const TournamentException(
        'Record why the posted pairing is changing.',
      );
    }
    final r = repairUnstartedRound(e, s, keep.toSet(), newId);
    checkPairingRequests(e, r.games);
    final repaired = r.copy(note: reason.trim());
    change(
      'Re-pair round ${r.number} boards not started',
      e.copy(
        sections: [
          for (final x in e.sections)
            x.id != sectionId
                ? x
                : x.copy(
                    rounds: [...x.rounds.take(x.rounds.length - 1), repaired],
                  ),
        ],
      ),
    );
    return repaired.explanations;
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
}

/// Runs [_proposeRounds] on a background isolate. Top-level, so the isolate's
/// closure can only capture the plain data passed here, never the controller
/// and its open event file.
Future<PairingBatch> _proposeInBackground(
  Event snapshot,
  String? sectionId,
  bool onlyReady,
) => Isolate.run(() => _proposeRounds(snapshot, sectionId, onlyReady));

PairingBatch _proposeRounds(Event snapshot, String? sectionId, bool onlyReady) {
  final rounds = <String, Round>{}, issues = <String, String>{};
  // A knockout runs until its bracket is decided, not to a round count: a
  // drawn final still takes tie-break games after the planned rounds, and a
  // finished bracket is left for the proposal to explain.
  bool knockout(Section s) => s.format == Format.knockout;
  bool roundsLeft(Section s) => knockout(s)
      ? !knockoutBracket(snapshot, s).complete
      : s.rounds.length < s.plannedRounds;
  for (final s in snapshot.sections.where(
    (s) =>
        s.players.isNotEmpty &&
        !s.sideGames &&
        (!onlyReady || s.format != Format.ladder) &&
        (!onlyReady || !hasFixedQuadSchedule(s)) &&
        (sectionId == null || s.id == sectionId) &&
        (knockout(s) || !s.finished) &&
        (!onlyReady ||
            (roundsLeft(s) &&
                !s.rounds
                    .expand((r) => r.games)
                    .any(
                      (g) => !g.outcome.resolved && g.pairingAssumption == null,
                    ))),
  )) {
    try {
      rounds[s.id] = proposeRound(snapshot, s, () => const Uuid().v4());
    } on TournamentException catch (e) {
      issues[s.id] = e.message;
    }
  }
  return PairingBatch(snapshot.revision, rounds, issues);
}
