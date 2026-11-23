import 'eligibility.dart';
import 'fixed_schedule.dart';
import 'model.dart';
import 'pairing.dart' show pairingRestricted;
import 'prizes.dart';
import 'us_chess.dart' show isMemberId, nameKey;

/// How much a finding matters to the director.
enum CheckLevel {
  /// The event cannot go on as it stands.
  fix('Fix'),

  /// Probably a mistake; look before the next round.
  look('Look'),

  /// Allowed, and worth knowing.
  note('Note');

  const CheckLevel(this.label);
  final String label;
}

/// One thing a check found.
class CheckFinding {
  const CheckFinding(
    this.level,
    this.message, {
    this.sectionId = '',
    this.round = 0,
    this.players = const [],
  });
  final CheckLevel level;
  final String message;

  /// The section and round it is about, when it is about one (else empty
  /// and zero), and the players it names.
  final String sectionId;
  final int round;
  final List<String> players;
}

/// One check of the event: what it looked at and what it found. A check
/// that did not apply says why in [skipped], so a check that never ran is
/// not mistaken for a clean one.
class CheckLine {
  const CheckLine(
    this.title, {
    this.examined = '',
    this.skipped,
    this.findings = const [],
  });
  final String title;

  /// What was looked at, such as `24 pairings`. Empty when [skipped].
  final String examined;

  /// Why the check did not apply, or null when it ran.
  final String? skipped;
  final List<CheckFinding> findings;
  bool get ran => skipped == null;
  bool get clear => ran && findings.isEmpty;

  /// The line a director reads: `Clear: 24 pairings checked`.
  String get verdict => !ran
      ? 'Not checked: $skipped'
      : findings.isEmpty
      ? 'Clear: $examined checked'
      : '${findings.length} found: $examined checked';
}

/// The checks of an event or of one section, in the order they ran.
class EventCheck {
  const EventCheck(this.scope, this.checks);

  /// What was checked: the event's name, or the section's.
  final String scope;
  final List<CheckLine> checks;

  /// Every finding, the most serious first; within a level, in check order.
  List<CheckFinding> get findings => [
    for (final level in CheckLevel.values)
      for (final check in checks)
        ...check.findings.where((f) => f.level == level),
  ];

  /// The whole check as plain text, for the clipboard.
  String report() {
    final found = findings;
    return [
      'Check of $scope',
      found.isEmpty
          ? 'Nothing found.'
          : '${found.length} ${found.length == 1 ? 'finding' : 'findings'}.',
      '',
      if (found.isNotEmpty) ...[
        'Found',
        for (final f in found) '  ${f.level.label}: ${f.message}',
        '',
      ],
      'Checked',
      for (final c in checks) '  ${c.title}: ${c.verdict}',
    ].join('\n');
  }
}

String _count(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : many ?? '${one}s'}';

/// Whether [g] put its two players across a board: a played game, or one
/// still to be played. A forfeit is not a meeting (rule 29E1 treats the
/// game as unplayed), so the two may be paired again.
bool _met(Game g) => g.outcome.played || !g.outcome.resolved;

/// Checks [event], or only the section [sectionId], for the mistakes a
/// director wants to hear about before the next round. Nothing here blocks
/// or repairs anything: the event's structure is already guarded when it is
/// saved (`validateEvent`), and these are the judgment calls on top.
EventCheck checkEvent(Event event, {String? sectionId}) {
  final sections = [
    for (final s in event.sections)
      if (sectionId == null || s.id == sectionId) s,
  ];
  final whole = sectionId == null;
  if (sections.isEmpty && !whole) {
    throw const TournamentException('That section is no longer in the event.');
  }
  String name(String id) => event.player(id).name;
  final checks = <CheckLine>[
    _unfinishedRounds(sections),
    _unpaired(event, sections, name),
    _withdrawnOnBoards(event, sections, name),
    _rematches(sections, name),
    _colors(sections, name),
    _fullPointByes(sections, name),
    _halfPointByes(sections, name),
    _requests(event, sections, name),
    _teammates(event, sections, name),
    _ratingRanges(event, sections),
    _prizes(event, sections),
    if (whole) ...[
      _twoSections(event, name),
      _noSection(event),
      _behind(event),
    ],
  ];
  return EventCheck(whole ? event.name : sections.first.name, checks);
}

