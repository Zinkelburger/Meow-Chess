part of 'tournament_controller_core.dart';

/// Ratings and membership evidence: reviewed supplement ratings and US Chess
/// membership checks, plus the rules a TD-assigned rating must meet.
mixin _RatingCommands on _CommandContext {
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

bool _hasClassPrizeFor(Section section, int rating) {
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
