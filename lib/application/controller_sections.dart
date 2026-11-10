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
        'A section that has been paired cannot be deleted: its games are part of the record.',
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

  /// The points a late entrant's bye for posted [round] of [section] scores
  /// when the director does not choose: half a point where the section's
  /// announced bye rules still allow a half-point bye for that round and
  /// the player has not used them up, otherwise zero.
  int lateEntryByePoints(Section section, Player player, int round) =>
      ByePolicy.fromJson(
            section.byeRules,
          ).halfByeProblem(player, round, declared: true) ==
          null
      ? 1
      : 0;

  /// Enters players who are in no section into [sectionId] after it has
  /// been paired, even while its current round is being played. Each gets a
  /// bye recorded on every round already posted: [byes] (round → 0 or 1
  /// half-points) chooses them, and a round it leaves out takes
  /// [lateEntryByePoints]. The next round pairs them like anyone else. This
  /// is an entry, not a move between sections, so it needs no reason and
  /// records no transition.
  void enterLate(
    List<String> ids,
    String sectionId, {
    Map<int, int> byes = const {},
  }) {
    final e = event!, target = _section(sectionId);
    final entering = ids.toSet();
    if (entering.isEmpty) return;
    if (target.rounds.isEmpty) {
      throw TournamentException(
        '${target.name} has not been paired; add the players to it directly.',
      );
    }
    // A fixed schedule or bracket has no place for another player, and
    // turning the section into a Swiss would change the event announced.
    final format = pairingFormat(target);
    if (const [
      Format.quad,
      Format.roundRobin,
      Format.knockout,
      Format.scheveningen,
    ].contains(format)) {
      throw TournamentException(
        '${target.name} is a ${format == Format.quad ? 'quad' : format.label.toLowerCase()} that has started, and its schedule has no place for another player. Enter them in a Swiss section instead.',
      );
    }
    for (final MapEntry(key: round, value: points) in byes.entries) {
      if (round < 1 || round > target.rounds.length) {
        throw TournamentException(
          '${target.name} has posted ${target.rounds.length} ${target.rounds.length == 1 ? 'round' : 'rounds'}; a missed-round bye is for one of those.',
        );
      }
      if (points != 0 && points != 1) {
        throw const TournamentException(
          'A missed round scores zero or half a point.',
        );
      }
    }
    final people = {
      for (final id in target.players) e.player(id).personId ?? id: id,
    };
    final awards = <String, Map<int, int>>{};
    for (final id in entering) {
      final p = e.player(id), from = e.sectionOf(id);
      if (from != null) {
        throw TournamentException(
          '${p.name} is in ${from.name}. Move them from there instead.',
        );
      }
      if (p.withdrawn) {
        throw TournamentException(
          '${p.name} has withdrawn. Reinstate them first.',
        );
      }
      final person = p.personId ?? id;
      if (people[person] case final other?) {
        throw TournamentException(
          '${p.name} already has an entry in ${target.name} (${e.player(other).name}).',
        );
      }
      people[person] = id;
      // A ladder has no rounds to miss: batches of challenge games.
      if (target.format == Format.ladder) continue;
      final mine = <int, int>{};
      for (final r in target.rounds) {
        final chosen = byes[r.number];
        final entrant = p.copy(byes: {...p.byes, ...mine});
        if (chosen == 1) {
          final problem = ByePolicy.fromJson(
            target.byeRules,
          ).halfByeProblem(entrant, r.number, declared: true);
          if (problem != null) throw TournamentException(problem);
        }
        mine[r.number] =
            chosen ?? lateEntryByePoints(target, entrant, r.number);
      }
      awards[id] = mine;
    }
    String describe(Map<int, int> mine) => [
      for (final MapEntry(key: round, value: points) in mine.entries)
        'round $round ${points == 1 ? '½' : '0'}',
    ].join(', ');
    final names = [for (final id in entering) e.player(id).name];
    // One list when every entrant has the same byes; otherwise each by name,
    // since the half-point bye limit can give one walk-up ½ and another 0.
    final described = {
      for (final MapEntry(key: id, value: mine) in awards.entries)
        if (mine.isNotEmpty) id: describe(mine),
    };
    final byeNote = described.isEmpty
        ? ''
        : described.values.toSet().length == 1 &&
              described.length == awards.length
        ? ' (byes: ${described.values.first})'
        : ' (byes: ${[for (final MapEntry(key: id, value: text) in described.entries) '${e.player(id).name} $text'].join('; ')})';
    final grown = target.copy(
      players: [...target.players, ...entering],
      rounds: [
        for (final r in target.rounds)
          r.copy(
            byes: [
              ...r.byes,
              for (final MapEntry(key: id, value: mine) in awards.entries)
                ByeAward(id, mine[r.number]!, 'Late entry'),
            ],
          ),
      ],
    );
    change(
      '${names.length == 1 ? 'Enter ${names.single}' : 'Enter ${names.length} players'} late in ${target.name}$byeNote',
      e.copy(
        // The byes stay on the player too, so a round posted again gives
        // the same bye and the half-point bye limit counts them.
        players: [
          for (final p in e.players)
            awards[p.id] == null
                ? p
                : p.copy(byes: {...p.byes, ...awards[p.id]!}),
        ],
        sections: keepBoardRanges(
          e.sections,
          [for (final s in e.sections) s.id == target.id ? grown : s],
          {target.id},
        ),
      ),
    );
  }

  /// Moves entries into [targetId]. Players who are in no section and join
  /// a section that has been paired are late entries ([enterLate], with the
  /// missed-round byes of [lateByes]); everything else is a move or a
  /// combination of sections, which after play started needs a [reason].
  void movePlayers(
    List<String> ids,
    String targetId, {
    String reason = '',
    Map<int, int> lateByes = const {},
  }) {
    final e = event!;
    final target = _section(targetId);
    final unknown = ids.where((id) => !e.players.any((p) => p.id == id));
    if (unknown.isNotEmpty) {
      throw const TournamentException('A selected player no longer exists.');
    }
    if (ids.isNotEmpty &&
        target.rounds.isNotEmpty &&
        ids.every((id) => e.sectionOf(id) == null)) {
      enterLate(ids, targetId, byes: lateByes);
      return;
    }
    final sources = e.sections
        .where((s) => s.id != targetId && s.players.any(ids.contains))
        .toList();
    // Bughouse partners are fixed once round 1 is posted; before that a
    // move leaves the partner unpartnered, as setPartners describes.
    for (final s in sources.where((s) => s.rounds.isNotEmpty)) {
      for (final pair in s.partners) {
        if (pair.any(ids.contains)) {
          throw TournamentException(
            '${e.player(pair[0]).name} and ${e.player(pair[1]).name} are partners in ${s.name}, and partnerships are fixed once round 1 is posted.',
          );
        }
      }
    }
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
        'Enter the results of the round being played before moving players between sections.',
      );
    }
    if (affected.any((s) => s.rounds.length != target.rounds.length)) {
      throw const TournamentException(
        'These sections have played different numbers of rounds, so players cannot move between them.',
      );
    }
    if (affected.any((s) => s.rounds.isNotEmpty) && reason.trim().isEmpty) {
      throw const TournamentException(
        'Say why the players are moving. Games already played stay with the section they were played in, on the wall chart and in the rating report.',
      );
    }
    // Side-game entries and re-entries are the same person as another entry;
    // a section holds at most one entry per person.
    final people = <String, String>{
      for (final id in target.players)
        if (!ids.contains(id)) e.player(id).personId ?? id: id,
    };
    for (final id in ids.toSet()) {
      final p = e.player(id), person = p.personId ?? id;
      if (people[person] case final other? when other != id) {
        throw TournamentException(
          '${p.name} already has an entry in ${target.name} (${e.player(other).name}).',
        );
      }
      people[person] = id;
    }
    final members = {...target.players, ...ids}.toList();
    // Before any play a move is only a roster edit; afterwards the merged
    // section's schedule no longer holds, so it continues as a Swiss.
    final played = affected.any((s) => s.rounds.isNotEmpty);
    // Partners moved together into a bughouse section stay partners; one
    // moved alone leaves the other unpartnered, as setPartners describes.
    final carried = target.format == Format.bughouse
        ? [
            for (final s in sources)
              for (final pair in s.partners)
                if (pair.every(ids.contains)) pair,
          ]
        : const <List<String>>[];
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
        partners: [
          for (final pair in s.partners)
            if (pair.every(players.contains)) pair,
          if (s.id == targetId) ...carried,
        ],
        format: s.id == targetId && played ? Format.swiss : null,
        // A manual quad schedule names roster slots, which shift.
        quadPairings: const [],
      );
    }).toList();
    final allocated = keepBoardRanges(e.sections, sections, changed);
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
