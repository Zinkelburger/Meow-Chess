import 'knockout.dart';
import 'model.dart';
import 'standings.dart';

/// Rules 32–33: the announced prize table of a section and the allocation
/// of its prizes from the prize standings.
///
/// `Section.prizes` schema (every key optional; integers in cents):
/// ```
/// {
///   'basedOn': int,            // announced based-on entries; 0 = guaranteed
///   'fundCents': int,          // announced total fund, informational
///   'withdrawnEligible': bool, // 32C1: withdrawn players stay eligible
///   'unratedCapCents': int,    // 33F / 32C6: most an unrated may win; 0 = none
///   'list': [
///     {'id': String, 'label': String,
///      'kind': 'place'|'class'|'under'|'unrated'|'junior'|'senior'
///              |'points'|'computer'|'team',
///      'place': int,           // 1-based rank within the prize group;
///                              // for 'team', the place among the teams
///      'min': int, 'max': int, // class: inclusive range; under: max exclusive
///      'points': int,          // halves, for kind 'points' (33E)
///      'cents': int,           // cash; 0 for trophy-only
///      'trophy': bool,
///      'guaranteed': bool,     // optional, 32E: never reduced by based-on
///      'eligible': [String]}   // optional player IDs; the only way to name
///                              // juniors and seniors (no birth dates are kept)
///   ],
///   'teams': {                 // optional: scholastic team awards; absent = off
///     'counting': int,         // N, the announced number of scores that
///                              // count (Scholastic Regulations 10.2.1)
///     'method': 'topN'|'rollins', // top N individual scores, or 31A1
///                              // Rollins points (field size − place)
///     'minPlayers': int}       // fewest players for a prize; 2 (10.2.2)
/// }
/// ```
///
/// Team prizes (`kind: 'team'`) go to teams, not players: [allocatePrizes]
/// leaves them out and `allocateTeamPrizes` (team_standings.dart) awards
/// them from the team standings.
///
/// Prizes follow the prize standings, except where a format places its
/// players another way: a knockout by its bracket (both losers of a round
/// are level, and pool the places they cover), a ladder by its positions
/// (never tied), and a bughouse section by partnership, each partnership
/// winning one prize as a unit.
enum PrizeKind {
  place('place', 'Place'),
  classRange('class', 'Class'),
  under('under', 'Under'),
  unrated('unrated', 'Unrated'),
  junior('junior', 'Junior'),
  senior('senior', 'Senior'),
  points('points', 'Points'),
  computer('computer', 'Computer'),

  /// Scholastic Regulations 10.2: a place among the teams.
  team('team', 'Team');

  const PrizeKind(this.code, this.label);
  final String code, label;

  static PrizeKind parse(Object? code) =>
      values.where((k) => k.code == code).firstOrNull ??
      (throw TournamentException(
        'Unknown prize kind "$code". Use ${values.map((k) => k.code).join(', ')}.',
      ));

  /// 33C: a rating-restricted prize.
  bool get ratingBased => this == classRange || this == under;
}

class Prize {
  Prize({
    required this.id,
    this.label = '',
    this.kind = PrizeKind.place,
    this.place = 1,
    this.min = 0,
    this.max = 0,
    this.points = 0,
    this.cents = 0,
    bool trophy = false,
    this.item = '',
    this.guaranteed = false,
    List<String> eligible = const [],
  }) : trophy = trophy || item.trim().isNotEmpty,
       eligible = List.unmodifiable(eligible);
  final String id, label;
  final PrizeKind kind;
  final int place, min, max, points, cents;

  /// 32F: an award that cannot be divided (a trophy, a medal), which goes
  /// to one player by tie-breaks. True whenever [item] names one.
  final bool trophy;

  /// What the indivisible award is, as announced ("Trophy", "Medal");
  /// empty for a plain trophy or none. See [award].
  final String item;
  final bool guaranteed;
  final List<String> eligible;

  /// The indivisible award in words, or empty when the prize has none.
  String get award => item.trim().isNotEmpty
      ? item.trim()
      : trophy
      ? 'Trophy'
      : '';

  /// The prize with its award named once: "1st trophy", and "Champion
  /// trophy" for a prize already labelled that way.
  String get awardTitle {
    final word = award.toLowerCase();
    return word.isEmpty ||
            RegExp(
              '\\b${RegExp.escape(word)}\\b',
              caseSensitive: false,
            ).hasMatch(title)
        ? title
        : '$title $word';
  }

  factory Prize.fromJson(Json j) {
    int integer(String key) {
      final v = j[key];
      if (v == null) return 0;
      if (v is! int || v < 0) {
        throw TournamentException(
          'Prize "${j['label'] ?? j['id']}": $key must be a whole number of 0 or more.',
        );
      }
      return v;
    }

    final id = '${j['id'] ?? ''}'.trim();
    if (id.isEmpty) throw const TournamentException('Every prize needs an id.');
    final kind = PrizeKind.parse(j['kind'] ?? 'place');
    final min = integer('min'), max = integer('max');
    if (kind == PrizeKind.classRange && min > 0 && max > 0 && min > max) {
      throw TournamentException(
        'Prize "${j['label'] ?? id}": the class range $min–$max is reversed.',
      );
    }
    final place = j['place'] == null ? 1 : integer('place');
    if (place < 1) {
      throw TournamentException(
        'Prize "${j['label'] ?? id}": place starts at 1.',
      );
    }
    final eligible = j['eligible'];
    if (eligible != null && eligible is! List) {
      throw TournamentException(
        'Prize "${j['label'] ?? id}": eligible must be a list of player IDs.',
      );
    }
    return Prize(
      id: id,
      label: '${j['label'] ?? ''}'.trim(),
      kind: kind,
      place: place,
      min: min,
      max: max,
      points: integer('points'),
      cents: integer('cents'),
      trophy: j['trophy'] == true,
      item: '${j['item'] ?? ''}'.trim(),
      guaranteed: j['guaranteed'] == true,
      eligible: [for (final e in (eligible as List?) ?? const []) '$e'],
    );
  }

