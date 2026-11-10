import 'knockout.dart';
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

  /// Later rounds were made from this result: a Swiss or bughouse pairing
  /// read the scores, and a knockout round holds whoever advanced.
  bool get hasDependencies =>
      (const [
            Format.swiss,
            Format.bughouse,
            Format.knockout,
          ].contains(section.format) &&
          later.isNotEmpty) ||
      hasTransfers;

  /// Knockout: the posted bracket round that correcting this game to
  /// [outcome] would leave paired with a player who no longer advances
  /// into it, as its name and first round number; null when the bracket
  /// stays whole.
  ({String name, int round})? replacedStage(Outcome outcome) {
    if (section.format != Format.knockout) return null;
    final corrected = _corrected(outcome);
    final stage = knockoutBracket(
      corrected,
      corrected.sections.firstWhere((s) => s.id == section.id),
    ).stages.where((s) => s.replaced.isNotEmpty).firstOrNull;
    return stage == null
        ? null
        : (name: stage.name, round: stage.rounds.first.number);
  }

  /// The event with only the game's outcome changed.
  Event _corrected(Outcome outcome) => event.copy(
    sections: [
      for (final s in event.sections)
        s.id != section.id
            ? s
            : s.copy(
                rounds: [
                  for (final r in s.rounds)
                    r.number != round.number
                        ? r
                        : r.copy(
                            games: [
                              for (final g in r.games)
                                g.id != gameId ? g : g.copy(outcome: outcome),
                            ],
                          ),
                ],
              ),
    ],
  );

  bool canReopenFrom(int number) =>
      !hasTransfers &&
      later.any((r) => r.number == number) &&
      later.where((r) => r.number >= number).every((r) => !r.hasPlay);

  Event apply(
    Outcome outcome, {
    String reason = '',
    int? reopenFrom,
    bool confirmedUnstarted = false,
    bool? adjudicated,
    bool? shortGame,
  }) {
    if (reopenFrom != null &&
        (!canReopenFrom(reopenFrom) || !confirmedUnstarted)) {
      throw const TournamentException(
        'Only later rounds without recorded play or section transfers can be reopened. Confirm that none of their games have started.',
      );
    }
    // A knockout round paired with a player this correction puts out cannot
    // be played as posted. While none of it has started it is unpaired with
    // the correction; once it has, the correction stands and the bracket
    // asks for that round to be paired again.
    if (replacedStage(outcome) case (:final name, round: final first)
        when first > round.number &&
            canReopenFrom(first) &&
            (reopenFrom == null || reopenFrom > first)) {
      throw TournamentException(
        'This result changes who advances, and the $name (round $first) is already paired with the player it puts out. '
        'Choose "Unpair from round $first" so the $name can be paired again.',
      );
    }
    final next = event.copy(
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
                                            // Rule 18G: an adjudicated result
                                            // stays marked until unmarked.
                                            adjudicated:
                                                adjudicated ?? g.adjudicated,
                                            // FIDE: a game of less than one
                                            // move, kept only on a played
                                            // 1–0, ½–½ or 0–1.
                                            shortGame:
                                                (shortGame ?? g.shortGame) &&
                                                outcome.played &&
                                                !outcome.unusual &&
                                                section.fideRated,
                                            // The note is optional; an empty
                                            // one keeps what the game had.
                                            note: reason.trim().isEmpty
                                                ? g.note
                                                : reason.trim(),
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
    if (section.format != Format.knockout || reopenFrom == null) return next;
    // Unpairing bracket rounds takes their record and decisions with them.
    return next.copy(
      sections: [
        for (final s in next.sections)
          s.id == section.id ? knockoutAfterPost(next, s) : s,
      ],
    );
  }
}
