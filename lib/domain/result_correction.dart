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

  /// Whether transfer [t] may carry this game's result into its target,
  /// that is, whether it took effect after this round. Scores travel with
  /// the players: standings count every section's games.
  ///
  /// `effectiveRound` numbers the target's rounds, so it is comparable with
  /// this round only while the two sections are in step. A transfer of a
  /// player who played (or had a bye) here in this round or later happened
  /// after this round too, however few rounds the target had then.
  bool _carriesThisRound(Json t) {
    if ((t['effectiveRound'] as int) > round.number) return true;
    if (t['target'] == section.id) return false;
    final moved = (t['players'] as List).cast<String>().toSet();
    return section.rounds
        .where((r) => r.number >= round.number)
        .any(
          (r) =>
              r.games.any(
                (g) => moved.contains(g.white) || moved.contains(g.black),
              ) ||
              r.byes.any((b) => moved.contains(b.player)),
        );
  }

  /// Section ID → the first of its rounds that may depend on this result:
  /// for another section, the effective round of the earliest transfer
  /// that carried scores into it; for this one, the next round. Transfers
  /// are followed transitively, and conservatively: a connected section is
  /// protected even when this correction changes no pairing of it.
  late final Map<String, int> _dependentFrom = () {
    final from = {section.id: round.number + 1};
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
        if (!_carriesThisRound(t)) continue;
        final target = t['target'] as String;
        final moved = (t['players'] as List).cast<String>();
        if (!moved.any(players.contains) && !from.containsKey(target)) {
          continue;
        }
        final effective = t['effectiveRound'] as int;
        if (target != section.id &&
            (from[target] == null || effective < from[target]!)) {
          from[target] = effective;
          changed = true;
        }
        final known = players.length;
        players.addAll(moved);
        for (final s in event.sections.where((s) => from.containsKey(s.id))) {
          players.addAll(s.players);
        }
        // New players can link transfers already passed over.
        if (players.length != known) changed = true;
      }
    }
    return from;
  }();

  /// This section and every section a transfer links to this result.
  late final Set<String> connectedSections = _dependentFrom.keys.toSet();

  /// Whether a transfer carried this result into a connected section, or a
  /// later transfer brought players into this one. Reopening is refused
  /// then ([canReopenFrom]).
  bool get hasTransfers => event.transitions.any(
    (t) => _carriesThisRound(t) && connectedSections.contains(t['target']),
  );

  /// Rounds of other sections that may have been paired on this result.
  /// They are shown, never removed: [apply] only reopens this section.
  ///
  /// Invariant: non-empty only when [hasTransfers]. Every section other than
  /// this one enters [connectedSections] as the target of a transfer that
  /// [_carriesThisRound], and such a transfer makes [hasTransfers] true. So
  /// reopening, which [hasTransfers] refuses, never leaves these rounds
  /// paired on scores from rounds that no longer exist.
  List<(Section, Round)> get relatedRounds => [
    for (final s in event.sections)
      if (s.id != section.id && _dependentFrom.containsKey(s.id))
        for (final r in s.rounds)
          if (r.number >= _dependentFrom[s.id]!) (s, r),
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

  /// The event with this game's result set to [outcome]. With [reopenFrom],
  /// this section's rounds from that number on are removed as well; rounds
  /// of other sections are never touched, which is sound only because
  /// [canReopenFrom] refuses whenever [relatedRounds] could be non-empty.
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
    assert(
      reopenFrom == null || relatedRounds.isEmpty,
      'Reopening would leave rounds of a connected section paired on '
      'scores from removed rounds.',
    );
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
