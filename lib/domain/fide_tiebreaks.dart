import 'fide.dart';
import 'fixed_schedule.dart';
import 'model.dart';
import 'tiebreaks.dart';
import 'trf.dart';

/// FIDE tie-break regulations C.07 (approved 2 February 2026, applied from
/// 1 March 2026), for FIDE-rated sections. Source:
/// `research/local/fide-c07-tiebreak-2026.txt`; codes as TRF records
/// 202/212 write them (MTB26).
///
/// Values use the units of [TiebreakMethod]: half-points for scores,
/// quarter-points for products (Sonneborn–Berger, averaged encounters).

/// C.07 has no default list (2.1: the regulations announce one). These are
/// Meow-Chess's defaults, shown and printed before round 1: none is
/// rating-based, so unrated players never make them unusable (Art. 10),
/// and Buchholz is never used in a round robin (Art. 8).
List<TiebreakMethod> defaultFideTiebreaks(Format format) => switch (format) {
  Format.swiss => const [
    TiebreakMethod.fideBhC1,
    TiebreakMethod.fideBh,
    TiebreakMethod.fideSb,
    TiebreakMethod.fideDe,
    TiebreakMethod.fideWin,
  ],
  _ => const [
    TiebreakMethod.fideDe,
    TiebreakMethod.fideWin,
    TiebreakMethod.fideSb,
    TiebreakMethod.fideKs,
  ],
};

/// The FIDE methods a FIDE-rated [section] ranks by: the event's announced
/// FIDE order, or the default for its format. Buchholz methods are left
/// out of a round robin (Art. 8).
List<TiebreakMethod> fideSectionTiebreaks(Event event, Section section) {
  final format = pairingFormat(section);
  final posted = [
    for (final code in event.fideTiebreaks)
      if (tiebreakMethod(code) case final m? when m.fide) m,
  ];
  final list = posted.isEmpty ? defaultFideTiebreaks(format) : posted;
  return format == Format.swiss
      ? list
      : [
          for (final m in list)
            if (!m.buchholz) m,
        ];
}

/// Codes that are not C.07 methods Meow-Chess computes, or that repeat.
String? fideTiebreakCodesProblem(List<String> codes) {
  final unknown = [
    for (final c in codes)
      if (!(tiebreakMethod(c)?.fide ?? false)) c,
  ];
  if (unknown.isNotEmpty) {
    return 'Unknown FIDE tie-break ${unknown.join(', ')}. Use ${TiebreakMethod.values.where((m) => m.fide).map((m) => m.code).join(', ')}.';
  }
  if (codes.toSet().length != codes.length) {
    return 'A tie-break may appear only once in the order.';
  }
  return null;
}

/// An MTB26 rank order descriptor for an individual tie-break, such as
/// `BH/C1/P`: the acronym and what its modifiers and options ask for.
class FideTiebreakCode {
  const FideTiebreakCode(
    this.name, {
    this.low = 0,
    this.high = 0,
    this.forfeitsPlayed = false,
    this.reverse = false,
    this.fore = false,
    this.limit = 0,
  });

  /// The acronym (C.07 table 5), upper case.
  final String name;

  /// Least and most significant values cut (/C1, /C2; /M1, /M2 cut both).
  final int low, high;

  /// /P: forfeits count as games against the scheduled opponent.
  final bool forfeitsPlayed;

  /// /R: the order is reversed (RTNG, TPN).
  final bool reverse;

  /// /F: Fore Buchholz instead of Buchholz (AOB).
  final bool fore;

  /// /L±n: Koya's limit moved by n half-points.
  final int limit;