CheckLine _unfinishedRounds(List<Section> sections) {
  final findings = <CheckFinding>[];
  var rounds = 0;
  for (final s in sections) {
    rounds += s.rounds.length;
    for (final r in s.rounds) {
      final missing = r.games.where((g) => !g.outcome.resolved).length;
      if (missing == 0 || r.number == s.rounds.length) continue;
      // A fixed schedule posts every round at once; its coming rounds are
      // not late.
      if (hasFixedSchedule(s) &&
          s.rounds.skip(r.number).every((later) => !later.hasPlay)) {
        continue;
      }
      findings.add(
        CheckFinding(
          CheckLevel.look,
          '${s.name}: round ${r.number} is missing '
          '${_count(missing, 'result')} and round ${s.rounds.length} is '
          'already up.',
          sectionId: s.id,
          round: r.number,
        ),
      );
    }
  }
  return CheckLine(
    'Results missing from an earlier round',
    examined: _count(rounds, 'round'),
    skipped: rounds == 0 ? 'no round is paired yet' : null,
    findings: findings,
  );
}

/// The round a section is on: its last posted round, when that round pairs
/// the whole field (Swiss and bughouse). Null for formats where sitting out
/// is normal.
Round? _currentFieldRound(Section s) =>
    s.rounds.isNotEmpty &&
        const [Format.swiss, Format.bughouse].contains(pairingFormat(s)) &&
        !s.sideGames
    ? s.rounds.last
    : null;

CheckLine _unpaired(
  Event event,
  List<Section> sections,
  String Function(String) name,
) {
  final findings = <CheckFinding>[];
  var players = 0;
  for (final s in sections) {
    final r = _currentFieldRound(s);
    if (r == null) continue;
    final seated = {
      for (final g in r.games) ...[
        g.white,
        g.black,
        if (g.whitePartner.isNotEmpty) g.whitePartner,
        if (g.blackPartner.isNotEmpty) g.blackPartner,
      ],
      for (final b in r.byes) b.player,
    };
    for (final id in s.players) {
      if (event.player(id).withdrawn) continue;
      players++;
      if (seated.contains(id)) continue;
      findings.add(
        CheckFinding(
          CheckLevel.look,
          '${s.name}: ${name(id)} has no game and no bye in round '
          '${r.number}.',
          sectionId: s.id,
          round: r.number,
          players: [id],
        ),
      );
    }
  }
  return CheckLine(
    'Everyone has a game or a bye',
    examined: _count(players, 'player'),
    skipped: players == 0 ? 'no Swiss section has a round up' : null,
    findings: findings,
  );
}

CheckLine _withdrawnOnBoards(
  Event event,
  List<Section> sections,
  String Function(String) name,
) {
  final findings = <CheckFinding>[];
  var games = 0;
  for (final s in sections) {
    for (final r in s.rounds) {
      for (final g in r.games) {
        if (g.outcome != Outcome.unreported) continue;
        games++;
        for (final id in [g.white, g.black]) {
          if (!event.player(id).withdrawn) continue;
          findings.add(
            CheckFinding(
              CheckLevel.look,
              '${s.name}: ${name(id)} has withdrawn and is still on board '
              '${g.board} in round ${r.number}. Re-pair the unstarted boards, '
              'or record the forfeit.',
              sectionId: s.id,
              round: r.number,
              players: [id],
            ),
          );
        }
      }
    }
  }
  return CheckLine(
    'Withdrawn players on a board',
    examined: _count(games, 'game without a result', 'games without a result'),
    skipped: games == 0 ? 'no game is waiting for a result' : null,
    findings: findings,
  );
}

/// Sections whose players should never meet twice.
bool _noRepeats(Section s) =>
    const [Format.swiss, Format.bughouse].contains(pairingFormat(s)) &&
    !s.sideGames;

