part of 'tournament_controller_core.dart';

/// Quads and round robins: grouping by rating, numbers by lot, the manual
/// quad schedule, and the read-only projection of unposted quad rounds.
mixin _QuadCommands on _CommandContext {
  List<Section> quadPreview() => makeQuads(event!, newId);
  void applyQuads(List<Section> sections, int expectedRevision) {
    if (event!.revision != expectedRevision) {
      throw const TournamentException(
        'The roster changed. Preview the groups again.',
      );
    }
    change('Make quads', event!.copy(sections: sections));
  }

  /// Rule 30A: assigns a round-robin or quad section's pairing numbers by
  /// lot. The shuffle is seeded and the seed is in the audited action, so the
  /// draw can be reproduced; posted rounds fix the numbers.
  void drawLots(String sectionId, {int? seed}) {
    final e = event!, section = _section(sectionId);
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

  /// Rule 30H / 30I: splits the unassigned, non-withdrawn roster (or
  /// [players]) into Holland preliminary round robins. Only before play.
  List<String> makeHolland({
    required int groups,
    required int qualifiers,
    bool unbalanced = false,
    List<String>? players,
  }) {
    final e = event!;
    if (e.sections.any((s) => s.rounds.isNotEmpty)) {
      throw const TournamentException(
        'Rounds are already posted. Create the Holland prelims before any section is paired.',
      );
    }
    final pool = players == null
        ? e.players.where((p) => !p.withdrawn && e.sectionOf(p.id) == null)
        : players.map(e.player);
    final ids = pool.map((p) => p.id).toSet();
    final prelims = planHolland(
      e.copy(sections: _without(e, ids)),
      pool,
      groups: groups,
      qualifiers: qualifiers,
      unbalanced: unbalanced,
      id: newId,
    );
    change(
      'Make ${prelims.length} Holland prelims${unbalanced ? ' (30I)' : ''}',
      e.copy(sections: [..._without(e, ids), ...prelims]),
    );
    return [for (final s in prelims) s.id];
  }

  /// Creates the final of a Holland [group] once every prelim has finished:
  /// the qualifiers enter it separately with a fresh score. A tie on every
  /// tie-break at the cut is broken by lot (34E13); the seed is recorded in
  /// the action so the draw can be reproduced.
  String makeHollandFinal(String group, {int? seed}) {
    final e = event!;
    final drawn = seed ?? Random().nextInt(1 << 31);
    final (:section, :entries) = finalsFor(e, group, newId, seed: drawn);
    final prelims = hollandPrelims(e, group);
    change(
      'Create ${section.name} from ${prelims.length} prelims (seed $drawn)',
      e.copy(
        players: [...e.players, ...entries],
        sections: [...e.sections, section],
      ),
    );
    return section.id;
  }

  /// The sections with [ids] taken out of their unpaired rosters, and any
  /// section that leaves empty removed.
  static List<Section> _without(Event e, Set<String> ids) {
    final emptied = sectionsEmptiedBy(e, ids);
    return [
      for (final s in e.sections)
        if (!emptied.contains(s.id))
          s.players.any(ids.contains)
              ? s.copy(
                  players: s.players.where((id) => !ids.contains(id)).toList(),
                  quadPairings: const [],
                )
              : s,
    ];
  }
}

/// The quad projection of one event revision, keyed by that revision's object.
typedef _Projection = ({
  Event source,
  Event projected,
  Map<String, String> issues,
});
