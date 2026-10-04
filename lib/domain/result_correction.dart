import 'model.dart';

/// A review is tied to one immutable event revision and stable game identity.
/// Reopening always removes a suffix; keeping a later round while removing its
/// prerequisites would leave the competition in an incoherent state.
class ResultCorrection {
  ResultCorrection(this.event, this.gameId) {
    for (final s in event.sections) {
      for (final r in s.rounds) {
        for (final g in r.games) {
          if (g.id == gameId) {
            section = s;
            round = r;
            game = g;
            return;
          }
        }
      }
    }
    throw const TournamentException('This game is no longer in the event.');
  }

  final Event event;
  final String gameId;
  late final Section section;
  late final Round round;
  late final Game game;
  List<Round> get later =>
      section.rounds.where((r) => r.number > round.number).toList();

  // Transfers carry scores into another section. Conservatively protect the
  // connected sections, even when the particular correction changes no pairing.
  late final Set<String> connectedSections = () {
    final ids = {section.id};
    final players = <String>{
      ...section.players,
      for (final r in section.rounds)
        ...r.games.expand((g) => [g.white, g.black]),
      for (final r in section.rounds) ...r.byes.map((b) => b.player),
    };
    var changed = true;
    while (changed) {
      changed = false;
      for (final t in event.transitions) {
        if ((t['effectiveRound'] as int) <= round.number) continue;
        final moved = (t['players'] as List).cast<String>();
        if (!moved.any(players.contains) && !ids.contains(t['target'])) {
          continue;
        }
        if (ids.add(t['target'] as String)) changed = true;
        players.addAll(moved);
        for (final s in event.sections.where((s) => ids.contains(s.id))) {
          players.addAll(s.players);
        }
      }
    }
    return ids;
  }();

  bool get hasTransfers => event.transitions.any(
    (t) =>
        (t['effectiveRound'] as int) > round.number &&
        connectedSections.contains(t['target']),
  );
  List<(Section, Round)> get relatedRounds => [
    for (final s in event.sections)
      if (s.id != section.id && connectedSections.contains(s.id))
        for (final r in s.rounds)
          if (r.number > round.number) (s, r),
  ];
  bool get hasDependencies =>
      (section.format == Format.swiss && later.isNotEmpty) || hasTransfers;

  bool canReopenFrom(int number) =>
      !hasTransfers &&
      later.any((r) => r.number == number) &&
      later.where((r) => r.number >= number).every((r) => !r.hasPlay);

  Event apply(
    Outcome outcome, {
    required String reason,
    int? reopenFrom,
    bool confirmedUnstarted = false,
  }) {
    if (reason.trim().isEmpty) {
      throw const TournamentException(
        'Give a reason for changing this result.',
      );
    }
    if (reopenFrom != null &&
        (!canReopenFrom(reopenFrom) || !confirmedUnstarted)) {
      throw const TournamentException(
        'Only later rounds without recorded play or section transfers can be reopened. Confirm that none of their games have started.',
      );
    }
    return event.copy(
      sections: [
        for (final s in event.sections)
          s.id != section.id
              ? s
              : s.copy(
                  rounds: [
                    for (final r in s.rounds)
                      if (reopenFrom == null || r.number < reopenFrom)
                        r.number != round.number
                            ? r
                            : r.copy(
                                games: [
                                  for (final g in r.games)
                                    g.id != gameId
                                        ? g
                                        : g.copy(
                                            outcome: outcome,
                                            note: reason.trim(),
                                            pairingAssumption: outcome.resolved
                                                ? null
                                                : g.pairingAssumption,
                                            pairingReason: outcome.resolved
                                                ? ''
                                                : g.pairingReason,
                                          ),
                                ],
                              ),
                  ],
                ),
      ],
    );
  }
}
