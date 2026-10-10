import 'model.dart';
import 'prizes.dart';
import 'standings.dart';

/// Scholastic team awards in a combined individual/team tournament (rule
/// 31A): the event is an ordinary Swiss or round robin, and players from
/// the same school (`Player.team`) also score for their team.
///
/// Sources: US Chess Scholastic Regulations 2026–27 §5.6.1, §10.2.1–10.2.2
/// and §12.3.3; rulebook 31A1 for Rollins scoring.

/// How a team's score is built from its players.
enum TeamScoring {
  /// Scholastic Regulations 10.2.1: the sum of the top N individual
  /// scores (top 4 at Spring Nationals, top 3 at Grade Nationals and
  /// blitz).
  topN('topN', 'Top N scores'),

  /// Rule 31A1, Rollins (military) scoring: each player earns the field
  /// size minus their overall place (the winner of a 100-player event
  /// earns 99), and a team adds its top N players' points.
  rollins('rollins', 'Rollins points');

  const TeamScoring(this.code, this.label);
  final String code, label;
}

/// A section's announced team awards, stored as `Section.prizes['teams']`
/// (see the schema in prizes.dart). Absent means the section has none.
class TeamAwards {
  const TeamAwards({
    this.counting = 4,
    this.method = TeamScoring.topN,
    this.minPlayers = 2,
  });

  /// N, the announced number of scores that count (10.2.1).
  final int counting;
  final TeamScoring method;

  /// The fewest players a team needs to be eligible for a team prize:
  /// 2, with no maximum (5.6.1, 10.2.2).
  final int minPlayers;

  /// The section's team awards, or null when it has none. Throws on a
  /// malformed setting so a bad file or tool call is reported, not ignored.
  static TeamAwards? of(Section section) => fromJson(section.prizes['teams']);

  /// Like [of], but a malformed setting reads as off (for display).
  static TeamAwards? tryOf(Section section) {
    try {
      return of(section);
    } on TournamentException {
      return null;
    }
  }

  static TeamAwards? fromJson(Object? json) {
    if (json == null) return null;
    if (json is! Map) {
      throw const TournamentException(
        'Team awards: teams must be an object with counting, method and minPlayers.',
      );
    }
    int integer(String key, int blank, {int min = 1}) {
      final v = json[key];
      if (v == null) return blank;
      if (v is! int || v < min || v > 99) {
        throw TournamentException(
          'Team awards: $key must be a whole number from $min to 99.',
        );
      }
      return v;
    }

    final code = json['method'] ?? TeamScoring.topN.code;
    final method = TeamScoring.values.where((m) => m.code == code).firstOrNull;
    if (method == null) {
      throw TournamentException(
        'Team awards: unknown method "$code". Use ${TeamScoring.values.map((m) => m.code).join(' or ')}.',
      );
    }
    return TeamAwards(
      counting: integer('counting', 4),
      method: method,
      minPlayers: integer('minPlayers', 2),
    );
  }

  Json toJson() => {
    'counting': counting,
    'method': method.code,
    'minPlayers': minPlayers,
  };

  /// One line for the panel summary and the conditions sheet.
  String get summary => switch (method) {
    TeamScoring.topN => 'Top $counting scores count',
    TeamScoring.rollins => 'Rollins points, top $counting count',
  };

  /// The announced method in full, with its rules.
  String get description =>
      '${switch (method) {
        TeamScoring.topN => 'team score is the sum of the top $counting individual scores (Scholastic Regulations 10.2.1)',
        TeamScoring.rollins => 'team score is the sum of the top $counting Rollins points, each player earning the field size minus their place (rule 31A1)',
      }}; at least $minPlayers players for a team prize (10.2.2); '
      'team tie-breaks: ${teamTiebreakLabels.join(', ')} (12.3.3)';
}

/// [section] with its team awards set to [awards], or removed when null.
Section withTeamAwards(Section section, TeamAwards? awards) => section.copy(
  prizes: {
    for (final e in section.prizes.entries)
      if (e.key != 'teams') e.key: e.value,
    if (awards != null) 'teams': awards.toJson(),
  },
);

/// Team labels compare like pairing's team-mate test: trimmed, any case.
String teamKey(String label) => label.trim().toLowerCase();

/// The distinct team labels among [section]'s players, as first spelled.
List<String> sectionTeams(Event event, Section section) {
  final seen = <String, String>{};
  for (final id in section.players) {
    final label = event.player(id).team.trim();
    if (label.isNotEmpty) seen.putIfAbsent(teamKey(label), () => label);
  }
  return seen.values.toList();
}