CheckLine _rematches(List<Section> sections, String Function(String) name) {
  final findings = <CheckFinding>[];
  var pairings = 0;
  for (final s in sections.where(_noRepeats)) {
    final first = <String, int>{};
    for (final r in s.rounds) {
      final seen = <String>{};
      for (final g in r.games.where(_met)) {
        final pair = ([g.white, g.black]..sort()).join('|');
        // Both games of a double round are one pairing.
        if (!seen.add(pair)) continue;
        pairings++;
        final before = first[pair];
        if (before == null) {
          first[pair] = r.number;
          continue;
        }
        findings.add(
          CheckFinding(
            CheckLevel.look,
            '${s.name}: ${name(g.white)} and ${name(g.black)} meet again on '
            'board ${g.board} in round ${r.number}; they played in round '
            '$before.',
            sectionId: s.id,
            round: r.number,
            players: [g.white, g.black],
          ),
        );
      }
    }
  }
  return CheckLine(
    'Players paired against each other twice',
    examined: _count(pairings, 'pairing'),
    skipped: pairings == 0 ? 'no Swiss section has a round up' : null,
    findings: findings,
  );
}

/// Sections where the pairing gives out colors: one game a round, round by
/// round.
bool _colorsMatter(Section s) =>
    pairingFormat(s) == Format.swiss && !s.doubleGames && !s.sideGames;

CheckLine _colors(List<Section> sections, String Function(String) name) {
  final findings = <CheckFinding>[];
  var assignments = 0;
  for (final s in sections.where(_colorsMatter)) {
    // The run of one color each player is on: +n white, -n black.
    final run = <String, int>{};
    for (final r in s.rounds) {
      for (final g in r.games.where(_met)) {
        for (final (id, color) in [(g.white, 1), (g.black, -1)]) {
          assignments++;
          final before = run[id] ?? 0;
          final now = before.sign == color ? before + color : color;
          run[id] = now;
          if (now.abs() < 3) continue;
          findings.add(
            CheckFinding(
              CheckLevel.look,
              '${s.name}: ${name(id)} has ${color > 0 ? 'White' : 'Black'} '
              'for the ${now.abs() == 3 ? 'third' : '${now.abs()}th'} game '
              'in a row in round ${r.number} (board ${g.board}).',
              sectionId: s.id,
              round: r.number,
              players: [id],
            ),
          );
        }
      }
    }
  }
  return CheckLine(
    'The same color three games in a row',
    examined: _count(assignments, 'color'),
    skipped: assignments == 0 ? 'no Swiss section has a round up' : null,
    findings: findings,
  );
}

CheckLine _fullPointByes(List<Section> sections, String Function(String) name) {
  final findings = <CheckFinding>[];
  var byes = 0;
  for (final s in sections) {
    final full = s.doubleGames ? 4 : 2;
    final got = <String, int>{};
    for (final r in s.rounds) {
      for (final b in r.byes.where((b) => b.allocated && b.points == full)) {
        byes++;
        final before = got[b.player];
        got[b.player] = r.number;
        if (before == null) continue;
        findings.add(
          CheckFinding(
            CheckLevel.look,
            '${s.name}: ${name(b.player)} has the full-point bye in round '
            '${r.number} and already had it in round $before.',
            sectionId: s.id,
            round: r.number,
            players: [b.player],
          ),
        );
      }
    }
  }
  return CheckLine(
    'A second full-point bye for the same player',
    examined: _count(byes, 'full-point bye'),
    skipped: byes == 0 ? 'no full-point bye has been given' : null,
    findings: findings,
  );
}

CheckLine _halfPointByes(List<Section> sections, String Function(String) name) {
  final findings = <CheckFinding>[];
  var byes = 0, limited = 0;
  for (final s in sections) {
    final rules = s.byeRules;
    if (rules.maxHalfByes == 0 && rules.lastHalfByeRound == 0) continue;
    limited++;
    final half = s.doubleGames ? 2 : 1;
    final taken = <String, int>{};
    for (final r in s.rounds) {
      for (final b in r.byes.where((b) => !b.allocated && b.points == half)) {
        byes++;
        final n = taken[b.player] = (taken[b.player] ?? 0) + 1;
        if (rules.maxHalfByes > 0 && n == rules.maxHalfByes + 1) {
          findings.add(
            CheckFinding(
              CheckLevel.look,
              '${s.name}: ${name(b.player)} has ${_count(n, 'half-point bye')}'
              '; the section allows ${rules.maxHalfByes}.',
              sectionId: s.id,
              round: r.number,
              players: [b.player],
            ),
          );
        }
        if (rules.lastHalfByeRound > 0 && r.number > rules.lastHalfByeRound) {
          findings.add(
            CheckFinding(
              CheckLevel.look,
              '${s.name}: ${name(b.player)} has a half-point bye in round '
              '${r.number}; the section allows them through round '
              '${rules.lastHalfByeRound}.',
              sectionId: s.id,
              round: r.number,
              players: [b.player],
            ),
          );
        }
      }
    }
  }
  return CheckLine(
    'Half-point byes within the announced limit',
    examined: _count(byes, 'half-point bye'),
    skipped: limited == 0 ? 'no section limits half-point byes' : null,
    findings: findings,
  );
}

