part of 'tournament_controller_core.dart';

/// Ladder commands (see `ladder.dart` for the house rules). An extension, so
/// a format can add its commands without touching the controller's mixin
/// list; the same-library privilege reaches [_CommandContext._section].
extension LadderCommands on TournamentControllerCore {
  /// Records one challenge game and reorders the ladder in the same
  /// revision. The challenger has Black unless [challengerWhite]. The game
  /// joins the latest batch (round) when neither player has a game there,
  /// otherwise it opens a new batch. Returns the game's ID.
  String recordLadderGame(
    String sectionId,
    String challengerId,
    String defenderId,
    Outcome outcome, {
    bool challengerWhite = false,
    String reason = '',
  }) {
    final e = event!, s = _section(sectionId);
    if (s.format != Format.ladder) {
      throw TournamentException('${s.name} is not a ladder.');
    }
    String name(String id) => e.player(id).name;
    if (ladderChallengeAllowed(s, challengerId, defenderId, name: name)
        case final problem?) {
      throw TournamentException(problem);
    }
    for (final id in [challengerId, defenderId]) {
      if (e.player(id).withdrawn) {
        throw TournamentException('${name(id)} has withdrawn from the ladder.');
      }
      if (s.rounds
          .expand((r) => r.games)
          .any(
            (g) => !g.outcome.resolved && (g.white == id || g.black == id),
          )) {
        throw TournamentException(
          'Record the result of ${name(id)}’s open game first.',
        );
      }
    }
    if (!outcome.resolved) {
      throw const TournamentException(
        'Record how the challenge ended: a win, a draw, a loss or a forfeit.',
      );
    }
    final last = s.rounds.lastOrNull;
    final append =
        last != null &&
        !last.games.any(
          (g) => [
            g.white,
            g.black,
          ].any((id) => id == challengerId || id == defenderId),
        );
    if (!append && s.rounds.length >= s.plannedRounds) {
      throw TournamentException(
        '${s.name} holds its ${s.plannedRounds} batches of challenge games. Raise the planned rounds in Section settings to record more.',
      );
    }
    final game = ladderGame(
      id: newId(),
      challenger: challengerId,
      defender: defenderId,
      board: s.boardStart + (append ? last.games.length : 0),
      outcome: outcome,
      challengerWhite: challengerWhite,
      note: reason.trim(),
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final rounds = append
        ? [
            ...s.rounds.take(s.rounds.length - 1),
            last.copy(games: [...last.games, game]),
          ]
        : [
            ...s.rounds,
            Round(
              number: s.rounds.length + 1,
              games: [game],
              policy: 'ladder-challenge-v1',
              note: 'Challenge games',
              postedAt: now,
              startedAt: now,
            ),
          ];
    final order = ladderAfterResult(s, game);
    final result = ladderScoreLabel(outcome, fromWhite: challengerWhite);
    change(
      'Ladder challenge: ${name(challengerId)} v. ${name(defenderId)} $result · ${ladderMoves(s.players, order, name)}',
      e.copy(
        sections: [
          for (final x in e.sections)
            x.id == s.id ? x.copy(players: order, rounds: rounds) : x,
        ],
      ),
    );
    secondaryBackup();
    return game.id;
  }

  /// The director's reordering of the ladder: [order] lists every player of
  /// [sectionId] exactly once, top first, and [reason] says why.
  void setLadderOrder(String sectionId, List<String> order, String reason) {
    final e = event!, s = _section(sectionId);
    if (s.format != Format.ladder) {
      throw TournamentException('${s.name} is not a ladder.');
    }
    if (ladderOrderProblem(s, order) case final problem?) {
      throw TournamentException(problem);
    }
    if (reason.trim().isEmpty) {
      throw const TournamentException(
        'Record why the ladder is being reordered.',
      );
    }
    change(
      'Reorder ladder: ${ladderMoves(s.players, order, (id) => e.player(id).name)} · ${reason.trim()}',
      e.copy(
        sections: [
          for (final x in e.sections) x.id == s.id ? x.copy(players: order) : x,
        ],
      ),
    );
  }
}
