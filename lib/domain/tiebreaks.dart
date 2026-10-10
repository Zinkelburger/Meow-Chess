import 'model.dart';

/// How a tie-break value is scaled and printed.
enum TiebreakUnit {
  /// Integer half-points (2 = one point), like [scoreText].
  halves,

  /// Integer quarter-points (4 = one point).
  quarters,

  /// A plain count or rating-point figure.
  whole,

  /// A plus/minus balance, printed with its sign.
  signed,
}

/// US Chess rule 34 tie-break methods. [code] is what `Event.tiebreaks`
/// stores; [defaultTiebreaks] gives the rule 34E / 34F order used when the
/// event has not posted its own.
enum TiebreakMethod {
  /// 34E1: opponents' adjusted scores, discarding the least significant
  /// ones. Unplayed games of an opponent count ½ each; the player's own
  /// unplayed games count as opponents scoring 0.
  modifiedMedian(
    'modifiedMedian',
    'Modified Median',
    '34E1',
    'MMed',
    TiebreakUnit.halves,
  ),

  /// 34E2: the same adjusted opponents' scores, nothing discarded.
  solkoff('solkoff', 'Solkoff', '34E2', 'Solk', TiebreakUnit.halves),

  /// 34E3: the sum of the running score after each round, minus one point
  /// per unplayed win or full-point bye and ½ per unplayed draw or
  /// half-point bye.
  cumulative('cumulative', 'Cumulative', '34E3', 'Cum', TiebreakUnit.halves),

  /// 34E9: the sum of the played opponents' cumulative (34E3) scores.
  cumulativeOpposition(
    'cumulativeOpposition',
    'Cumulative of opposition',
    '34E9',
    'OppCum',
    TiebreakUnit.halves,
  ),

  /// 34E4: adjusted opponents' scores discarding the highest and lowest
  /// (two of each in a nine-round or longer event), whatever the score.
  median('median', 'Median', '34E4', 'Med', TiebreakUnit.halves),

  /// 34E5: wins minus losses in the games among the tied players.
  headToHead(
    'headToHead',
    'Result between tied players',
    '34E5',
    'H2H',
    TiebreakUnit.signed,
  ),

  /// 34E6: games played with black.
  mostBlacks('mostBlacks', 'Most blacks', '34E6', 'Blk', TiebreakUnit.whole),

  /// 34E7: 4 per win, 2 per draw, 1 per loss, 0 per unplayed game.
  kashdan('kashdan', 'Kashdan', '34E7', 'Kash', TiebreakUnit.whole),

  /// 34E8 / 34F: defeated opponents' final scores plus half the drawn
  /// opponents' final scores; nothing for losses or unplayed games.
  sonnebornBerger(
    'sonnebornBerger',
    'Sonneborn–Berger',
    '34E8',
    'SB',
    TiebreakUnit.quarters,
  ),

  /// 34E10: the average performance rating of the played opponents, with
  /// games between tied players left out. Unrated players are skipped.
  opponentsPerformance(
    'opponentsPerformance',
    "Opponents' performance",
    '34E10',
    'OppPerf',
    TiebreakUnit.whole,
  ),

  /// 34E11: the average pairing rating of the played, rated opponents.
  averageOpponentRating(
    'averageOpponentRating',
    'Average opponent rating',
    '34E11',
    'AvgOpp',
    TiebreakUnit.whole,
  ),

  /// 34E13: a recorded draw, fixed by the event and player IDs so it can
  /// be reproduced.
  coinFlip('coinFlip', 'Coin flip', '34E13', 'Coin', TiebreakUnit.whole);

  const TiebreakMethod(this.code, this.label, this.rule, this.short, this.unit);
  final String code, label, rule, short;
  final TiebreakUnit unit;

  /// Methods whose value depends on who else is tied (34E5, 34E10).
  bool get groupwise => this == headToHead || this == opponentsPerformance;

  /// Printed value for [value] in this method's [unit].
  String format(int value) => switch (unit) {
    TiebreakUnit.halves => _halves(value),
    TiebreakUnit.quarters => _quarters(value),
    TiebreakUnit.whole => '$value',
    TiebreakUnit.signed =>
      value > 0
          ? '+$value'
          : value < 0
          ? '−${-value}'
          : '0',
  };

  /// [value] as a number in points (or rating points, games, etc.).
  num number(int value) => switch (unit) {
    TiebreakUnit.halves => value / 2,
    TiebreakUnit.quarters => value / 4,
    _ => value,
  };
}

/// One computed tie-break for a standing row.
class TiebreakValue {
  const TiebreakValue(this.method, this.value);
  final TiebreakMethod method;

  /// In [method]'s unit.
  final int value;
  String get code => method.code;
  String get text => method.format(value);
  num get number => method.number(value);
}