  Json toJson() => {
    'id': id,
    'label': label,
    'kind': kind.code,
    'place': place,
    'min': min,
    'max': max,
    'points': points,
    'cents': cents,
    'trophy': trophy,
    if (item.isNotEmpty) 'item': item,
    if (guaranteed) 'guaranteed': true,
    if (eligible.isNotEmpty) 'eligible': eligible,
  };

  Prize copy({
    String? label,
    PrizeKind? kind,
    int? place,
    int? min,
    int? max,
    int? points,
    int? cents,
    bool? trophy,
    String? item,
    bool? guaranteed,
    List<String>? eligible,
  }) => Prize(
    id: id,
    label: label ?? this.label,
    kind: kind ?? this.kind,
    place: place ?? this.place,
    min: min ?? this.min,
    max: max ?? this.max,
    points: points ?? this.points,
    cents: cents ?? this.cents,
    // Naming no item keeps a plain trophy; turning the trophy off also
    // drops the item that implied it.
    trophy: trophy ?? (item != null ? false : this.trophy),
    item: trophy == false ? '' : item ?? this.item,
    guaranteed: guaranteed ?? this.guaranteed,
    eligible: eligible ?? this.eligible,
  );

  /// Prizes of one group rank against each other by [place]; 32B2 ties
  /// "in the same class" and 32C6 "within the prize group" refer to this.
  String get group => switch (kind) {
    PrizeKind.place => 'place',
    PrizeKind.classRange => 'class:$min-$max',
    PrizeKind.under => 'under:$max',
    PrizeKind.points => 'points:$points',
    _ => kind.code,
  };

  /// The label as announced, or a description built from the terms.
  String get title => label.isNotEmpty ? label : describe();

  String describe() {
    final nth = '${_ordinal(place)} ';
    return switch (kind) {
      PrizeKind.place => _ordinal(place),
      PrizeKind.classRange =>
        '$nth${min > 0 && max > 0
            ? '$min–$max'
            : min > 0
            ? '$min and up'
            : 'up to $max'}',
      PrizeKind.under => '${nth}Under $max',
      PrizeKind.unrated => '${nth}Unrated',
      PrizeKind.junior => '${nth}Junior',
      PrizeKind.senior => '${nth}Senior',
      PrizeKind.computer => '${nth}Computer',
      PrizeKind.points => '${scoreText(points)} points',
      PrizeKind.team => '${_ordinal(place)} team',
    };
  }
}

String _ordinal(int n) => n % 100 >= 11 && n % 100 <= 13
    ? '${n}th'
    : switch (n % 10) {
        1 => '${n}st',
        2 => '${n}nd',
        3 => '${n}rd',
        _ => '${n}th',
      };

/// Cents as printed: `$200`, `$12.50`, `$1,250`.
String dollars(int cents) {
  final sign = cents < 0 ? '-' : '';
  final whole = cents.abs() ~/ 100, part = cents.abs() % 100;
  final digits = whole.toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return '$sign\$$grouped${part == 0 ? '' : '.${part.toString().padLeft(2, '0')}'}';
}

class PrizeTable {
  PrizeTable({
    this.basedOn = 0,
    this.fundCents = 0,
    this.withdrawnEligible = false,
    this.unratedCapCents = 0,
    List<Prize> list = const [],
    this.teams,
  }) : list = List.unmodifiable(list);
  final int basedOn, fundCents, unratedCapCents;
  final bool withdrawnEligible;
  final List<Prize> list;

  /// The `teams` settings, kept as stored (see `TeamAwards`); null is off.
  final Json? teams;

  bool get isEmpty => list.isEmpty;

  /// The table without its team prizes, which [allocatePrizes] leaves to
  /// `allocateTeamPrizes`.
  PrizeTable get individual => copy(
    list: [
      for (final p in list)
        if (p.kind != PrizeKind.team) p,
    ],
  );

  /// The announced fund: the stated total, else the sum of the cash prizes.
  int get announcedCents =>
      fundCents > 0 ? fundCents : list.fold(0, (sum, p) => sum + p.cents);

  factory PrizeTable.fromJson(Json j) {
    int integer(String key) {
      final v = j[key];
      if (v == null) return 0;
      if (v is! int || v < 0) {
        throw TournamentException(
          'Prizes: $key must be a whole number of 0 or more.',
        );
      }
      return v;
    }

    final raw = j['list'];
    if (raw != null && raw is! List) {
      throw const TournamentException('Prizes: list must be a list of prizes.');
    }
    final list = [
      for (final entry in (raw as List?) ?? const [])
        if (entry is Map)
          Prize.fromJson(Map<String, dynamic>.from(entry))
        else
          throw const TournamentException('Prizes: each prize is an object.'),
    ];
    final ids = <String>{};
    for (final p in list) {
      if (!ids.add(p.id)) {
        throw TournamentException('Prize id "${p.id}" is used twice.');
      }
    }
    return PrizeTable(
      basedOn: integer('basedOn'),
      fundCents: integer('fundCents'),
      withdrawnEligible: j['withdrawnEligible'] == true,
      unratedCapCents: integer('unratedCapCents'),
      list: list,
      teams: j['teams'] is Map
          ? Map<String, dynamic>.from(j['teams'] as Map)
          : null,
    );
  }

  Json toJson() => {
    'basedOn': basedOn,
    'fundCents': fundCents,
    'withdrawnEligible': withdrawnEligible,
    if (unratedCapCents > 0) 'unratedCapCents': unratedCapCents,
    'list': [for (final p in list) p.toJson()],
    if (teams != null) 'teams': teams,
  };

