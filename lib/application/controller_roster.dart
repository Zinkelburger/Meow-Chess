part of 'tournament_controller_core.dart';

/// Player entries: registration and edits, teams, do-not-pair requests,
/// byes, withdrawals and removals.
mixin _RosterCommands on _CommandContext {
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

  /// Reserves, changes or cancels (negative [points]) a future bye. Rules
  /// 22C1–22C4 limit half-point byes by the section's [ByePolicy];
  /// zero-point byes are always allowed. [irrevocable] true declares the
  /// bye irrevocable (22C4), false withdraws the declaration, null keeps
  /// it, so a cancelled irrevocable bye still counts under 22C5.
  void reserveBye(String playerId, int round, int points, {bool? irrevocable}) {
    // Points 0, 1 and 2 are zero, half and full point; the file stores them.
    if (round < 1) {
      throw const TournamentException('Choose a round from 1 on.');
    }
    if (points > 2) {
      throw const TournamentException(
        'A bye is worth zero, half or one point.',
      );
    }
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
}