/// Rule 34E's announced default order for a Swiss; rule 34F's for a round
/// robin or quad.
List<TiebreakMethod> defaultTiebreaks(Format format) => switch (format) {
  Format.swiss || Format.bughouse || Format.knockout || Format.ladder => const [
    TiebreakMethod.modifiedMedian,
    TiebreakMethod.solkoff,
    TiebreakMethod.cumulative,
    TiebreakMethod.cumulativeOpposition,
  ],
  Format.roundRobin || Format.quad || Format.scheveningen => const [
    TiebreakMethod.sonnebornBerger,
    TiebreakMethod.headToHead,
  ],
};

/// The method for a stored code, or null for an unknown code.
TiebreakMethod? tiebreakMethod(String code) =>
    TiebreakMethod.values.where((m) => m.code == code).firstOrNull;

/// The posted name for a stored code; unknown codes print as themselves.
String tiebreakLabel(String code) => tiebreakMethod(code)?.label ?? code;

/// Codes that are not rule 34 methods, or that repeat.
String? tiebreakCodesProblem(List<String> codes) {
  final unknown = codes.where((c) => tiebreakMethod(c) == null).toList();
  if (unknown.isNotEmpty) {
    return 'Unknown tie-break method ${unknown.join(', ')}. Use ${TiebreakMethod.values.map((m) => m.code).join(', ')}.';
  }
  if (codes.toSet().length != codes.length) {
    return 'A tie-break method may appear only once in the order.';
  }
  return null;
}

/// The methods this section ranks by, in order: the event's posted list,
/// or the rule 34E / 34F default for the section's pairing format.
List<TiebreakMethod> sectionTiebreaks(Event event, Format format) {
  final posted = event.tiebreaks.map(tiebreakMethod).nonNulls.toList();
  return posted.isEmpty ? defaultTiebreaks(format) : posted;
}

/// Tie-break values for [players], in [methods] order. [scores] are the
/// final half-point scores for everyone in the event (already adjusted
/// for pairing assumptions or prize outcomes); [outcomeOf] is the result
/// that counts for this ranking and [counts] excludes games that do not.
///
/// Groupwise methods (34E5, 34E10) are computed within each set of players
/// still tied on points and every earlier method, so they are only
/// meaningful in the order given.
Map<String, List<TiebreakValue>> tiebreakValues({
  required Event event,
  required Section section,
  required List<String> players,
  required List<TiebreakMethod> methods,
  required Map<String, int> scores,
  required Outcome Function(Game) outcomeOf,
  required bool Function(Game) counts,
}) {
  final calc = _Calculator(event, section, scores, outcomeOf, counts);
  final values = {for (final id in players) id: <TiebreakValue>[]};
  for (final method in methods) {
    final groups = <String, List<String>>{};
    for (final id in players) {
      final key = [
        scores[id] ?? 0,
        ...values[id]!.map((t) => t.value),
      ].join(',');
      groups.putIfAbsent(key, () => []).add(id);
    }
    for (final group in groups.values) {
      for (final id in group) {
        values[id]!.add(TiebreakValue(method, calc.value(method, id, group)));
      }
    }
  }
  return values;
}

class _Played {
  const _Played(this.opponent, this.result, this.black);
  final String opponent;

  /// The player's half-points from this game.
  final int result;
  final bool black;
}

class _Calculator {
  _Calculator(
    this.event,
    this.section,
    this.scores,
    this.outcomeOf,
    this.counts,
  ) : slotsPerRound = section.doubleGames ? 2 : 1 {
    for (final s in event.sections) {
      for (final r in s.rounds) {
        for (final b in r.byes) {
          _add(b.player, r.number, b.points);
          _unplayed[b.player] = (_unplayed[b.player] ?? 0) + b.points;
        }
        for (final g in r.games) {
          if (!counts(g)) continue;
          final o = outcomeOf(g);
          // Bughouse partners share the match: each is credited like the
          // board-1 player of their side, against the other side's board 1.
          for (final (me, opponent, result, black) in [
            (g.white, g.black, o.whiteScore, false),
            (g.black, g.white, o.blackScore, true),
            if (g.whitePartner.isNotEmpty)
              (g.whitePartner, g.black, o.whiteScore, true),
            if (g.blackPartner.isNotEmpty)
              (g.blackPartner, g.white, o.blackScore, false),
          ]) {
            _add(me, r.number, result);
            if (o.played) {
              (_played[me] ??= []).add(_Played(opponent, result, black));
            } else {
              _unplayed[me] = (_unplayed[me] ?? 0) + result;
            }
          }
        }
      }
    }
  }

  final Event event;
  final Section section;
  final Map<String, int> scores;
  final Outcome Function(Game) outcomeOf;
  final bool Function(Game) counts;
  final int slotsPerRound;

  /// Half-points scored per round number, including byes and forfeits.
  final _byRound = <String, Map<int, int>>{};
  final _played = <String, List<_Played>>{};

  /// Half-points from byes and forfeit wins (34E3's deductions).
  final _unplayed = <String, int>{};
  final _cache = <TiebreakMethod, Map<String, int>>{};

  void _add(String id, int round, int halves) {
    final rounds = _byRound[id] ??= {};
    rounds[round] = (rounds[round] ?? 0) + halves;
  }