  /// [code] as MTB26 writes it (case-insensitive), or null when it is not
  /// a descriptor this program reads.
  static FideTiebreakCode? parse(String code) {
    final parts = code.trim().toUpperCase().split('/');
    if (parts.first.isEmpty || parts.first.contains(':')) return null;
    var low = 0, high = 0, limit = 0;
    var forfeitsPlayed = false, reverse = false, fore = false;
    for (final v in parts.skip(1)) {
      if (RegExp(r'^C(\d)$').firstMatch(v) case final m?) {
        low = int.parse(m[1]!);
      } else if (RegExp(r'^M(\d)$').firstMatch(v) case final m?) {
        low = high = int.parse(m[1]!);
      } else if (RegExp(r'^L([+-])(\d+)$').firstMatch(v) case final m?) {
        limit = int.parse(m[2]!) * (m[1] == '-' ? -1 : 1);
      } else if (v == 'P') {
        forfeitsPlayed = true;
      } else if (v == 'R') {
        reverse = true;
      } else if (v == 'F') {
        fore = true;
      } else {
        return null;
      }
    }
    return FideTiebreakCode(
      parts.first,
      low: low,
      high: high,
      forfeitsPlayed: forfeitsPlayed,
      reverse: reverse,
      fore: fore,
      limit: limit,
    );
  }
}

/// One round of one player, as Article 16 classifies it.
class _Round {
  _Round(this.cell, this.opponent, this.points);
  final TrfCell cell;

  /// The scheduled opponent's player ID, or null for a bye or absence.
  final String? opponent;

  /// Half-points scored in the round.
  final int points;

  /// Played over the board, rated or not (a game that lasted less than one
  /// move, W/D/L, still counts as played).
  bool get played => const {'1', '=', '0', 'W', 'D', 'L'}.contains(cell.result);
  bool get forfeit => !played && opponent != null;
  bool get requestedBye =>
      opponent == null && (cell.result == 'H' || cell.result == 'Z');

  /// 16.1.2: a voluntary unplayed round, a requested bye or forfeit loss.
  bool get vur => requestedBye || (forfeit && cell.result == '-');
}

/// One element of a Buchholz-type sum: the opponent's (or dummy's) score,
/// the participant's points in that round, and whether it came from a
/// voluntary unplayed round.
typedef _Contribution = ({int opponent, int points, bool vur});

/// C.07 values for one section. [outcomeOf] chooses the result that counts
/// (the wall chart, or prize outcomes).
///
/// Where C.07 leaves a detail open, the values follow TEC's open reference
/// implementation (Gacrux): Koya counts every paired round; Standard
/// Points compares each round's points with a draw's; rating averages
/// leave unrated opponents out.
class FideTiebreaks {
  FideTiebreaks(this.event, this.section, this._outcomeOf)
    : swiss = pairingFormat(section) == Format.swiss {
    final outcomeOf = _outcomeOf;
    final t = trfTournament(event, section);
    _rank = {for (final (i, p) in t.players.indexed) p.id: i + 1};
    for (final p in t.players) {
      _rounds[p.id] = [
        for (final (round, leg) in t.rounds)
          () {
            final cell = trfCell(t, p, round, leg, outcomeOf);
            return _Round(
              cell,
              cell.opponent == 0 ? null : t.players[cell.opponent - 1].id,
              trfCellHalves(cell, pab: section.pabPoints),
            );
          }(),
      ];
    }
    rounds = t.rounds.length;
    _players = t.players.length;
    _category = sectionFideCategory(event, section);
  }

  final Event event;
  final Section section;
  final Outcome Function(Game) _outcomeOf;
  final bool swiss;

  /// Rounds held (TRF rounds: a two-game round counts twice).
  late final int rounds;
  late final int _players;
  late final FideCategory? _category;
  late final Map<String, int> _rank;
  final _rounds = <String, List<_Round>>{};
  final _cache = <String, int?>{};

  List<_Round> _of(String id) => _rounds[id] ?? const [];

  /// The participant's score in this section, in half-points.
  int score(String id) => _of(id).fold(0, (n, r) => n + r.points);

  /// 16.2.5: a requested bye followed only by voluntary unplayed rounds, or
  /// in the last round.
  bool _lateBye(List<_Round> list, int i) =>
      list[i].requestedBye && list.skip(i + 1).every((r) => r.vur);