  PrizeTable copy({
    int? basedOn,
    int? fundCents,
    bool? withdrawnEligible,
    int? unratedCapCents,
    List<Prize>? list,
  }) => PrizeTable(
    basedOn: basedOn ?? this.basedOn,
    fundCents: fundCents ?? this.fundCents,
    withdrawnEligible: withdrawnEligible ?? this.withdrawnEligible,
    unratedCapCents: unratedCapCents ?? this.unratedCapCents,
    list: list ?? this.list,
    teams: teams,
  );
}

/// One prize as paid: its reduced amount and who received cash or the trophy.
class PrizeLine {
  PrizeLine(
    this.prize,
    this.paidCents,
    Map<String, int> cash,
    List<String> pooledWith,
    this.trophyWinner,
    this.note, {
    this.trophyNote = '',
    Map<String, String> names = const {},
  }) : cash = Map.unmodifiable(cash),
       names = Map.unmodifiable(names),
       pooledWith = List.unmodifiable(pooledWith);
  final Prize prize;

  /// The amount after any based-on reduction (32C4).
  final int paidCents;

  /// Player ID → cents received: the whole amount for a clear winner; for
  /// a tie, each sharer's full share of the pool this prize went into. A
  /// bughouse partnership is one entry under its first-listed partner.
  final Map<String, int> cash;

  /// How to print a winner who is not one player: the ID a partnership
  /// appears under in [cash] or as [trophyWinner] → "Chen / Patel".
  final Map<String, String> names;

  /// IDs of the other prizes pooled with this one (32B2); empty otherwise.
  final List<String> pooledWith;
  final String? trophyWinner;
  final String note;

  /// Rule 34A: how tie-breaks gave the award to [trophyWinner] over a
  /// player tied with them on points, or that they did not decide it;
  /// empty when no eligible player was tied.
  final String trophyNote;

  Json toJson() => {
    'id': prize.id,
    'label': prize.title,
    'announcedCents': prize.cents,
    'paidCents': paidCents,
    'cash': cash,
    if (pooledWith.isNotEmpty) 'pooledWith': pooledWith,
    if (trophyWinner != null) 'trophy': trophyWinner,
    if (names.isNotEmpty) 'partnerships': names,
    if (trophyNote.isNotEmpty) 'trophyNote': trophyNote,
    if (note.isNotEmpty) 'note': note,
  };
}

/// What one player, or one bughouse partnership, takes home.
class PlayerAward {
  PlayerAward(
    this.player,
    this.points,
    this.cents,
    List<Prize> trophies, {
    List<Player> partners = const [],
    this.placing = '',
  }) : trophies = List.unmodifiable(trophies),
       partners = List.unmodifiable(partners);
  final Player player;

  /// The rest of a bughouse partnership, which wins as one; empty otherwise.
  final List<Player> partners;
  final int points, cents;
  final List<Prize> trophies;

  /// The finish that earned it when that is not the score: a knockout's
  /// bracket placing ("Runner-up") or a ladder position. Empty otherwise.
  final String placing;

  /// The winner as printed: the player, or "Chen / Patel".
  String get name => [player, ...partners].map((p) => p.name).join(' / ');

  /// The finish as printed beside the name: the placing, else the score.
  String get standing => placing.isNotEmpty ? placing : scoreText(points);

  Json toJson() => {
    'playerId': player.id,
    if (partners.isNotEmpty) 'partnerIds': [for (final p in partners) p.id],
    'name': name,
    'points': points,
    if (placing.isNotEmpty) 'placing': placing,
    'cents': cents,
    'trophies': [for (final t in trophies) t.title],
  };
}

class PrizeAllocation {
  PrizeAllocation({
    required this.table,
    required List<PrizeLine> lines,
    required List<PlayerAward> awards,
    required List<String> explanations,
    required this.entries,
    required this.payoutPercent,
  }) : lines = List.unmodifiable(lines),
       awards = List.unmodifiable(awards),
       explanations = List.unmodifiable(explanations);
  final PrizeTable table;
  final List<PrizeLine> lines;

  /// In standings order; only players who receive something.
  final List<PlayerAward> awards;
  final List<String> explanations;
  final int entries;

  /// 100 when fully paid; the 32C4 proportion otherwise.
  final int payoutPercent;

  int get paidCents => awards.fold(0, (sum, a) => sum + a.cents);

  Json toJson() => {
    'entries': entries,
    'payoutPercent': payoutPercent,
    'paidCents': paidCents,
    'prizes': [for (final l in lines) l.toJson()],
    'awards': [for (final a in awards) a.toJson()],
    'explanations': explanations,
  };
}

/// Rules 32C4 and 32E: what each prize of a section pays when fewer players
/// entered than its prizes were based on.
class PrizePayout {
  PrizePayout({
    required this.entries,
    required this.basedOn,
    required this.halfMinimum,
  });

  /// The payout terms of [section]: its entries (house players excluded)
  /// against its based-on number, and whether the event's announced funds
  /// exceed $500 (32C4b).
  factory PrizePayout.of(Event event, Section section) {
    final table = PrizeTable.fromJson(section.prizes);
    final fund = event.sections.fold(
      0,
      (sum, s) => sum + PrizeTable.fromJson(s.prizes).announcedCents,
    );
    return PrizePayout(
      entries: section.players
          .where((id) => !event.player(id).house)
          .toSet()
          .length,
      basedOn: table.basedOn,
      halfMinimum: fund > 50000,
    );
  }

  final int entries, basedOn;

  /// 32C4b: no prize pays less than half.
  final bool halfMinimum;

  bool get reduced => basedOn > 0 && entries < basedOn;