  List<_Played> played(String id) => _played[id] ?? const [];

  /// Game slots the section has held so far.
  int get slots => section.rounds.length * slotsPerRound;

  /// Rounds held that this player did not play out, each worth ½ in the
  /// 34E1 adjusted score.
  int unplayedSlots(String id) => (slots - played(id).length).clamp(0, slots);

  /// 34E1: the score used when this player is someone's opponent.
  int adjustedScore(String id) =>
      played(id).fold(0, (sum, g) => sum + g.result) + unplayedSlots(id);

  int value(TiebreakMethod method, String id, List<String> group) {
    if (method.groupwise) {
      return switch (method) {
        TiebreakMethod.headToHead => _headToHead(id, group),
        _ => _opponentsPerformance(id, group),
      };
    }
    return (_cache[method] ??= {}).putIfAbsent(id, () => _scalar(method, id));
  }

  int _scalar(TiebreakMethod method, String id) => switch (method) {
    TiebreakMethod.modifiedMedian => _modifiedMedian(id),
    TiebreakMethod.solkoff => _median(id, low: 0, high: 0),
    TiebreakMethod.median => _median(id, low: _discards, high: _discards),
    TiebreakMethod.cumulative => _cumulative(id),
    TiebreakMethod.cumulativeOpposition => played(
      id,
    ).fold(0, (sum, g) => sum + _cumulative(g.opponent)),
    TiebreakMethod.mostBlacks => played(id).where((g) => g.black).length,
    TiebreakMethod.kashdan => played(
      id,
    ).fold(0, (sum, g) => sum + const [1, 2, 4][g.result]),
    TiebreakMethod.sonnebornBerger => played(
      id,
    ).fold(0, (sum, g) => sum + (scores[g.opponent] ?? 0) * g.result),
    TiebreakMethod.averageOpponentRating => _average(
      played(id).map((g) => _rating(g.opponent)).where((r) => r > 0),
    ),
    TiebreakMethod.coinFlip => _coin(id),
    TiebreakMethod.headToHead || TiebreakMethod.opponentsPerformance =>
      throw StateError('$method is groupwise'),
  };

  /// 34E1: two from each end in a nine-round or longer event.
  int get _discards => section.plannedRounds >= 9 ? 2 : 1;

  int _modifiedMedian(String id) {
    final points = scores[id] ?? 0, even = slots;
    return _median(
      id,
      low: points >= even ? _discards : 0,
      high: points <= even ? _discards : 0,
    );
  }

  /// Opponents' adjusted scores, with 0 for each of the player's own
  /// unplayed games, less [low] from the bottom and [high] from the top.
  int _median(String id, {required int low, required int high}) {
    final list = [
      for (final g in played(id)) adjustedScore(g.opponent),
      for (var i = 0; i < unplayedSlots(id); i++) 0,
    ]..sort();
    final kept = list
        .skip(low)
        .take((list.length - low - high).clamp(0, list.length));
    return kept.fold(0, (sum, v) => sum + v);
  }

  int _cumulative(String id) {
    final rounds = _byRound[id] ?? const {};
    var running = 0, total = 0;
    for (var r = 1; r <= section.rounds.length; r++) {
      running += rounds[r] ?? 0;
      total += running;
    }
    return total - (_unplayed[id] ?? 0);
  }

  int _headToHead(String id, List<String> group) {
    final tied = group.toSet();
    var balance = 0;
    for (final g in played(id)) {
      if (!tied.contains(g.opponent)) continue;
      balance += g.result == 2 ? 1 : (g.result == 0 ? -1 : 0);
    }
    return balance;
  }

  int _rating(String id) => event.player(id).effectivePairingRating;

  int _opponentsPerformance(String id, List<String> group) {
    final tied = group.toSet();
    final performances = <int>[];
    for (final g in played(id)) {
      final opponent = g.opponent;
      final credits = <int>[];
      for (final game in played(opponent)) {
        if (tied.contains(opponent) && tied.contains(game.opponent)) continue;
        final rating = _rating(game.opponent);
        if (rating <= 0) continue;
        credits.add(rating + const [-400, 0, 400][game.result]);
      }
      if (credits.isNotEmpty) performances.add(_average(credits));
    }
    return _average(performances);
  }

  int _average(Iterable<int> values) {
    final list = values.toList();
    if (list.isEmpty) return 0;
    return (list.fold(0, (sum, v) => sum + v) / list.length).round();
  }

  /// FNV-1a over the event and player IDs, as a six-digit lot.
  int _coin(String id) {
    var hash = 0x811c9dc5;
    for (final unit in '${event.id}/$id'.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash % 1000000;
  }
}

String _halves(int n) => n == 1
    ? '½'
    : n.isOdd
    ? '${n ~/ 2}½'
    : '${n ~/ 2}';

String _quarters(int n) {
  final whole = n ~/ 4, part = const ['', '¼', '½', '¾'][n % 4];
  return whole == 0 && part.isNotEmpty ? part : '$whole$part';
}