/// Scholastic Regulations 12.3.3: team ties are broken by the totals of
/// the counting players' individual tie-breaks, in this order, then a coin
/// flip.
const teamTiebreakMethods = [
  TiebreakMethod.modifiedMedian,
  TiebreakMethod.solkoff,
  TiebreakMethod.sonnebornBerger,
  TiebreakMethod.cumulative,
];

List<String> get teamTiebreakLabels => [
  for (final m in teamTiebreakMethods) m.label,
  TiebreakMethod.coinFlip.label,
];

/// One player as their team sees them.
class TeamMember {
  const TeamMember(this.standing, this.points, this.counts, this.tiebreaks);
  final Standing standing;
  Player get player => standing.player;

  /// What the player adds to the team: half-points for top-N scoring,
  /// whole Rollins points for 31A1.
  final int points;

  /// Among the top N whose points make the team score.
  final bool counts;

  /// The player's own [teamTiebreakMethods] values.
  final List<TiebreakValue> tiebreaks;
}

class TeamStanding {
  const TeamStanding({
    required this.team,
    required this.members,
    required this.score,
    required this.tiebreaks,
    required this.eligible,
    required this.method,
    this.rank = 0,
  });

  /// The team label as first spelled in the section.
  final String team;

  /// Every member in individual standings order; the counting ones first.
  final List<TeamMember> members;

  /// Half-points (top N) or Rollins points.
  final int score;

  /// [teamTiebreakMethods] totals over the counting players, then the
  /// recorded coin flip (34E13).
  final List<TiebreakValue> tiebreaks;

  /// At least the announced minimum of players (10.2.2).
  final bool eligible;
  final TeamScoring method;

  /// 1-based place among eligible teams, shared only when every tie-break
  /// is equal; 0 for an ineligible team.
  final int rank;

  List<TeamMember> get counting => [
    for (final m in members)
      if (m.counts) m,
  ];

  String get scoreText => formatTeamPoints(method, score);

  TeamStanding withRank(int rank) => TeamStanding(
    team: team,
    members: members,
    score: score,
    tiebreaks: tiebreaks,
    eligible: eligible,
    method: method,
    rank: rank,
  );

  Json toJson() => {
    'team': team,
    'rank': rank,
    'eligible': eligible,
    'score': score,
    'scoreText': scoreText,
    'unit': method == TeamScoring.topN ? 'halves' : 'whole',
    'counting': [
      for (final m in counting)
        {
          'playerId': m.player.id,
          'name': m.player.name,
          'points': m.points,
          'text': formatTeamPoints(method, m.points),
        },
    ],
    'others': [
      for (final m in members)
        if (!m.counts) {'playerId': m.player.id, 'name': m.player.name},
    ],
    'tiebreaks': [
      for (final t in tiebreaks)
        {'code': t.code, 'value': t.value, 'number': t.number, 'text': t.text},
    ],
  };
}

/// A member's or team's points as printed: `3½` for scores, `87` for
/// Rollins points.
String formatTeamPoints(TeamScoring method, int points) =>
    method == TeamScoring.topN
    ? TiebreakMethod.solkoff.format(points)
    : '$points';

/// Team standings for [section] under its team awards, eligible teams in
/// place order, then the ineligible ones. Empty when the section has no
/// team awards. Withdrawn players keep the scores they earned; house
/// players and entries replaced by a re-entry (32C5) score for no team;
/// players without a team label are on no team.
List<TeamStanding> teamStandings(
  Event event,
  Section section, {
  TeamAwards? awards,
}) {
  final settings = awards ?? TeamAwards.of(section);
  if (settings == null) return const [];
  final rows = standings(event, section);
  final field = rows.length;
  final values = {
    for (final r in standings(event, section, tiebreaks: teamTiebreakMethods))
      r.player.id: r.tiebreaks,
  };
  final superseded = {
    for (final p in event.players)
      if (p.reentryOf.isNotEmpty) p.reentryOf,
  };
  final byTeam = <String, List<Standing>>{};
  final labels = <String, String>{};
  for (final row in rows) {
    final p = row.player;
    final key = teamKey(p.team);
    if (key.isEmpty || p.house || superseded.contains(p.id)) continue;
    labels.putIfAbsent(key, () => p.team.trim());
    (byTeam[key] ??= []).add(row);
  }
  final teams = <TeamStanding>[];
  for (final MapEntry(:key, value: players) in byTeam.entries) {
    // Rows arrive in standings order, so the first N are the counting
    // players and their tie-breaks are the ones that total (12.3.3).
    final members = [
      for (final (i, row) in players.indexed)
        TeamMember(
          row,
          switch (settings.method) {
            TeamScoring.topN => row.points,
            // 31A1: overall place counts down from the field size; tied
            // players share a place and so share the points.
            TeamScoring.rollins => field - row.rank,
          },
          i < settings.counting,
          values[row.player.id] ?? const [],
        ),
    ];
    final counting = members.where((m) => m.counts).toList();
    teams.add(
      TeamStanding(
        team: labels[key]!,
        members: members,
        score: counting.fold(0, (sum, m) => sum + m.points),
        tiebreaks: [
          for (final (i, method) in teamTiebreakMethods.indexed)
            TiebreakValue(
              method,
              counting.fold(
                0,
                (sum, m) =>
                    sum + (i < m.tiebreaks.length ? m.tiebreaks[i].value : 0),
              ),
            ),
          TiebreakValue(TiebreakMethod.coinFlip, _coin(event, key)),
        ],
        eligible: members.length >= settings.minPlayers,
        method: settings.method,
      ),
    );
  }
  return rankTeams(teams);
}