  /// The proportion is below the 50% minimum, so every prize pays half.
  bool get atMinimum => reduced && halfMinimum && entries * 2 < basedOn;

  /// What [prize] pays: its exact share of the turnout, rounded up to the
  /// cent so it is never below the proportion (32C4a), at least half when
  /// the minimum applies, and in full when guaranteed (32E).
  int cents(Prize prize) {
    if (!reduced || prize.guaranteed) return prize.cents;
    final share = (prize.cents * entries + basedOn - 1) ~/ basedOn;
    final half = (prize.cents + 1) ~/ 2;
    return halfMinimum && half > share ? half : share;
  }

  /// The proportion as a whole percentage, rounded down; 100 only when
  /// every prize pays in full.
  int get percent => !reduced
      ? 100
      : atMinimum
      ? 50
      : entries * 100 ~/ basedOn;

  /// The proportion in words: `70%`, or `47/60 of its amount (78.33%)`
  /// when it is not a whole percentage.
  String get proportion {
    if (atMinimum || entries * 100 % basedOn == 0) return '$percent%';
    final hundredths = entries * 10000 ~/ basedOn;
    return '$entries/$basedOn of its amount '
        '(${hundredths ~/ 100}.${(hundredths % 100).toString().padLeft(2, '0')}%, '
        'rounded up to the cent)';
  }
}

/// One competitor for the prizes: a player, or a bughouse partnership,
/// which wins and shares as one.
class _Entrant {
  _Entrant({
    required this.players,
    required this.points,
    required this.level,
    this.placing = '',
    this.tiebreaks = const [],
  });
  final List<Player> players;
  final int points;

  /// Entrants on the same level are tied; a higher level finished ahead.
  /// The score for most formats, the bracket placing for a knockout, the
  /// place on the ladder for a ladder.
  final int level;

  /// The finish in words when it is not the score ("Semifinalist").
  final String placing;
  final List<TiebreakValue> tiebreaks;

  String get id => players.first.id;
  String get name => players.map((p) => p.name).join(' / ');
  bool get house => players.every((p) => p.house);
  bool get withdrawn => players.any((p) => p.withdrawn);
  bool get computer => players.any((p) => p.computer);

  /// The rating prize eligibility uses (28F): a partnership's is the
  /// average of its rated partners, zero when neither is rated.
  int get rating {
    final rated = [
      for (final p in players)
        if (p.effectivePrizeRating > 0) p.effectivePrizeRating,
    ];
    return rated.isEmpty
        ? 0
        : rated.fold(0, (sum, r) => sum + r) ~/ rated.length;
  }

  /// The finish as printed beside the name: the score, or the placing.
  String get standing => placing.isNotEmpty ? placing : scoreText(points);

  /// The IDs of the prizes this entrant may win.
  Set<String> can = const {};
  int cents = 0;
  final trophies = <Prize>[];
}

/// A cash prize while it is being allocated: pool awards may leave a
/// remainder behind (32C6), which stays in the group as its own prize.
class _Cash {
  _Cash(this.prize, this.cents, {this.remainderOf});
  final Prize prize;
  final int cents;
  final Prize? remainderOf;
  String get title =>
      remainderOf == null ? prize.title : 'remainder of ${prize.title}';
}

/// The tied players who can win exactly the same prizes. They are
/// interchangeable for pooling, so a tie of any size is a handful of these.
class _Alike {
  _Alike(this.prizes) : _set = Set.identity()..addAll(prizes);
  final List<_Cash> prizes;
  final Set<_Cash> _set;
  final members = <_Entrant>[];
  bool wins(_Cash c) => _set.contains(c);

  /// The largest of [among] a member could win with no tie (32B3).
  int best(Iterable<_Cash> among) =>
      among.where(wins).fold(0, (m, c) => c.cents > m ? c.cents : m);
}

/// The most sub-groups of a tie examined for a prize the rest cannot win
/// (32B3). Ties with up to twelve kinds of eligibility are examined in full.
const _maxCarveOuts = 4096;

/// The competitors of [section] from the top, before eligibility: by prize
/// standings, except that a knockout places by its bracket, a ladder by its
/// positions, and a bughouse partnership competes as one.
List<_Entrant> _competitors(Event event, Section section) {
  // Trophies go by tie-breaks even when equal scores share a place (34A).
  final rows = standings(event, section, forPrizes: true, byTiebreaks: true);
  final byId = {for (final row in rows) row.player.id: row};
  switch (section.format) {
    case Format.knockout:
      // Players level in the bracket (both semifinal losers, or everyone
      // still in) are tied; the bracket has no tie-break between them.
      return [
        for (final (:playerId, :rank, :placing) in knockoutRanking(
          event,
          section,
        ))
          _Entrant(
            players: [event.player(playerId)],
            points: byId[playerId]?.points ?? 0,
            level: -rank,
            placing: placing,
          ),
      ];
    case Format.ladder:
      return [
        for (final (i, id) in section.players.indexed)
          _Entrant(
            players: [event.player(id)],
            points: byId[id]?.points ?? 0,
            level: -i,
            placing: '#${i + 1} on the ladder',
          ),
      ];
    case Format.bughouse:
      // Both partners carry the partnership's score; the first of them in
      // the standings stands for the pair, listed in its announced order.
      final placed = <String>{};
      final pairs = <_Entrant>[];
      for (final row in rows) {
        if (placed.contains(row.player.id)) continue;
        final pair =
            section.partners
                .where((pair) => pair.contains(row.player.id))
                .firstOrNull ??
            [row.player.id];
        placed.addAll(pair);
        pairs.add(
          _Entrant(
            players: [for (final id in pair) event.player(id)],
            points: row.points,
            level: row.points,
            tiebreaks: row.tiebreaks,
          ),
        );
      }
      return pairs;
    default:
      return [
        for (final row in rows)
          _Entrant(
            players: [row.player],
            points: row.points,
            level: row.points,
            tiebreaks: row.tiebreaks,
          ),
      ];
  }
}

