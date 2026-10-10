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
    this.trophy = false,
    this.guaranteed = false,
    List<String> eligible = const [],
  }) : eligible = List.unmodifiable(eligible);
  final String id, label;
  final PrizeKind kind;
  final int place, min, max, points, cents;
  final bool trophy, guaranteed;
  final List<String> eligible;

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
    trophy: trophy ?? this.trophy,
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
      teams: j['teams'] is Map ? Map<String, dynamic>.from(j['teams']) : null,
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
    this.note,
  ) : cash = Map.unmodifiable(cash),
      pooledWith = List.unmodifiable(pooledWith);
  final Prize prize;

  /// The amount after any based-on reduction (32C4).
  final int paidCents;

  /// Player ID → cents received: the whole amount for a clear winner; for
  /// a tie, each sharer's full share of the pool this prize went into.
  final Map<String, int> cash;

  /// IDs of the other prizes pooled with this one (32B2); empty otherwise.
  final List<String> pooledWith;
  final String? trophyWinner;
  final String note;

  Json toJson() => {
    'id': prize.id,
    'label': prize.title,
    'announcedCents': prize.cents,
    'paidCents': paidCents,
    'cash': cash,
    if (pooledWith.isNotEmpty) 'pooledWith': pooledWith,
    if (trophyWinner != null) 'trophy': trophyWinner,
    if (note.isNotEmpty) 'note': note,
  };
}