CheckLine _requests(
  Event event,
  List<Section> sections,
  String Function(String) name,
) {
  final findings = <CheckFinding>[];
  final asked = sections
      .expand((s) => s.players)
      .where((id) => event.player(id).avoid.isNotEmpty)
      .length;
  var games = 0;
  for (final s in sections) {
    for (final r in s.rounds) {
      for (final g in r.games.where((g) => g.leg == 1)) {
        games++;
        if (!pairingRestricted(event, g.white, g.black)) continue;
        findings.add(
          CheckFinding(
            CheckLevel.look,
            '${s.name}: ${name(g.white)} and ${name(g.black)} asked not to '
            'be paired and are on board ${g.board} in round ${r.number}.',
            sectionId: s.id,
            round: r.number,
            players: [g.white, g.black],
          ),
        );
      }
    }
  }
  return CheckLine(
    'Do-not-pair requests',
    examined: _count(games, 'pairing'),
    skipped: asked == 0
        ? 'nobody has a do-not-pair request'
        : games == 0
        ? 'no round is paired yet'
        : null,
    findings: findings,
  );
}

CheckLine _teammates(
  Event event,
  List<Section> sections,
  String Function(String) name,
) {
  final findings = <CheckFinding>[];
  var games = 0, avoiding = 0;
  for (final s in sections.where((s) => s.avoidTeammates)) {
    avoiding++;
    for (final r in s.rounds) {
      for (final g in r.games.where((g) => g.leg == 1)) {
        games++;
        final team = event.player(g.white).team.trim().toLowerCase();
        if (team.isEmpty ||
            team != event.player(g.black).team.trim().toLowerCase()) {
          continue;
        }
        findings.add(
          CheckFinding(
            CheckLevel.note,
            '${s.name}: team-mates ${name(g.white)} and ${name(g.black)} '
            '(${event.player(g.white).team.trim()}) are paired on board '
            '${g.board} in round ${r.number}.',
            sectionId: s.id,
            round: r.number,
            players: [g.white, g.black],
          ),
        );
      }
    }
  }
  return CheckLine(
    'Team-mates paired against each other',
    examined: _count(games, 'pairing'),
    skipped: avoiding == 0
        ? 'no section avoids pairing team-mates'
        : games == 0
        ? 'no round is paired yet'
        : null,
    findings: findings,
  );
}

CheckLine _ratingRanges(Event event, List<Section> sections) {
  final findings = <CheckFinding>[];
  var players = 0, ranged = 0;
  for (final s in sections) {
    // An open section has no range of its own, but the play-up rule
    // still sets a lowest rating for it.
    if (s.ratingFloor == 0 &&
        s.ratingCeiling == 0 &&
        playUpFloor(event, s) == 0) {
      continue;
    }
    ranged++;
    players += s.players.length;
    for (final MapEntry(key: id, value: problem) in sectionRangeProblems(
      event,
      s,
    ).entries) {
      findings.add(
        CheckFinding(
          CheckLevel.look,
          '${event.player(id).name}: $problem',
          sectionId: s.id,
          players: [id],
        ),
      );
    }
  }
  return CheckLine(
    'Ratings inside each section\'s range',
    examined: _count(players, 'player'),
    skipped: ranged == 0 ? 'no section has a rating range' : null,
    findings: findings,
  );
}

CheckLine _prizes(Event event, List<Section> sections) {
  final findings = <CheckFinding>[];
  var prizes = 0;
  for (final s in sections) {
    if (s.players.isEmpty) continue;
    final allocation = allocatePrizes(event, s);
    for (final p in allocation.table.list) {
      prizes++;
      if (allocation.eligible[p.id] != 0) continue;
      findings.add(
        CheckFinding(
          CheckLevel.look,
          '${s.name}: nobody entered can win ${p.title}. Check its rating '
          'range and the players it names.',
          sectionId: s.id,
        ),
      );
    }
  }
  return CheckLine(
    'Prizes somebody can win',
    examined: _count(prizes, 'prize'),
    skipped: prizes == 0 ? 'no section with players announces prizes' : null,
    findings: findings,
  );
}