  /// 16.3: the score an opponent's tie-break sees. Category 16.2.5 rounds
  /// count as draws.
  int adjusted(String id) {
    if (!swiss) return score(id);
    final list = _of(id);
    var total = 0;
    for (var i = 0; i < list.length; i++) {
      total += _lateBye(list, i) ? 1 : list[i].points;
    }
    return total;
  }

  /// For each round, the opponent's score as this participant's Buchholz
  /// and Sonneborn–Berger see it, and whether the round was a VUR. In a
  /// Swiss an unplayed round is a game against a dummy (16.4), unless /P
  /// counts a forfeit as a game; in a round robin a forfeit is a game
  /// against the scheduled opponent and a sit-out contributes nothing
  /// (15.2).
  List<_Contribution> _contributions(String id, {bool forfeitsPlayed = false}) {
    final own = score(id);
    return [
      for (final r in _of(id))
        if (r.played || (r.forfeit && (!swiss || forfeitsPlayed)))
          (opponent: adjusted(r.opponent!), points: r.points, vur: false)
        else if (swiss)
          (
            opponent: [
              own,
              r.forfeit ? adjusted(r.opponent!) : rounds,
            ].reduce((a, b) => a < b ? a : b),
            points: r.points,
            vur: r.vur,
          ),
    ];
  }

  /// Sums [values] (each with its sort key and whether it came from a VUR)
  /// after cutting [low] least and [high] most significant ones, with the
  /// Cut-1 exception of 16.5 for the low cuts.
  int _cut(
    List<({int key, int value, bool vur})> values, {
    int low = 0,
    int high = 0,
  }) {
    final list = [...values]
      ..sort(
        (a, b) => a.key != b.key
            ? a.key.compareTo(b.key)
            : a.value.compareTo(b.value),
      );
    for (var i = 0; i < low && list.isNotEmpty; i++) {
      final least = list.first;
      final vurs = list.where((v) => v.vur).toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      // 16.5.1: the lowest VUR contribution is cut when it is not lower
      // than the least significant value (for Sonneborn–Berger, the higher
      // of the two is cut).
      final cut = vurs.isNotEmpty && vurs.first.value >= least.value
          ? vurs.first
          : least;
      list.remove(cut);
    }
    for (var i = 0; i < high && list.isNotEmpty; i++) {
      list.removeLast();
    }
    return list.fold(0, (n, v) => n + v.value);
  }

  int buchholz(
    String id, {
    int low = 0,
    int high = 0,
    bool forfeitsPlayed = false,
  }) => _cut(
    [
      for (final c in _contributions(id, forfeitsPlayed: forfeitsPlayed))
        (key: c.opponent, value: c.opponent, vur: c.vur),
    ],
    low: low,
    high: high,
  );

  /// Quarter-points: opponent's score × points scored, both in halves.
  int sonnebornBerger(
    String id, {
    int low = 0,
    int high = 0,
    bool forfeitsPlayed = false,
  }) => _cut(
    [
      for (final c in _contributions(id, forfeitsPlayed: forfeitsPlayed))
        (key: c.opponent, value: c.opponent * c.points, vur: c.vur),
    ],
    low: low,
    high: high,
  );

  int progressive(String id, {int low = 0}) {
    var running = 0;
    final after = <int>[];
    for (final r in _of(id)) {
      running += r.points;
      after.add(running);
    }
    // 14.1: PS Cut-1 drops the score after the first round(s).
    return after.skip(low).fold(0, (n, v) => n + v);
  }

  /// Art. 6 for [id] within [group] (the participants still tied): their
  /// place among them, negated so that the first place ranks highest.
  /// Forfeits count only in a round robin or with /P (6.1.1, 15.2);
  /// repeated meetings are averaged (6.1.2).
  int directEncounter(
    String id,
    List<String> group, {
    bool forfeitsPlayed = false,
  }) {
    final key =
        '${forfeitsPlayed ? 'P' : ''}|${(group.toList()..sort()).join('|')}';
    return (_encounters[key] ??= _encounterValues(group, forfeitsPlayed))[id] ??
        -1;
  }