/// What one player takes home.
class PlayerAward {
  PlayerAward(this.player, this.points, this.cents, List<Prize> trophies)
    : trophies = List.unmodifiable(trophies);
  final Player player;
  final int points, cents;
  final List<Prize> trophies;
  Json toJson() => {
    'playerId': player.id,
    'name': player.name,
    'points': points,
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

/// Prize-eligible players in prize-standings order.
class _Entrant {
  _Entrant(this.standing);
  final Standing standing;
  Player get player => standing.player;
  String get id => player.id;
  int get points => standing.points;
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

/// Rules 32B–32G, 33C–33F: who wins what in [section].
PrizeAllocation allocatePrizes(Event event, Section section) {
  final table = PrizeTable.fromJson(section.prizes).individual;
  final notes = <String>[];
  final rows = standings(event, section, forPrizes: true);
  final entries = section.players
      .where((id) => !event.player(id).house)
      .toSet()
      .length;

  // 32C4 / 32E: proportional payout, at least 50% when the whole event
  // announces more than $500; guaranteed prizes are never reduced.
  var percent = 100;
  final paid = <String, int>{};
  if (table.basedOn > 0 && entries < table.basedOn) {
    final eventFund = event.sections.fold(
      0,
      (sum, s) => sum + PrizeTable.fromJson(s.prizes).announcedCents,
    );
    final floor = eventFund > 50000 ? 50 : 0;
    final proportion = entries * 100 ~/ table.basedOn;
    percent = proportion < floor ? floor : proportion;
    notes.add(
      'Prizes were based on ${table.basedOn} entries and $entries entered: '
      'each prize pays $percent%'
      '${proportion < floor ? ' (the 50% minimum, because the announced fund exceeds \$500)' : ''}'
      '${table.list.any((p) => p.guaranteed && p.cents > 0) ? '; guaranteed prizes pay in full' : ''}.',
    );
  }
  for (final p in table.list) {
    paid[p.id] = p.guaranteed ? p.cents : (p.cents * percent / 100).round();
  }

  if (table.isEmpty) {
    return PrizeAllocation(
      table: table,
      lines: const [],
      awards: const [],
      explanations: const ['No prizes are announced for this section.'],
      entries: entries,
      payoutPercent: percent,
    );
  }

  // 32C5: an entry replaced by a re-entry competes only for the record.
  final superseded = {
    for (final p in event.players)
      if (p.reentryOf.isNotEmpty) p.reentryOf,
  };
  final entrants = <_Entrant>[];
  for (final row in rows) {
    final p = row.player;
    if (p.house) continue;
    if (superseded.contains(p.id)) {
      notes.add(
        '${p.name} re-entered; the earlier entry wins no prize (32C5).',
      );
      continue;
    }
    if (p.withdrawn && !table.withdrawnEligible) {
      notes.add('${p.name} withdrew and is not eligible for prizes (32C1).');
      continue;
    }
    entrants.add(_Entrant(row));
  }

  bool eligible(Player p, Prize prize) {
    if (prize.eligible.isNotEmpty && !prize.eligible.contains(p.id)) {
      return false;
    }
    // Rule 36: computers only win prizes designated for computers.
    if (p.computer != (prize.kind == PrizeKind.computer)) return false;
    final rating = p.effectivePrizeRating;
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

  // ---- Cash (32B, 34C): ties on points pool and split; never tie-breaks.
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
  List<_Cash?> match(List<_Entrant> tied, List<_Cash> prizes) {
    final options = [
      for (final e in tied)
        [
          for (final c in prizes)
            if (eligible(e.player, c.prize)) c,
        ]..sort((a, b) => weight(b).compareTo(weight(a))),
    ];
    var best = <_Cash?>[for (final _ in tied) null];
    var bestWeight = -1;
    final taken = <_Cash>{};
    final current = <_Cash?>[for (final _ in tied) null];
    void search(int i, int total) {
      if (i == tied.length) {
        if (total > bestWeight) {
          bestWeight = total;
          best = [...current];
        }
        return;
      }
      // Upper bound: every remaining player takes their own best prize.
      var bound = total;
      for (var j = i; j < tied.length; j++) {
        bound += options[j].isEmpty ? 0 : weight(options[j].first);
      }
      if (bound <= bestWeight) return;
      for (final c in options[i]) {
        if (taken.contains(c)) continue;
        taken.add(c);
        current[i] = c;
        search(i + 1, total + weight(c));
        taken.remove(c);
      }
      current[i] = null;
      search(i + 1, total);
    }

    search(0, 0);
    return best;
  }

  int bestAlone(_Entrant e, List<_Cash> prizes) => prizes
      .where((c) => eligible(e.player, c.prize))
      .fold(0, (m, c) => c.cents > m ? c.cents : m);

  /// Splits [pool] equally among [tied], with nobody above the prize they
  /// would win alone (32B3); any excess flows to the others, then back.
  Map<String, int> divide(List<_Entrant> tied, int pool, List<_Cash> prizes) {
    final caps = {for (final e in tied) e.id: bestAlone(e, prizes)};
    final out = <String, int>{};
    var remaining = pool;
    var open = tied.map((e) => e.id).toList();
    while (open.isNotEmpty && remaining > 0) {
      final share = remaining ~/ open.length;
      final capped = open.where((id) => caps[id]! <= share).toList();
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

  String names(Iterable<_Entrant> es) =>
      es.map((e) => e.player.name).join(', ');

  final awarded = <_Cash>{};
  final pending = <_Cash>[];

  /// Allocates among [tied] (equal points) from [prizes], recursively
  /// carving out players who do better from prizes the rest cannot win.
  void allocateTie(List<_Entrant> tied, List<_Cash> prizes) {
    final contenders = tied
        .where((e) => prizes.any((c) => eligible(e.player, c.prize)))
        .toList();
    if (contenders.isEmpty) return;
    final matched = match(contenders, prizes);
    final pool = matched.whereType<_Cash>().toList();
    final total = pool.fold(0, (sum, c) => sum + c.cents);
    final full = divide(contenders, total, prizes);

    // 32B3: a sub-group takes only prizes the others are ineligible for
    // when every one of them does at least as well and someone does better.
    if (contenders.length > 1) {
      final signatures = <String, List<_Entrant>>{};
      for (final e in contenders) {
        final key = [
          for (final c in prizes)
            if (eligible(e.player, c.prize)) c.prize.id,
        ].join('|');
        (signatures[key] ??= []).add(e);
      }
      final groups = signatures.values.toList();
      List<_Entrant>? bestGroup;
      List<_Cash>? bestRestricted;
      var bestMin = -1;
      if (groups.length > 1 && groups.length <= 12) {
        for (var mask = 1; mask < (1 << groups.length) - 1; mask++) {
          final g = <_Entrant>[
            for (var i = 0; i < groups.length; i++)
              if (mask & (1 << i) != 0) ...groups[i],
          ];
          final inG = g.map((e) => e.id).toSet();
          final restricted = [
            for (final c in prizes)
              if (contenders.every(
                (e) => inG.contains(e.id) || !eligible(e.player, c.prize),
              ))
                c,
          ];
          if (restricted.isEmpty) continue;
          final sub = match(g, restricted).whereType<_Cash>().toList();
          final subTotal = sub.fold(0, (sum, c) => sum + c.cents);
          final split = divide(g, subTotal, restricted);
          if (!g.every((e) => split[e.id]! >= full[e.id]!) ||
              !g.any((e) => split[e.id]! > full[e.id]!)) {
            continue;
          }
          final low = g.fold(
            1 << 60,
            (m, e) => split[e.id]! < m ? split[e.id]! : m,
          );
          if (low > bestMin ||
              (low == bestMin && g.length < bestGroup!.length)) {
            bestMin = low;
            bestGroup = g;
            bestRestricted = restricted;
          }
        }
      }
      if (bestGroup != null) {
        notes.add(
          '${names(bestGroup)} ${bestGroup.length == 1 ? 'does' : 'do'} better '
          'from ${bestRestricted!.map((c) => c.title).join(' + ')}, which the '
          'others in the tie cannot win, so that money is taken out of the pool.',
        );
        allocateTie(bestGroup, bestRestricted);
        final rest = contenders.where((e) => !bestGroup!.contains(e)).toList();
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
        '${e.player.name} (${scoreText(e.points)}) wins ${c.title}: ${dollars(amount)}'
        '${c.remainderOf != null ? ' (32C6 remainder)' : ''}.',
      );
    } else {
      final shares = full.values.toSet();
      final sum = pool.length == 1
          ? '${pool.single.title} (${dollars(total)}) split'
          : '${pool.map((c) => c.title).join(' + ')}: '
                '${pool.map((c) => dollars(c.cents)).join(' + ')} = ${dollars(total)} pooled';
      notes.add(
        '${contenders.length} players tied at ${scoreText(contenders.first.points)} '
        '(${names(contenders)}) for $sum, '
        '${shares.length == 1 ? '${dollars(shares.single)} each' : contenders.map((e) => '${e.player.name} ${dollars(full[e.id]!)}').join(', ')}.',
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
    // 33F / 32C6: an unrated player's limit; the excess stays in the
    // point group, else in the prize group for the next score group.
    if (table.unratedCapCents > 0) {
      for (final e in contenders) {
        if (e.player.effectivePrizeRating != 0 ||
            e.cents <= table.unratedCapCents) {
          continue;
        }
        final excess = e.cents - table.unratedCapCents;
        e.cents = table.unratedCapCents;
        final source = pool.firstWhere(
          (c) => (cashLines[c.prize.id]![e.id] ?? 0) > 0,
          orElse: () => pool.first,
        );
        final others = contenders
            .where((o) => o != e && o.player.effectivePrizeRating != 0)
            .toList();
        if (others.isNotEmpty) {
          // Equal shares; the first `excess % others.length` get a cent more.
          final each = excess ~/ others.length;
          var leftover = excess % others.length;
          for (final o in others) {
            o.cents += each + (leftover-- > 0 ? 1 : 0);
          }
          notes.add(
            '${e.player.name} is unrated and limited to ${dollars(table.unratedCapCents)}; '
            'the remaining ${dollars(excess)} goes to the others in the tie (32C6).',
          );
        } else {
          pending.add(_Cash(source.prize, excess, remainderOf: source.prize));
          notes.add(
            '${e.player.name} is unrated and limited to ${dollars(table.unratedCapCents)}; '
            'the remaining ${dollars(excess)} of ${source.prize.title} goes to the next '
            'eligible score group (32C6).',
          );
        }
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

  // Score groups from the top; the pool of a group never reaches below it.
  var i = 0;
  while (i < entrants.length) {
    var j = i;
    while (j < entrants.length && entrants[j].points == entrants[i].points) {
      j++;
    }
    final tied = entrants.sublist(i, j);
    final open = [
      for (final c in available)
        if (!awarded.contains(c)) c,
      ...pending.where((c) => !awarded.contains(c)),
    ];
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
        .where((p) => e.points >= p.points && eligible(e.player, p))
        .firstOrNull;
    if (prize == null) continue;
    final amount = paid[prize.id]!;
    if (amount <= e.cents) continue;
    if (e.cents > 0) {
      notes.add(
        '${e.player.name} takes the ${prize.title} prize (${dollars(amount)}) '
        'instead of ${dollars(e.cents)} from the pooled prizes (32B1).',
      );
      for (final line in cashLines.values) {
        line.remove(e.id);
      }
    } else {
      notes.add(
        '${e.player.name} (${scoreText(e.points)}) wins ${prize.title}: ${dollars(amount)}.',
      );
    }
    e.cents = amount;
    cashLines[prize.id]![e.id] = amount;
  }

  // ---- Trophies (32F, 33D1, 33D2): one each, by standings order, the
  // highest-ranked trophy the player qualifies for.
  final trophies = [
    for (final p in ordered)
      if (p.trophy) p,
  ];
  final trophyWinner = <String, String>{};
  for (final e in entrants) {
    final prize = trophies
        .where((p) => !trophyWinner.containsKey(p.id) && eligible(e.player, p))
        .firstOrNull;
    if (prize == null) continue;
    trophyWinner[prize.id] = e.id;
    e.trophies.add(prize);
    notes.add(
      '${e.player.name} takes the ${prize.title} trophy'
      '${entrants.any((o) => o != e && o.points == e.points && eligible(o.player, prize)) ? ' on tie-breaks' : ''}.',
    );
  }

  // ---- Lines and awards.
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
      note = entrants.any((e) => eligible(e.player, p))
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
      ),
    );
  }
  for (final p in table.list) {
    if (p.cents > 0 && p.kind != PrizeKind.points && cashLines[p.id]!.isEmpty) {
      final why = entrants.any((e) => eligible(e.player, p))
          ? 'every eligible player already holds a larger prize'
          : 'no eligible player finished (32C3)';
      notes.add('${p.title} (${dollars(paid[p.id]!)}) is not awarded: $why.');
    }
  }
  final awards = [
    for (final e in entrants)
      if (e.cents > 0 || e.trophies.isNotEmpty)
        PlayerAward(e.player, e.points, e.cents, e.trophies),
  ];
  return PrizeAllocation(
    table: table,
    lines: lines,
    awards: awards,
    explanations: notes,
    entries: entries,
    payoutPercent: percent,
  );
}