/// Rules 32B–32G, 33C–33F: who wins what in [section].
///
/// Cash is allocated level by level from the top. Within a tie, players who
/// can win the same prizes are grouped, the pool is the most valuable set of
/// prizes the tie can hold at one each (a matching of prizes to groups), and
/// the work grows with the number of prizes and groups, not with the number
/// of ways to hand prizes out.
PrizeAllocation allocatePrizes(Event event, Section section) {
  final table = PrizeTable.fromJson(section.prizes).individual;
  final notes = <String>[];
  final payout = PrizePayout.of(event, section);
  final entries = payout.entries;

  // 32C4 / 32E: proportional payout, at least 50% when the whole event
  // announces more than $500; guaranteed prizes are never reduced.
  if (payout.reduced) {
    notes.add(
      'Prizes were based on ${table.basedOn} entries and $entries entered: '
      'each prize pays ${payout.proportion}'
      '${payout.atMinimum ? ' (the 50% minimum, because the announced fund exceeds \$500)' : ''}'
      '${table.list.any((p) => p.guaranteed && p.cents > 0) ? '; guaranteed prizes pay in full' : ''}.',
    );
  }
  final paid = {for (final p in table.list) p.id: payout.cents(p)};

  if (table.isEmpty) {
    return PrizeAllocation(
      table: table,
      lines: const [],
      awards: const [],
      explanations: const ['No prizes are announced for this section.'],
      entries: entries,
      payoutPercent: payout.percent,
    );
  }

  final teams = section.format == Format.bughouse;
  final several = teams ? 'partnerships' : 'players';

  // 32C5: an entry replaced by a re-entry competes only for the record.
  final superseded = {
    for (final p in event.players)
      if (p.reentryOf.isNotEmpty) p.reentryOf,
  };
  final entrants = <_Entrant>[];
  for (final e in _competitors(event, section)) {
    if (e.house) continue;
    if (e.players.any((p) => superseded.contains(p.id))) {
      notes.add(
        '${e.name} re-entered; the earlier entry wins no prize (32C5).',
      );
      continue;
    }
    if (e.withdrawn && !table.withdrawnEligible) {
      notes.add('${e.name} withdrew and is not eligible for prizes (32C1).');
      continue;
    }
    entrants.add(e);
  }

  bool qualifies(_Entrant e, Prize prize) {
    if (prize.eligible.isNotEmpty &&
        !e.players.any((p) => prize.eligible.contains(p.id))) {
      return false;
    }
    // Rule 36: computers only win prizes designated for computers.
    if (e.computer != (prize.kind == PrizeKind.computer)) return false;
    final rating = e.rating;
    // 33F: unrateds compete for place, points and unrated prizes only.
    if (rating == 0) {
      return const [
        PrizeKind.place,
        PrizeKind.points,
        PrizeKind.unrated,
        PrizeKind.computer,
      ].contains(prize.kind);
    }
    return switch (prize.kind) {
      PrizeKind.unrated => false,
      // 33C: a class prize names both boundaries; Under takes every class below.
      PrizeKind.classRange =>
        (prize.min == 0 || rating >= prize.min) &&
            (prize.max == 0 || rating <= prize.max),
      PrizeKind.under =>
        prize.max > 0 && rating < prize.max && rating >= prize.min,
      _ => true,
    };
  }

  for (final e in entrants) {
    e.can = {
      for (final p in table.list)
        if (qualifies(e, p)) p.id,
    };
  }
  bool eligible(_Entrant e, Prize prize) => e.can.contains(prize.id);

  // 32B4: among equal amounts, place beats class, a higher class beats a
  // lower one, and a rating class beats juniors and seniors.
  int precedence(Prize p) => switch (p.kind) {
    PrizeKind.place => 0,
    PrizeKind.points => 1,
    PrizeKind.classRange || PrizeKind.under => 2,
    PrizeKind.unrated => 3,
    PrizeKind.junior || PrizeKind.senior => 4,
    PrizeKind.computer || PrizeKind.team => 5,
  };
  int comparePrizes(Prize a, Prize b) {
    final k = precedence(a).compareTo(precedence(b));
    if (k != 0) return k;
    if (a.kind.ratingBased && b.kind.ratingBased) {
      int top(Prize p) => p.max == 0
          ? 1 << 30
          : p.kind == PrizeKind.under
          ? p.max - 1
          : p.max;
      final hi = top(b).compareTo(top(a));
      if (hi != 0) return hi;
      final lo = b.min.compareTo(a.min);
      if (lo != 0) return lo;
    }
    final g = a.group.compareTo(b.group);
    if (g != 0) return g;
    return a.place.compareTo(b.place);
  }

  final ordered = [...table.list]..sort(comparePrizes);
  final rank = {for (final (i, p) in ordered.indexed) p.id: i};

  // ---- Cash (32B, 34C): ties pool and split; never tie-breaks.
  final available = <_Cash>[
    for (final p in table.list)
      if (p.cents > 0 && p.kind != PrizeKind.points) _Cash(p, paid[p.id]!),
  ];
  final cashLines = <String, Map<String, int>>{
    for (final p in table.list) p.id: {},
  };
  final pooledWith = <String, List<String>>{
    for (final p in table.list) p.id: [],
  };

  int weight(_Cash c) =>
      c.cents * 1024 + (1023 - (rank[c.prize.id] ?? 1023).clamp(0, 1023));

  /// 32B3 TD TIP: at most one prize per tied player, the largest each can
  /// take, chosen together so the pool is as large as the tie allows.
  ///
  /// The prizes a tie can hold at one per player form a matroid, so taking
  /// them from the most valuable down, keeping each one that still fits,
  /// gives the most valuable pool. A prize fits when some group that can win
  /// it has a member to spare, after moving other prizes between groups.
  List<_Cash> bestPool(List<_Alike> groups, List<_Cash> prizes) {
    final order = [...prizes]..sort((a, b) => weight(b).compareTo(weight(a)));
    final held = [for (final _ in groups) <_Cash>[]];
    bool place(_Cash c, Set<int> tried) {
      for (final (i, g) in groups.indexed) {
        if (!g.wins(c) || !tried.add(i)) continue;
        if (held[i].length < g.members.length) {
          held[i].add(c);
          return true;
        }
        // The group is full: one of its prizes may fit elsewhere.
        for (final other in [...held[i]]) {
          if (place(other, tried)) {
            held[i]
              ..remove(other)
              ..add(c);
            return true;
          }
        }
      }
      return false;
    }

    return [
      for (final c in order)
        if (place(c, {})) c,
    ];
  }

  /// Splits [pool] equally among [tied], with nobody above [cap], the prize
  /// they would win alone (32B3); any excess flows to the others, then back.
  Map<String, int> divide(
    List<_Entrant> tied,
    int pool,
    int Function(_Entrant) cap,
  ) {
    final caps = {for (final e in tied) e.id: cap(e)};
    final out = <String, int>{};
    var remaining = pool;
    var open = tied.map((e) => e.id).toList();
    while (open.isNotEmpty && remaining > 0) {
      final share = remaining ~/ open.length;
      final capped = open.where((id) => caps[id]! <= share).toSet();
      if (capped.isEmpty) {
        var extra = remaining - share * open.length;
        for (final id in open) {
          out[id] = share + (extra-- > 0 ? 1 : 0);
        }
        remaining = 0;
        break;
      }
      for (final id in capped) {
        out[id] = caps[id]!;
        remaining -= caps[id]!;
      }
      open = open.where((id) => !capped.contains(id)).toList();
    }
    for (final e in tied) {
      out.putIfAbsent(e.id, () => 0);
    }
    return out;
  }

  String names(Iterable<_Entrant> es) => es.map((e) => e.name).join(', ');

  final awarded = <_Cash>{};
  final pending = <_Cash>[];

  /// Allocates among [tied] (one level) from [prizes], recursively carving
  /// out players who do better from prizes the rest cannot win.
  void allocateTie(List<_Entrant> tied, List<_Cash> prizes) {
    // Group the tied players by the prizes they can win.
    final alike = <String, _Alike>{};
    final groupOf = <String, _Alike>{};
    for (final e in tied) {
      final mine = [
        for (final c in prizes)
          if (eligible(e, c.prize)) c,
      ];
      if (mine.isEmpty) continue;
      final group = alike[mine.map((c) => c.prize.id).join('|')] ??= _Alike(
        mine,
      );
      group.members.add(e);
      groupOf[e.id] = group;
    }
    final contenders = tied.where((e) => groupOf.containsKey(e.id)).toList();
    if (contenders.isEmpty) return;
    final groups = alike.values.toList();
    final pool = bestPool(groups, prizes);
    final total = pool.fold(0, (sum, c) => sum + c.cents);
    final full = divide(contenders, total, (e) => groupOf[e.id]!.best(prizes));

    // 32B3: a sub-group takes only prizes the others are ineligible for
    // when every one of them does at least as well and someone does better.
    // Such a sub-group is made of whole groups, and it is exactly the
    // groups that can win the prizes it takes, so the candidates are the
    // unions of "who can win this prize" over the prizes.
    if (groups.length > 1) {
      final winners = <String, List<int>>{};
      for (final c in prizes) {
        final who = [
          for (final (i, g) in groups.indexed)
            if (g.wins(c)) i,
        ];
        if (who.isEmpty || who.length == groups.length) continue;
        winners[who.join(',')] = who;
      }
      final candidates = {...winners};
      final queue = [...winners.values];
      for (var at = 0; at < queue.length; at++) {
        if (candidates.length >= _maxCarveOuts) break;
        for (final who in winners.values) {
          final union = {...queue[at], ...who}.toList()..sort();
          if (union.length == groups.length) continue;
          if (candidates.containsKey(union.join(','))) continue;
          candidates[union.join(',')] = union;
          queue.add(union);
          if (candidates.length >= _maxCarveOuts) break;
        }
      }
      // Examined in a fixed order (as binary numbers over the groups), so
      // equally good sub-groups always resolve the same way.
      int byNumber(List<int> a, List<int> b) {
        for (var i = 1; i <= a.length && i <= b.length; i++) {
          final c = a[a.length - i].compareTo(b[b.length - i]);
          if (c != 0) return c;
        }
        return a.length.compareTo(b.length);
      }

      List<_Entrant>? bestGroup;
      List<_Cash>? bestRestricted;
      var bestMin = -1;
      for (final who in candidates.values.toList()..sort(byNumber)) {
        final inside = who.toSet();
        final part = [for (final i in who) groups[i]];
        final g = [for (final a in part) ...a.members];
        final restricted = [
          for (final c in prizes)
            if (!groups.indexed.any(
              (entry) => !inside.contains(entry.$1) && entry.$2.wins(c),
            ))
              c,
        ];
        final sub = bestPool(part, restricted);
        final subTotal = sub.fold(0, (sum, c) => sum + c.cents);
        // Everyone at least level and someone ahead needs more money than
        // the sub-group's shares of the whole pool.
        if (subTotal <= g.fold(0, (sum, e) => sum + full[e.id]!)) continue;
        final split = divide(
          g,
          subTotal,
          (e) => groupOf[e.id]!.best(restricted),
        );
        if (!g.every((e) => split[e.id]! >= full[e.id]!) ||
            !g.any((e) => split[e.id]! > full[e.id]!)) {
          continue;
        }
        final low = g.fold(
          1 << 30,
          (m, e) => split[e.id]! < m ? split[e.id]! : m,
        );
        if (low > bestMin || (low == bestMin && g.length < bestGroup!.length)) {
          bestMin = low;
          bestGroup = g;
          bestRestricted = restricted;
        }
      }
      if (bestGroup != null) {
        notes.add(
          '${names(bestGroup)} ${bestGroup.length == 1 ? 'does' : 'do'} better '
          'from ${bestRestricted!.map((c) => c.title).join(' + ')}, which the '
          'others in the tie cannot win, so that money is taken out of the pool.',
        );
        allocateTie(bestGroup, bestRestricted);
        final chosen = bestGroup.map((e) => e.id).toSet();
        final rest = contenders.where((e) => !chosen.contains(e.id)).toList();
        allocateTie(rest, prizes.where((c) => !awarded.contains(c)).toList());
        return;
      }
    }

    // Award the pool.
    for (final c in pool) {
      awarded.add(c);
    }
    if (contenders.length == 1 && pool.length == 1) {
      final e = contenders.single, c = pool.single;
      final amount = full[e.id]!;
      e.cents += amount;
      cashLines[c.prize.id]![e.id] = amount;
      notes.add(
        '${e.name} (${e.standing}) wins ${c.title}: ${dollars(amount)}'
        '${c.remainderOf != null ? ' (32C6 remainder)' : ''}.',
      );
    } else {
      final shares = full.values.toSet();
      final sum = pool.length == 1
          ? '${pool.single.title} (${dollars(total)}) split'
          : '${pool.map((c) => c.title).join(' + ')}: '
                '${pool.map((c) => dollars(c.cents)).join(' + ')} = ${dollars(total)} pooled';
      final first = contenders.first;
      notes.add(
        '${first.placing.isNotEmpty ? '${names(contenders)} are level in the bracket (${first.placing})' : '${contenders.length} $several tied at ${scoreText(first.points)} (${names(contenders)})'} '
        'for $sum, '
        '${shares.length == 1 ? '${dollars(shares.single)} each' : contenders.map((e) => '${e.name} ${dollars(full[e.id]!)}').join(', ')}.',
      );
      // Every sharer appears under every pooled prize with their full share.
      for (final c in pool) {
        pooledWith[c.prize.id] = [
          for (final o in pool)
            if (o != c && !pooledWith[c.prize.id]!.contains(o.prize.id))
              o.prize.id,
        ];
        for (final e in contenders) {
          if (full[e.id]! > 0) cashLines[c.prize.id]![e.id] = full[e.id]!;
        }
      }
      for (final e in contenders) {
        e.cents += full[e.id]!;
      }
    }
    // 33F / 32C6: an unrated player's limit. The excess stays in the point
    // group, with nobody lifted above the prize they would win alone
    // (32B3); what is left stays in the prize group for the next level.
    if (table.unratedCapCents > 0) {
      for (final e in contenders) {
        if (e.rating != 0 || e.cents <= table.unratedCapCents) continue;
        var excess = e.cents - table.unratedCapCents;
        final over = excess;
        e.cents = table.unratedCapCents;
        final source = pool.firstWhere(
          (c) => (cashLines[c.prize.id]![e.id] ?? 0) > 0,
          orElse: () => pool.first,
        );
        int room(_Entrant o) => groupOf[o.id]!.best(prizes) - o.cents;
        var open = contenders
            .where((o) => o != e && o.rating != 0 && room(o) > 0)
            .toList();
        while (open.isNotEmpty && excess > 0) {
          // Equal shares; the first `excess % open.length` get a cent more.
          final each = excess ~/ open.length;
          final filled = open.where((o) => room(o) <= each).toList();
          if (filled.isEmpty) {
            var leftover = excess % open.length;
            for (final o in open) {
              o.cents += each + (leftover-- > 0 ? 1 : 0);
            }
            excess = 0;
            break;
          }
          for (final o in filled) {
            excess -= room(o);
            o.cents += room(o);
          }
          open = open.where((o) => !filled.contains(o)).toList();
        }
        final limited =
            '${e.name} is unrated and limited to ${dollars(table.unratedCapCents)}; ';
        if (excess > 0) {
          pending.add(_Cash(source.prize, excess, remainderOf: source.prize));
        }
        notes.add(
          excess == 0
              ? '${limited}the remaining ${dollars(over)} goes to the others in the tie (32C6).'
              : excess == over
              ? '${limited}the remaining ${dollars(excess)} of ${source.prize.title} goes to the next '
                    'eligible score group (32C6).'
              : '$limited${dollars(over - excess)} goes to the others in the tie, nobody '
                    'above the prize they would win alone (32B3), and the remaining '
                    '${dollars(excess)} of ${source.prize.title} goes to the next eligible '
                    'score group (32C6).',
        );
        for (final c in pool) {
          for (final o in contenders) {
            if (o.cents > 0) {
              cashLines[c.prize.id]![o.id] = o.cents;
            } else {
              cashLines[c.prize.id]!.remove(o.id);
            }
          }
        }
      }
    }
  }

  // Levels from the top; the pool of a level never reaches below it.
  var i = 0;
  while (i < entrants.length) {
    var j = i;
    while (j < entrants.length && entrants[j].level == entrants[i].level) {
      j++;
    }
    final tied = entrants.sublist(i, j);
    final open = [
      for (final c in available)
        if (!awarded.contains(c)) c,
      ...pending.where((c) => !awarded.contains(c)),
    ];
    if (open.isEmpty) break;
    allocateTie(tied, open);
    i = j;
  }

  // 33E: prizes by points, one per player, instead of a smaller pooled award.
  final pointPrizes = [
    for (final p in table.list)
      if (p.kind == PrizeKind.points && p.points > 0) p,
  ]..sort((a, b) => b.points.compareTo(a.points));
  for (final e in entrants) {
    final prize = pointPrizes
        .where((p) => e.points >= p.points && eligible(e, p))
        .firstOrNull;
    if (prize == null) continue;
    final amount = paid[prize.id]!;
    if (amount <= e.cents) continue;
    if (e.cents > 0) {
      notes.add(
        '${e.name} takes the ${prize.title} prize (${dollars(amount)}) '
        'instead of ${dollars(e.cents)} from the pooled prizes (32B1).',
      );
      for (final line in cashLines.values) {
        line.remove(e.id);
      }
    } else {
      notes.add(
        '${e.name} (${scoreText(e.points)}) wins ${prize.title}: ${dollars(amount)}.',
      );
    }
    e.cents = amount;
    cashLines[prize.id]![e.id] = amount;
  }

  // ---- Trophies (32F, 33D1, 33D2): one each, by standings order, the
  // highest-ranked trophy the player qualifies for. 33D1a: the award with
  // the larger cash component ranks higher; between equal amounts, place
  // before class and a higher class before a lower one.
  final trophies =
      [
        for (final p in ordered)
          if (p.trophy) p,
      ]..sort((a, b) {
        final cash = paid[b.id]!.compareTo(paid[a.id]!);
        return cash != 0 ? cash : rank[a.id]!.compareTo(rank[b.id]!);
      });
  final trophyWinner = <String, String>{}, trophyNotes = <String, String>{};
  for (final (i, e) in entrants.indexed) {
    final prize = trophies
        .where((p) => !trophyWinner.containsKey(p.id) && eligible(e, p))
        .firstOrNull;
    if (prize == null) continue;
    trophyWinner[prize.id] = e.id;
    e.trophies.add(prize);
    // Entrants on the same level who could have taken it rank lower; the
    // first of them is the one tie-breaks had to separate.
    final rivals = [
      for (final o in entrants.skip(i + 1))
        if (o.level == e.level && eligible(o, prize)) o,
    ];
    if (rivals.isEmpty) {
      notes.add('${e.name} takes the ${prize.awardTitle}.');
      continue;
    }
    final next = rivals.first;
    final decided = [
      for (final (k, mine) in e.tiebreaks.indexed)
        if (k < next.tiebreaks.length && mine.value != next.tiebreaks[k].value)
          (mine, next.tiebreaks[k]),
    ].firstOrNull;
    final tied = e.placing.isNotEmpty
        ? 'Level in the bracket (${e.placing}) with ${names(rivals)}'
        : 'Tied on ${scoreText(e.points)} with ${names(rivals)}';
    trophyNotes[prize.id] = e.tiebreaks.isEmpty
        ? e.placing.isNotEmpty
              ? '$tied, and the bracket does not rank them: decide by lot or a play-off.'
              : '$tied, and the section uses no tie-breaks: decide by lot or a play-off.'
        : decided == null
        ? rivals.length == 1
              ? '$tied and equal on every tie-break: decide by lot.'
              : '$tied; equal with ${next.name} on every tie-break: '
                    'decide by lot.'
        : '$tied; ahead of ${next.name} on ${decided.$1.method.label}, '
              '${decided.$1.text} to ${decided.$2.text}.';
    notes.add(
      '${e.name} takes the ${prize.awardTitle}'
      '${e.tiebreaks.isEmpty ? '' : ' on tie-breaks'}. '
      '${trophyNotes[prize.id]}',
    );
  }

  // ---- Lines and awards.
  final unitNames = {
    for (final e in entrants)
      if (e.players.length > 1) e.id: e.name,
  };
  final lines = <PrizeLine>[];
  for (final p in table.list) {
    final cash = cashLines[p.id]!;
    var note = '';
    if (p.cents == 0 && !p.trophy) {
      note = 'Neither cash nor a trophy';
    } else if (p.kind == PrizeKind.under && p.max == 0) {
      note = 'Under prize needs a rating limit';
    } else if (cash.isEmpty &&
        p.cents > 0 &&
        (!p.trophy || trophyWinner[p.id] == null)) {
      note = entrants.any((e) => eligible(e, p))
          ? 'Not awarded'
          : 'No eligible player (32C3)';
    } else if (cash.isEmpty && p.trophy && trophyWinner[p.id] == null) {
      note = 'No eligible player';
    }
    lines.add(
      PrizeLine(
        p,
        paid[p.id]!,
        cash,
        pooledWith[p.id]!,
        trophyWinner[p.id],
        note,
        trophyNote: trophyNotes[p.id] ?? '',
        names: {
          for (final id in [...cash.keys, ?trophyWinner[p.id]])
            id: ?unitNames[id],
        },
      ),
    );
  }
  for (final p in table.list) {
    if (p.cents > 0 && p.kind != PrizeKind.points && cashLines[p.id]!.isEmpty) {
      final why = entrants.any((e) => eligible(e, p))
          ? 'every eligible player already holds a larger prize'
          : 'no eligible player finished (32C3)';
      notes.add('${p.title} (${dollars(paid[p.id]!)}) is not awarded: $why.');
    }
  }
  final awards = [
    for (final e in entrants)
      if (e.cents > 0 || e.trophies.isNotEmpty)
        PlayerAward(
          e.players.first,
          e.points,
          e.cents,
          e.trophies,
          partners: e.players.skip(1).toList(),
          placing: e.placing,
        ),
  ];
  return PrizeAllocation(
    table: table,
    lines: lines,
    awards: awards,
    explanations: notes,
    entries: entries,
    payoutPercent: payout.percent,
  );
}