  final _encounters = <String, Map<String, int>>{};

  /// The averaged result of [a] against [b] in quarter-points, or null
  /// when they did not meet.
  int? _against(String a, String b, bool forfeitsPlayed) {
    final results = [
      for (final r in _of(a))
        if ((r.played || (r.forfeit && (!swiss || forfeitsPlayed))) &&
            r.opponent == b)
          r.points,
    ];
    if (results.isEmpty) return null;
    return (results.fold(0, (x, y) => x + y) * 2) ~/ results.length;
  }

  Map<String, int> _encounterValues(List<String> group, bool forfeitsPlayed) {
    final tiers = _encounterTiers(group, forfeitsPlayed);
    var place = 1;
    final out = <String, int>{};
    for (final tier in tiers) {
      for (final a in tier) {
        out[a] = -place;
      }
      place += tier.length;
    }
    return out;
  }

  /// Art. 6: [group] split into places, best first; players left tied
  /// share a place.
  ///
  /// When everyone met (or in a round robin), the separate standings
  /// order them (6.2). In a Swiss where not everyone met, players are
  /// placed from the top of the separate standings for as long as each is
  /// alone on top whatever the missing games bring (6.3). Article 6 is then
  /// applied again to every set still tied, until nothing changes.
  List<List<String>> _encounterTiers(List<String> group, bool forfeitsPlayed) {
    if (group.length < 2) return [group];
    final points = <String, int>{}, met = <String, int>{};
    for (final a in group) {
      var p = 0, n = 0;
      for (final b in group) {
        if (a == b) continue;
        if (_against(a, b, forfeitsPlayed) case final r?) {
          p += r;
          n++;
        }
      }
      points[a] = p;
      met[a] = n;
    }
    final everyoneMet =
        !swiss || group.every((a) => met[a] == group.length - 1);
    final List<List<String>> tiers;
    if (everyoneMet) {
      final levels = points.values.toSet().toList()
        ..sort((a, b) => b.compareTo(a));
      tiers = [
        for (final level in levels)
          [
            for (final a in group)
              if (points[a] == level) a,
          ],
      ];
    } else {
      // The most a player could reach: a win in every missing game.
      int most(String a) => points[a]! + 4 * (group.length - 1 - met[a]!);
      final order = [...group]
        ..sort(
          (a, b) => points[a] != points[b]
              ? points[b]!.compareTo(points[a]!)
              : most(b).compareTo(most(a)),
        );
      tiers = [];
      var i = 0;
      while (i < order.length - 1 &&
          order.skip(i + 1).every((b) => points[order[i]]! > most(b))) {
        tiers.add([order[i]]);
        i++;
      }
      tiers.add(order.sublist(i));
    }
    if (tiers.length == 1) return tiers;
    return [for (final tier in tiers) ..._encounterTiers(tier, forfeitsPlayed)];
  }

  int wins(String id) => _of(id).where((r) => r.points == 2).length;
  int gamesWon(String id) =>
      _of(id).where((r) => r.played && r.points == 2).length;
  int blackGames(String id) =>
      _of(id).where((r) => r.played && r.cell.color == 'b').length;
  int blackWins(String id) => _of(
    id,
  ).where((r) => r.played && r.points == 2 && r.cell.color == 'b').length;

  /// 7.6: rounds less half-point byes, zero-point byes and forfeit losses.
  int roundsElected(String id) =>
      _of(id).length -
      _of(
        id,
      ).where((r) => r.requestedBye || (r.forfeit && r.points == 0)).length;

  /// 7.7, in half-points: 2 for each round scoring more than a draw, 1 for
  /// each scoring a draw's points.
  int standardPoints(String id) => _of(
    id,
  ).fold(0, (n, r) => n + (r.points > 1 ? 2 : (r.points == 1 ? 1 : 0)));

  int _rating(String id) => fideRating(event.player(id), _category);

  /// Played (over the board) games against opponents FIDE rates in this
  /// list: (opponent rating, points in halves).
  List<(int, int)> _ratedGames(String id) => [
    for (final r in _of(id))
      if (r.played && _rating(r.opponent!) > 0)
        (_rating(r.opponent!), r.points),
  ];

