part of 'tournament_controller_core.dart';

/// Results and rulings: recording and correcting results, pairing
/// assumptions, non-reporters at pairing time, and the rulings log.
mixin _ResultCommands on _CommandContext, _QuadCommands {
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
    bool? shortGame,
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
        shortGame: shortGame,
      ),
      review.gameId,
    );
    final shortChanged =
        outcome == review.game.outcome &&
        shortGame != null &&
        shortGame != review.game.shortGame;
    change(
      'Correct ${review.section.name} round ${review.round.number}, board ${review.game.board}: '
      '${shortChanged ? (shortGame ? 'lasted less than one move' : 'a full game') : '${review.game.outcome.label} → ${outcome.label}'}'
      '${reopenFrom == null ? '' : ', unpair from round $reopenFrom'}'
      '${reason.trim().isEmpty ? '' : ' · ${reason.trim()}'}',
      next,
    );
  }

  /// Rule 22C5: once a result is in, a win by a player who cancelled an
  /// irrevocable bye for that round counts as a draw for prizes.
  static Event _withIrrevocableByeRule(Event e, String gameId) => _withGame(
    e,
    gameId,
    (game, round) => applyIrrevocableByeRule(e, game, round),
  );

  /// [e] with game [gameId] replaced by [update] of it. [update] also receives
  /// the number of the round holding the game; every other game is unchanged.
  static Event _withGame(
    Event e,
    String gameId,
    Game Function(Game game, int round) update,
  ) {
    bool holds(Round r) => r.games.any((g) => g.id == gameId);
    return e.copy(
      sections: [
        for (final s in e.sections)
          s.rounds.any(holds)
              ? s.copy(
                  rounds: [
                    for (final r in s.rounds)
                      holds(r)
                          ? r.copy(
                              games: [
                                for (final g in r.games)
                                  g.id == gameId ? update(g, r.number) : g,
                              ],
                            )
                          : r,
                  ],
                )
              : s,
      ],
    );
  }

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
        _withGame(
          e,
          gameId,
          (g, _) => g.copy(
            outcome: outcome,
            note: reason,
            // An assumption stands in only until the game is resolved.
            pairingAssumption: outcome.resolved ? null : g.pairingAssumption,
            pairingReason: outcome.resolved ? '' : g.pairingReason,
          ),
        ),
        gameId,
      ),
    );
  }

  void setPairingAssumption(String gameId, Outcome assumption, String reason) {
    final (e, game) = _materialize(gameId);
    if (game.outcome.resolved ||
        !assumption.played ||
        assumption.unusual ||
        reason.trim().isEmpty) {
      throw const TournamentException(
        'Choose a win, draw or loss assumption for an unresolved game and record the TD’s reason.',
      );
    }
    // C.04.2 3.1: FIDE pairs an adjourned game as a draw.
    final section = e.sections.firstWhere(
      (s) => s.rounds.any((r) => r.games.any((g) => g.id == gameId)),
    );
    if (section.fideRated && assumption != Outcome.draw) {
      throw const TournamentException(
        'A FIDE section pairs an unfinished game as a draw (C.04.2 3.1). Assume a draw.',
      );
    }
    change(
      'Temporary pairing treatment, board ${game.board}',
      _withGame(
        e,
        gameId,
        (g, _) => g.copy(pairingAssumption: assumption, pairingReason: reason),
      ),
    );
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

  /// Rules 29H3 and 29H4: when the last posted round of [sectionId] still has
  /// unreported games at pairing time, apply [treatment] to each in one
  /// revision. Returns the boards treated.
  List<int> holdOutNonReporters(
    String sectionId, {
    required NonReporterTreatment treatment,
  }) {
    final e = event!, s = _section(sectionId);
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
    if (treatment == NonReporterTreatment.doubleForfeit) {
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
      treatment == NonReporterTreatment.doubleForfeit
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
}

/// Rules 29H3 and 29H4: what happens to a game still unreported when the
/// next round is paired. Each value's [name] is its tool wire format.
enum NonReporterTreatment {
  /// Rule 29H3: score the game as a double forfeit.
  doubleForfeit,

  /// Rule 29H4: hold both players out of the next round with half-point byes.
  halfPointByes;

  /// The treatment called [name], refusing any other value plainly.
  static NonReporterTreatment parse(String name) =>
      values.where((t) => t.name == name).firstOrNull ??
      (throw TournamentException(
        'Unknown treatment "$name". Choose doubleForfeit (rule 29H3) or halfPointByes (rule 29H4).',
      ));
}