/// Places [teams]: eligible teams by team score, then the 12.3.3
/// tie-breaks in order (the coin flip last), sharing a place only when
/// every value is equal; ineligible teams follow with place 0.
List<TeamStanding> rankTeams(List<TeamStanding> teams) {
  int compare(TeamStanding a, TeamStanding b) {
    if (a.eligible != b.eligible) return a.eligible ? -1 : 1;
    final s = b.score.compareTo(a.score);
    if (s != 0) return s;
    for (var i = 0; i < a.tiebreaks.length && i < b.tiebreaks.length; i++) {
      final t = b.tiebreaks[i].value.compareTo(a.tiebreaks[i].value);
      if (t != 0) return t;
    }
    return a.team.compareTo(b.team);
  }

  final sorted = [...teams]..sort(compare);
  final ranked = <TeamStanding>[];
  var rank = 0;
  for (final (i, t) in sorted.indexed) {
    if (!t.eligible) {
      ranked.add(t.withRank(0));
      continue;
    }
    final previous = i == 0 ? null : sorted[i - 1];
    final shared =
        previous != null &&
        previous.score == t.score &&
        _sameValues(previous.tiebreaks, t.tiebreaks);
    if (!shared) rank = i + 1;
    ranked.add(t.withRank(rank));
  }
  return ranked;
}

bool _sameValues(List<TiebreakValue> a, List<TiebreakValue> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].value != b[i].value) return false;
  }
  return true;
}