  /// 10.1: the average FIDE rating of opponents played over the board,
  /// rounded half up, after cutting [low] lowest and [high] highest;
  /// unrated opponents are left out. Null without rated opponents.
  int? averageOpponentRating(String id, {int low = 0, int high = 0}) {
    final ratings = [for (final g in _ratedGames(id)) g.$1]..sort();
    final kept = ratings
        .skip(low)
        .take((ratings.length - low - high).clamp(0, ratings.length))
        .toList();
    if (kept.isEmpty) return null;
    return (kept.fold(0, (a, b) => a + b) / kept.length + 0.5).floor();
  }

  /// 9.2: points against participants who scored at least half the
  /// maximum possible score, moved by [limit] half-points (14.5). A round
  /// robin with an odd field counts the round each player sits out.
  int koya(String id, {int limit = 0}) {
    var games = rounds;
    if (!swiss && _players > 0 && rounds % _players == 0) {
      games -= rounds ~/ _players;
    }
    final threshold = games + limit;
    return _of(id)
        .where((r) => r.opponent != null && score(r.opponent!) >= threshold)
        .fold(0, (n, r) => n + r.points);
  }

  /// 10.2: ARO plus the rating difference for the fractional score over
  /// the board (B.02 table 8.1.1). Null without rated games.
  int? performance(String id) {
    final games = _ratedGames(id);
    if (games.isEmpty) return null;
    final aro = averageOpponentRating(id)!;
    final points = games.fold(0, (n, g) => n + g.$2);
    final p = (points * 100 / (games.length * 2)).round();
    return aro + fideScoreDifference[p];
  }

  /// 10.3: the lowest rating whose expected score (table 8.1.2, no 400
  /// cut) reaches the score over the board. A zero score is 800 below the
  /// lowest opponent. Null without rated games.
  int? perfectPerformance(String id) {
    final games = _ratedGames(id);
    if (games.isEmpty) return null;
    final ratings = [for (final g in games) g.$1]..sort();
    final points = games.fold(0, (n, g) => n + g.$2);
    if (points == 0) return ratings.first - 800;
    // Score and expectation in hundredths of a point. The expectation never
    // falls as the rating rises, so the lowest rating reaching the score is
    // found by halving the range.
    final target = points * 50;
    int expected(int rating) => ratings.fold(
      0,
      (n, opponent) => n + fideExpectedHundredths(rating - opponent),
    );
    var low = ratings.first - 800, high = ratings.last + 800;
    if (expected(high) < target) return high;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (expected(mid) >= target) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }

  /// The average of [value] over the opponents played over the board,
  /// rounded half up; opponents without a value are left out.
  int? _averageOver(String id, int? Function(String) value) {
    final values = [
      for (final r in _of(id))
        if (r.played) ?value(r.opponent!),
    ];
    if (values.isEmpty) return null;
    return (values.fold(0, (a, b) => a + b) / values.length + 0.5).floor();
  }

  /// 8.2, thousandths of a point: the average Buchholz (or, [fore], Fore
  /// Buchholz) of the opponents played over the board, rounded half up to
  /// two decimals before round 9 and three from then on.
  int averageOpponentsBuchholz(String id, {bool fore = false}) {
    final source = fore ? _fore : this;
    final values = [
      for (final r in _of(id))
        if (r.played) source.buchholz(r.opponent!),
    ];
    if (values.isEmpty) return 0;
    // Halves summed over n games: the mean in thousandths is
    // sum × 500 / n.
    final sum = values.fold(0, (a, b) => a + b), n = values.length;
    final step = rounds < 9 ? 10 : 1;
    return ((sum * 500 / n / step) + 0.5).floor() * step;
  }

  /// 8.3: Buchholz as if every paired game of the last round were drawn.
  late final FideTiebreaks _fore = FideTiebreaks(
    event,
    section,
    (g) => section.rounds.isNotEmpty && section.rounds.last.games.contains(g)
        ? Outcome.draw
        : _outcomeOf(g),
  );