CheckLine _twoSections(Event event, String Function(String) name) {
  final findings = <CheckFinding>[];
  // Side games and re-entries are meant to repeat a person.
  final main = event.sections.where((s) => !s.sideGames).toList();
  final seen = <String, (String, Section)>{};
  var players = 0;
  for (final s in main) {
    for (final id in s.players) {
      final p = event.player(id);
      if (p.withdrawn || p.house) continue;
      players++;
      final keys = [
        if (isMemberId(p.memberId)) 'id:${p.memberId}',
        'name:${nameKey(p.name)}',
      ];
      for (final key in keys) {
        final before = seen[key];
        if (before == null) {
          seen[key] = (id, s);
          continue;
        }
        final (otherId, otherSection) = before;
        final other = event.player(otherId);
        if (otherSection.id == s.id && key.startsWith('name:')) {
          // Two people may share a name; in one section it is plain to see.
          continue;
        }
        if (p.reentryOf == otherId || other.reentryOf == id) continue;
        // Two IDs settle that same-named entries are different people.
        if (key.startsWith('name:') &&
            isMemberId(p.memberId) &&
            isMemberId(other.memberId)) {
          continue;
        }
        findings.add(
          CheckFinding(
            CheckLevel.look,
            otherSection.id == s.id
                ? '${s.name}: ${name(id)} and ${name(otherId)} have the same '
                      'US Chess ID, ${p.memberId}.'
                : '${name(id)} is entered in ${otherSection.name} and in '
                      '${s.name}'
                      '${key.startsWith('id:') ? '' : ' (same name; no ID to tell them apart)'}'
                      '.',
            sectionId: s.id,
            players: [otherId, id],
          ),
        );
        break;
      }
    }
  }
  return CheckLine(
    'The same person entered twice',
    examined: _count(players, 'player'),
    skipped: players == 0 ? 'no players are in a section yet' : null,
    findings: findings,
  );
}

CheckLine _noSection(Event event) {
  final placed = event.sections.expand((s) => s.players).toSet();
  final loose = [
    for (final p in event.players)
      if (!p.withdrawn && !placed.contains(p.id)) p,
  ];
  return CheckLine(
    'Players in no section',
    examined: _count(event.players.length, 'player'),
    skipped: event.players.isEmpty ? 'nobody is registered yet' : null,
    findings: [
      if (loose.isNotEmpty)
        CheckFinding(
          CheckLevel.note,
          '${_count(loose.length, 'player is', 'players are')} in no section: '
          '${loose.take(8).map((p) => p.name).join(', ')}'
          '${loose.length > 8 ? ', and ${loose.length - 8} more' : ''}.',
          players: [for (final p in loose) p.id],
        ),
    ],
  );
}

CheckLine _behind(Event event) {
  // Sections paired a round at a time; a fixed schedule is posted whole.
  final live = [
    for (final s in event.sections)
      if (!s.sideGames &&
          !hasFixedSchedule(s) &&
          const [Format.swiss, Format.bughouse].contains(pairingFormat(s)))
        s,
  ];
  final ahead = live.fold(
    0,
    (m, s) => s.rounds.length > m ? s.rounds.length : m,
  );
  final findings = [
    for (final s in live)
      if (s.rounds.length < ahead &&
          s.rounds.length < s.plannedRounds &&
          s.players.length >= 2 &&
          s.rounds.every((r) => r.complete))
        CheckFinding(
          CheckLevel.note,
          s.rounds.isEmpty
              ? '${s.name} has no round paired; other sections are on round '
                    '$ahead.'
              : '${s.name} has finished round ${s.rounds.length} and round '
                    '${s.rounds.length + 1} is not paired; other sections are '
                    'on round $ahead.',
          sectionId: s.id,
        ),
  ];
  return CheckLine(
    'A section waiting to be paired',
    examined: _count(live.length, 'section'),
    skipped: live.length < 2
        ? 'fewer than two sections are paired round by round'
        : ahead == 0
        ? 'no round is paired yet'
        : null,
    findings: findings,
  );
}