/// 34E13 / 12.3.3: a recorded coin flip, fixed by the event ID and the
/// team so it can be reproduced (FNV-1a, as for players).
int _coin(Event event, String key) {
  var hash = 0x811c9dc5;
  for (final unit in '${event.id}/team:$key'.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash % 1000000;
}

/// Whether the team awards group belongs in [section]'s settings: a Swiss
/// or round robin whose players carry at least two team labels, or one
/// that already has team awards (so they can be turned off).
bool offersTeamAwards(Event event, Section section) =>
    (section.format == Format.swiss || section.format == Format.roundRobin) &&
    (sectionTeams(event, section).length >= 2 ||
        section.prizes['teams'] != null);

/// One team prize as awarded.
class TeamPrizeLine {
  TeamPrizeLine(
    this.prize,
    this.paidCents,
    Map<String, int> cash,
    List<String> pooledWith,
    this.trophyTeam,
    this.note,
  ) : cash = Map.unmodifiable(cash),
      pooledWith = List.unmodifiable(pooledWith);
  final Prize prize;

  /// After any based-on reduction (32C4), as for individual prizes.
  final int paidCents;

  /// Team label → cents; each sharer's full share when tied teams pool.
  final Map<String, int> cash;
  final List<String> pooledWith;
  final String? trophyTeam;
  final String note;

  Json toJson() => {
    'id': prize.id,
    'label': prize.title,
    'announcedCents': prize.cents,
    'paidCents': paidCents,
    'cash': cash,
    if (pooledWith.isNotEmpty) 'pooledWith': pooledWith,
    if (trophyTeam != null) 'trophy': trophyTeam,
    if (note.isNotEmpty) 'note': note,
  };
}

class TeamPrizeAllocation {
  TeamPrizeAllocation({
    required List<TeamPrizeLine> lines,
    required List<TeamStanding> standings,
    required List<String> explanations,
    Map<String, int> teamCents = const {},
  }) : lines = List.unmodifiable(lines),
       standings = List.unmodifiable(standings),
       explanations = List.unmodifiable(explanations),
       teamCents = Map.unmodifiable(teamCents);
  final List<TeamPrizeLine> lines;
  final List<TeamStanding> standings;
  final List<String> explanations;

  /// Team label → the cash it takes home, in place order.
  final Map<String, int> teamCents;

  bool get isEmpty => lines.isEmpty;
  int get paidCents => teamCents.values.fold(0, (sum, c) => sum + c);

  Json toJson() => {
    'prizes': [for (final l in lines) l.toJson()],
    'teamCents': teamCents,
    'paidCents': paidCents,
    'explanations': explanations,
  };
}

/// Team prizes (`kind: 'team'`) of [section], placed from [teamStandings].
/// Trophies follow the team places, ties broken by 12.3.3's tie-breaks;
/// cash for teams tied on team score pools and splits equally, like tied
/// players' cash (32B2, 34C: tie-breaks never divide money). Amounts are
/// reduced by the same based-on proportion as the individual prizes.
TeamPrizeAllocation allocateTeamPrizes(Event event, Section section) {
  final prizes = [
    for (final p in PrizeTable.fromJson(section.prizes).list)
      if (p.kind == PrizeKind.team) p,
  ]..sort((a, b) => a.place.compareTo(b.place));
  if (prizes.isEmpty) {
    return TeamPrizeAllocation(
      lines: const [],
      standings: const [],
      explanations: const [],
    );
  }
  final awards = TeamAwards.of(section);
  if (awards == null) {
    return TeamPrizeAllocation(
      lines: [
        for (final p in prizes)
          TeamPrizeLine(p, p.cents, {}, [], null, 'Team awards are off'),
      ],
      standings: const [],
      explanations: const [
        'Team prizes are announced but team awards are off for this section, so none is awarded.',
      ],
    );
  }
  final percent = allocatePrizes(event, section).payoutPercent;
  final paid = {
    for (final p in prizes)
      p.id: p.guaranteed ? p.cents : (p.cents * percent / 100).round(),
  };
  final table = teamStandings(event, section, awards: awards);
  final teams = table.where((t) => t.eligible).toList();
  final notes = <String>[
    for (final t in table)
      if (!t.eligible)
        '${t.team} has ${t.members.length} ${t.members.length == 1 ? 'player' : 'players'} '
            'and needs ${awards.minPlayers} for a team prize (10.2.2).',
  ];
  final cash = {for (final p in prizes) p.id: <String, int>{}};
  final teamCents = <String, int>{};
  final pooled = {for (final p in prizes) p.id: <String>[]};

  // Cash: teams equal on team score share the places they cover.
  var i = 0;
  while (i < teams.length) {
    var j = i;
    while (j < teams.length && teams[j].score == teams[i].score) {
      j++;
    }
    final group = teams.sublist(i, j);
    final pool = [
      for (final p in prizes)
        if (p.cents > 0 && p.place > i && p.place <= j) p,
    ];
    final total = pool.fold(0, (sum, p) => sum + paid[p.id]!);
    if (pool.isNotEmpty) {
      final each = total ~/ group.length;
      var extra = total - each * group.length;
      final shares = {
        for (final t in group) t.team: each + (extra-- > 0 ? 1 : 0),
      };
      for (final s in shares.entries) {
        if (s.value > 0) teamCents[s.key] = s.value;
      }
      for (final p in pool) {
        cash[p.id]!.addAll(shares);
        pooled[p.id]!.addAll([
          for (final o in pool)
            if (o != p) o.id,
        ]);
      }
      if (group.length == 1 && pool.length == 1) {
        notes.add(
          '${group.single.team} (${group.single.scoreText}) wins ${pool.single.title}: ${dollars(total)}.',
        );
      } else {
        notes.add(
          '${group.length} teams tied at ${group.first.scoreText} '
          '(${group.map((t) => t.team).join(', ')}) for '
          '${pool.map((p) => p.title).join(' + ')} = ${dollars(total)}, '
          '${shares.values.toSet().length == 1 ? '${dollars(each)} each' : shares.entries.map((e) => '${e.key} ${dollars(e.value)}').join(', ')}.',
        );
      }
    }
    i = j;
  }

  // Trophies: one per team, in place order (12.3.3 breaks the ties).
  final trophy = <String, String>{};
  var next = 0;
  for (final p in prizes.where((p) => p.trophy)) {
    if (next >= teams.length) break;
    final t = teams[next++];
    trophy[p.id] = t.team;
    final tied = teams.any((o) => o != t && o.score == t.score);
    notes.add(
      '${t.team} takes the ${p.title} trophy'
      '${tied ? ' on team tie-breaks (12.3.3)' : ''}.',
    );
  }

  final lines = [
    for (final p in prizes)
      TeamPrizeLine(
        p,
        paid[p.id]!,
        cash[p.id]!,
        pooled[p.id]!,
        trophy[p.id],
        p.cents == 0 && !p.trophy
            ? 'Neither cash nor a trophy'
            : cash[p.id]!.isEmpty && trophy[p.id] == null
            ? 'No eligible team'
            : '',
      ),
  ];
  return TeamPrizeAllocation(
    lines: lines,
    standings: table,
    explanations: notes,
    teamCents: teamCents,
  );
}