  int value(TiebreakMethod method, String id, List<String> group) {
    final code = FideTiebreakCode.parse(method.code);
    if (code == null || !method.fide) {
      throw ArgumentError('$method is not a FIDE tie-break');
    }
    if (method.groupwise) {
      return directEncounter(id, group, forfeitsPlayed: code.forfeitsPlayed);
    }
    return _cache.putIfAbsent('${method.code}|$id', () => _value(code, id)) ??
        0;
  }

  int? _value(FideTiebreakCode c, String id) {
    final p = c.forfeitsPlayed;
    return switch (c.name) {
      'BH' => buchholz(id, low: c.low, high: c.high, forfeitsPlayed: p),
      'FB' => _fore.buchholz(id, low: c.low, high: c.high, forfeitsPlayed: p),
      'SB' => sonnebornBerger(id, low: c.low, high: c.high, forfeitsPlayed: p),
      'WIN' => wins(id),
      'WON' => gamesWon(id),
      'BPG' => blackGames(id),
      'BWG' => blackWins(id),
      'PS' => progressive(id, low: c.low),
      'REP' || 'GE' => roundsElected(id),
      'STD' => standardPoints(id),
      'KS' => koya(id, limit: c.limit),
      'ARO' => averageOpponentRating(id, low: c.low, high: c.high),
      'TPR' => performance(id),
      'PTP' => perfectPerformance(id),
      'APRO' => _averageOver(id, performance),
      'APPO' => _averageOver(id, perfectPerformance),
      'AOB' => averageOpponentsBuchholz(id, fore: c.fore),
      // Higher values rank first: a lower rating or pairing number ranks
      // higher only when reversed or by nature.
      'RTNG' => c.reverse ? -_rating(id) : _rating(id),
      'TPN' => c.reverse ? _rank[id] ?? 0 : -(_rank[id] ?? 0),
      _ => throw ArgumentError('${c.name} is not a FIDE tie-break'),
    };
  }
}

/// B.02 table 8.1.1: the rating difference for a fractional score, by
/// hundredths (index 0 is a zero score, 100 a full score).
const fideScoreDifference = [
  -800, -677, -589, -538, -501, -470, -444, -422, -401, -383, -366, -351, //
  -336, -322, -309, -296, -284, -273, -262, -251, -240, -230, -220, -211, //
  -202, -193, -184, -175, -166, -158, -149, -141, -133, -125, -117, -110, //
  -102, -95, -87, -80, -72, -65, -57, -50, -43, -36, -29, -21, -14, -7, 0, //
  7, 14, 21, 29, 36, 43, 50, 57, 65, 72, 80, 87, 95, 102, 110, 117, 125, //
  133, 141, 149, 158, 166, 175, 184, 193, 202, 211, 220, 230, 240, 251, //
  262, 273, 284, 296, 309, 322, 336, 351, 366, 383, 401, 422, 444, 470, //
  501, 538, 589, 677, 800,
];

/// B.02 table 8.1.2: the upper end of each rating-difference band; band i
/// gives the higher-rated player 50 + i hundredths, and above 735, 100.
const _fideBandUpper = [
  3, 10, 17, 25, 32, 39, 46, 53, 61, 68, 76, 83, 91, 98, 106, 113, 121, //
  129, 137, 145, 153, 162, 170, 179, 188, 197, 206, 215, 225, 235, 245, //
  256, 267, 278, 290, 302, 315, 328, 344, 357, 374, 391, 411, 432, 456, //
  484, 517, 559, 619, 735,
];

/// The expected score, in hundredths, of a player [difference] points
/// above (or, negative, below) their opponent (table 8.1.2).
int fideExpectedHundredths(int difference) {
  final d = difference.abs();
  final band = _fideBandUpper.indexWhere((upper) => d <= upper);
  final higher = band < 0 ? 100 : 50 + band;
  return difference >= 0 ? higher : 100 - higher;
}
