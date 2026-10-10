part of 'tournament_controller_core.dart';

/// Section structure: creating and removing sections, separate entries, and
/// moving or swapping players between sections.
mixin _SectionCommands on _CommandContext {
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
            unrated: format == Format.bughouse,
          ),
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
      if (kept.any((s) => s.name.trim().toLowerCase() == title.toLowerCase())) {
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
          unrated: format == Format.bughouse,
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
      if (hasFixedSchedule(s) &&
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
            'players': [...ids],
            'target': targetId,
            'effectiveRound': target.rounds.length + 1,
            'reason': reason,
            'revision': e.revision,
          },
        ],
      ),
    );
  }
}
