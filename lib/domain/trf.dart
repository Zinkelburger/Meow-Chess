import '../version.dart';
import 'fide.dart';
import 'model.dart';
import 'us_chess.dart';
import 'fide_tiebreaks.dart';
import 'fixed_schedule.dart';
import 'standings.dart' show rankStandings, standings;

/// FIDE's Tournament Report File, version 2026 (TRF26): the file FIDE rates
/// from and the data-exchange format pairing engines read.
///
/// Source: `research/local/fide-trf26-spec.txt` (FIDE Handbook C.02
/// Appendix A, approved 12 May 2025, applied from 1 September 2025).
/// Every record is fixed-column; each line ends with a carriage return.

/// One section's players in pairing-number order, with what each scored.
class TrfTournament {
  TrfTournament._(this.event, this.section, this.players, this.rounds);

  final Event event;
  final Section section;

  /// Starting rank (pairing number) order: C.04.2, by the section's FIDE
  /// ranking rating, then title, then name.
  final List<Player> players;

  /// Each TRF round is one game per player. Double-game rounds become two
  /// TRF rounds (`(round, leg)`), as FIDE rates every game.
  final List<(Round, int)> rounds;

  late final Map<String, int> rankOf = {
    for (final (i, p) in players.indexed) p.id: i + 1,
  };
}

/// The section as TRF sees it. Withdrawn and house players stay listed:
/// they keep their pairing numbers and results.
TrfTournament trfTournament(
  Event event,
  Section section, {
  bool report = false,
}) {
  final players = fidePairingOrder(event, section);
  // The rating report leaves out house players and withdrawn entries that
  // never took part: nobody's results refer to them, and FIDE has nothing
  // to rate.
  if (report) {
    final active = <String>{
      for (final r in section.rounds) ...[
        for (final g in r.games) ...[g.white, g.black],
        for (final b in r.byes)
          if (b.points > 0) b.player,
      ],
    };
    players.retainWhere(
      (p) => active.contains(p.id) || !(p.house || p.withdrawn),
    );
  }
  final rounds = <(Round, int)>[
    for (final r in section.rounds)
      for (var leg = 1; leg <= (section.doubleGames ? 2 : 1); leg++) (r, leg),
  ];
  return TrfTournament._(event, section, players, rounds);
}

/// One player's entry for one TRF round: the opponent's pairing number (0
/// for none), the colour (`w`, `b` or `-`) and the result code.
typedef TrfCell = ({int opponent, String color, String result});

/// [player]'s TRF cell in round [round] leg [leg]. [outcomeOf] chooses which
/// result counts (the reported result, or a pairing assumption).
TrfCell trfCell(
  TrfTournament t,
  Player player,
  Round round,
  int leg,
  Outcome Function(Game) outcomeOf,
) {
  final game = round.games
      .where(
        (g) => g.leg == leg && (g.white == player.id || g.black == player.id),
      )
      .firstOrNull;
  if (game == null) {
    final bye = round.byes.where((b) => b.player == player.id).firstOrNull;
    // A two-game round's bye scores for both games: each leg gets its half.
    final points = bye == null
        ? 0
        : !t.section.doubleGames
        ? bye.points
        : leg == 1
        ? (bye.points + 1) ~/ 2
        : bye.points ~/ 2;
    // The pairing-allocated bye is U whatever it scores (record 162 P).
    final code = bye == null
        ? 'Z'
        : bye.allocated && (points > 0 || t.section.pabPoints == 0)
        ? 'U'
        : switch (points) {
            >= 2 => 'F',
            1 => 'H',
            _ => 'Z',
          };
    return (opponent: 0, color: '-', result: code);
  }
  final white = game.white == player.id;
  final opponent = t.rankOf[white ? game.black : game.white] ?? 0;
  final color = white ? 'w' : 'b';
  final outcome = outcomeOf(game);
  final mine = white ? outcome.whiteScore : outcome.blackScore;
  final result = switch (outcome) {
    // A game that lasted less than one move keeps its result, unrated:
    // W, D, L.
    _ when outcome.played =>
      (game.shortGame ? const ['L', 'D', 'W'] : const ['0', '=', '1'])[mine],
    Outcome.whiteForfeit || Outcome.blackForfeit => mine == 2 ? '+' : '-',
    Outcome.doubleForfeit => '-',
    // C.04.2 3.1: an adjourned game is a draw for pairing purposes.
    Outcome.unfinished => '=',
    // Unresolved games are refused before export; for pairing the caller
    // supplies an assumption.
    _ => '-',
  };
  return (opponent: opponent, color: color, result: result);
}

/// The points a TRF cell is worth, in half-points: standard scoring (TRF
/// record 162 defaults), with [pab] for the pairing-allocated bye.
int trfCellHalves(TrfCell cell, {int pab = 2}) => switch (cell.result) {
  'U' => pab,
  '1' || '+' || 'W' || 'F' => 2,
  '=' || 'D' || 'H' => 1,
  _ => 0,
};

/// One TRF26 record 250: [halves] fictitious points for players
/// [firstPlayer]..[lastPlayer] (starting ranks) in rounds
/// [firstRound]..[lastRound].
typedef TrfAcceleration = ({
  int halves,
  int firstRound,
  int lastRound,
  int firstPlayer,
  int lastPlayer,
});

/// C.04.7 1.2: the last player of the Baku method's group A, the first
/// half of the initial list rounded up to an even number (2 × ⌈n/4⌉ of the
/// players other than house players). Once round 1 is paired the player
/// recorded then holds ([Section.bakuLast], 1.3.2). Null without the Baku
/// acceleration or players.
String? bakuGroupLast(Event event, Section section) {
  if (section.accelerated != 'baku') return null;
  final order = [
    for (final p in fidePairingOrder(event, section))
      if (!p.house) p.id,
  ];
  if (section.bakuLast.isNotEmpty && order.contains(section.bakuLast)) {
    return section.bakuLast;
  }
  final initial = section.rounds.isEmpty || section.fideOrder.isEmpty
      ? order
      : [
          for (final id in section.fideOrder)
            if (!event.player(id).house) id,
        ];
  if (initial.isEmpty) return null;
  final size = 2 * ((initial.length + 3) ~/ 4);
  // The last member of group A, or the nearest member above them still in
  // the section.
  final present = order.toSet();
  final last = initial
      .take(size.clamp(1, initial.length))
      .lastWhere(present.contains, orElse: () => '');
  return last.isEmpty ? null : last;
}

/// C.04.7 1: the Baku Acceleration Method's virtual points for [t], or
/// none when the section does not use it. Group A is everyone ranked up to
/// [bakuGroupLast], so late entries above that player join it (1.3). Group
/// A gets a win's points before the first half (rounded up) of the
/// accelerated rounds, half that before the rest; the accelerated rounds
/// are the first half (rounded up) of the tournament.
List<TrfAcceleration> bakuAccelerations(TrfTournament t) {
  final section = t.section;
  final last = bakuGroupLast(t.event, section);
  if (last == null || t.players.isEmpty) return const [];
  final full = [
    for (final p in fidePairingOrder(t.event, section))
      if (!p.house) p.id,
  ];
  final group = full.take(full.indexOf(last) + 1).toSet();
  final lastRank = t.players.lastIndexWhere((p) => group.contains(p.id)) + 1;
  if (lastRank == 0) return const [];
  final accelerated = (section.plannedRounds + 1) ~/ 2;
  final whole = (accelerated + 1) ~/ 2;
  return [
    (
      halves: 2,
      firstRound: 1,
      lastRound: whole,
      firstPlayer: 1,
      lastPlayer: lastRank,
    ),
    if (accelerated > whole)
      (
        halves: 1,
        firstRound: whole + 1,
        lastRound: accelerated,
        firstPlayer: 1,
        lastPlayer: lastRank,
      ),
  ];
}

String _points(int halves) => '${halves ~/ 2}.${halves.isOdd ? 5 : 0}';

/// The day a round was played, as the TD's clock saw it: rounds are
/// timestamped in UTC, and an evening round in the Americas is already the
/// next day in UTC.
String _roundDate(String? timestamp, String fallback) {
  final at = timestamp == null ? null : DateTime.tryParse(timestamp);
  if (at == null) return _date(fallback);
  final local = at.toLocal();
  return '${local.year.toString().padLeft(4, '0')}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
}

String _date(String iso) =>
    iso.length >= 10 ? iso.substring(0, 10).replaceAll('-', '/') : '';

/// Pads or cuts [text] to exactly [width] characters.
String _fit(String text, int width, {bool right = false}) {
  final t = text.length > width ? text.substring(0, width) : text;
  return right ? t.padLeft(width) : t.padRight(width);
}

/// Writes fixed-column fields into one record. Positions are TRF's 1-based
/// columns.
class _Line {
  _Line(String code) {
    _put(1, code);
  }
  final _chars = <String>[];
  void _put(int at, String text) {
    while (_chars.length < at - 1 + text.length) {
      _chars.add(' ');
    }
    for (var i = 0; i < text.length; i++) {
      _chars[at - 1 + i] = text[i];
    }
  }

  void left(int from, int to, String text) =>
      _put(from, _fit(text, to - from + 1));
  void right(int from, int to, String text) =>
      _put(from, _fit(text, to - from + 1, right: true));
  @override
  String toString() => _chars.join().trimRight();
}

/// An official as records 102 and 112 write them: `Name (FIDE ID)`.
String _official(FideOfficial official) {
  final n = official.name.trim(), i = official.id.trim();
  if (n.isEmpty) return i;
  return i.isEmpty ? n : '$n ($i)';
}

/// TRF record 192 (ETT26): the tournament type. `FIDE_DUTCH` resolves by
/// date to the rules in force (the 2026 rules since 1 February 2026); a
/// round robin from Meow's own tables is `CUSTOM_ROUNDROBIN`.
String trfTournamentType(Section section) => switch (pairingFormat(section)) {
  Format.swiss when section.accelerated == 'baku' => 'FIDE_DUTCH_BAKU',
  Format.swiss => 'FIDE_DUTCH',
  _ => 'CUSTOM_ROUNDROBIN',
};

/// TRF record 222: the time control in seconds, `M/S+I` per period joined
/// by `:` (`G/90 inc/30` is `5400+30`; `40/90, SD/30 inc/30` is
/// `40/5400+30:1800+30`). FIDE counts a delay as an increment, so `d5`
/// writes `+5`. Null when the control cannot be parsed.
String? trfTimeControl(String text) {
  final TimeControl tc;
  try {
    tc = TimeControl.parse(text);
  } on TournamentException {
    return null;
  }
  final bonus = tc.bonusSeconds > 0 ? '+${tc.bonusSeconds}' : '';
  return [
    for (final (moves, minutes) in tc.stages)
      '${moves == null ? '' : '$moves/'}${minutes * 60}$bonus',
  ].join(':');
}

/// Who paired the section, for TRF record 182.
const pairingController = 'Meow-Chess $appVersion, BBP Pairings 6.0.0';

/// The TRF26 text for [section].
///
/// With [pairRound] set, the file is the in-tournament data exchange
/// (ITDX) a pairing engine reads to pair that round: it carries rounds
/// 1..pairRound-1, uses [outcomeOf] for results (pairing assumptions for
/// unreported games) and marks [sittingOut], the players who will not be
/// paired in [pairRound] with the points each one's bye scores (requested
/// byes, withdrawals, house players). Without it, the file is the rating
/// report. [tournament] is the section as TRF sees it, when the caller
/// already has it.
String writeTrf(
  Event event,
  Section section, {
  int? pairRound,
  Outcome Function(Game)? outcomeOf,
  Map<String, int> sittingOut = const {},
  String initialColor = '',
  TrfTournament? tournament,
}) {
  final t =
      tournament ?? trfTournament(event, section, report: pairRound == null);
  final result = outcomeOf ?? (Game g) => g.outcome;
  final rounds = pairRound == null
      ? t.rounds
      : t.rounds.where((r) => r.$1.number < pairRound).toList();
  final category = sectionFideCategory(event, section);
  final fide = event.fide;
  final lines = <String>[];
  void add(String code, String text) =>
      lines.add(text.isEmpty ? code : '$code $text');

  add('012', '${event.name.trim()} – ${section.name.trim()}');
  add('022', event.city.trim());
  add('032', fide.reportFederation);
  add('042', _date(event.date));
  add('052', _date(event.lastDate));
  add('062', '${t.players.length}');
  add('072', '${t.players.where((p) => fideRating(p, category) > 0).length}');
  add('092', switch (pairingFormat(section)) {
    Format.swiss => 'Individual: Swiss-System (Dutch)',
    Format.quad || Format.roundRobin =>
      section.doubleCycle
          ? 'Individual: Double Round-Robin'
          : 'Individual: Round-Robin',
    _ => 'Individual',
  });
  add('102', _official(fide.chiefArbiter));
  for (final d in fide.deputies) {
    final text = _official(d);
    if (text.isNotEmpty) add('112', text);
  }
  add('122', section.effectiveTimeControl(event).trim());
  if (rounds.isNotEmpty) {
    final dates = _Line('132');
    for (final (i, (round, _)) in rounds.indexed) {
      final d = _roundDate(round.startedAt ?? round.postedAt, event.date);
      dates.left(
        92 + 10 * i,
        99 + 10 * i,
        d.length == 10 ? d.substring(2) : '',
      );
    }
    lines.add('$dates');
  }
  add(
    '142',
    '${section.doubleGames ? section.plannedRounds * 2 : section.plannedRounds}',
  );
  if (initialColor.isNotEmpty) add('152', initialColor);
  // Record 162 only when the scoring differs from the default: here, the
  // pairing-allocated bye's value (C.04.1 3).
  if (section.pabPoints != 2) {
    final scoring = _Line('162');
    scoring.left(6, 6, 'P');
    scoring.right(7, 10, _points(section.pabPoints));
    lines.add('$scoring');
  }
  final dual = !section.unrated;
  if (dual) add('172', 'USA ${fideRankingMethod(section)}');
  add('182', pairingController);
  add('192', trfTournamentType(section));
  add('202', fideSectionTiebreaks(event, section).map((m) => m.code).join(','));
  if (trfTimeControl(section.effectiveTimeControl(event)) case final tc?) {
    add('222', tc);
  }

  final cellsFor = <String, List<TrfCell>>{};
  final pointsFor = <String, int>{};
  for (final p in t.players) {
    final cells = [
      for (final (round, leg) in rounds) trfCell(t, p, round, leg, result),
    ];
    cellsFor[p.id] = cells;
    pointsFor[p.id] = cells.fold(
      0,
      (n, c) => n + trfCellHalves(c, pab: section.pabPoints),
    );
  }
  // Rank (86–89): the standings place, ties broken by the section's FIDE
  // tie-breaks (C.07); while pairing, the place by points.
  final place = <String, int>{};
  if (pairRound == null) {
    // Places among the players reported: an entry who never took part is
    // left out of the file, so it holds no place either.
    final rows = [
      for (final row in standings(event, section))
        if (t.rankOf.containsKey(row.player.id)) row,
    ];
    final ranked = event.useTiebreaks || section.fideRated;
    for (final row in rankStandings(rows, tiebreaks: ranked)) {
      place[row.player.id] = row.rank;
    }
  } else {
    final order = [...t.players]
      ..sort((a, b) => pointsFor[b.id]!.compareTo(pointsFor[a.id]!));
    for (final (i, p) in order.indexed) {
      place[p.id] = i > 0 && pointsFor[p.id] == pointsFor[order[i - 1].id]
          ? place[order[i - 1].id]!
          : i + 1;
    }
  }

  for (final p in t.players) {
    final rank = t.rankOf[p.id]!;
    final line = _Line('001');
    line.right(5, 8, '$rank');
    line.left(10, 10, p.sex);
    line.right(11, 13, p.title);
    line.left(15, 47, fideName(p));
    final rating = fideRating(p, category);
    line.right(49, 52, rating > 0 ? '$rating' : '');
    line.left(54, 56, p.federation);
    line.right(58, 68, p.fideId);
    line.left(70, 79, p.birthDate.isEmpty ? '' : trfBirthDate(p.birthDate));
    line.right(81, 84, _points(pointsFor[p.id]!));
    line.right(86, 89, '${place[p.id] ?? ''}');
    for (final (i, cell) in cellsFor[p.id]!.indexed) {
      final at = 92 + 10 * i;
      line.right(at, at + 3, cell.opponent == 0 ? '0000' : '${cell.opponent}');
      line.left(at + 5, at + 5, cell.color);
      line.left(at + 7, at + 7, cell.result);
    }
    if (pairRound != null) {
      // ITDX: who will not be paired in the round being paired.
      final at = 92 + 10 * rounds.length;
      final code = switch (sittingOut[p.id]) {
        null => null,
        2 => 'F',
        1 => 'H',
        _ => 'Z',
      };
      if (code != null) {
        line.right(at, at + 3, '0000');
        line.left(at + 5, at + 5, '-');
        line.left(at + 7, at + 7, code);
      }
    }
    lines.add('$line');
  }

  // National Rating Support: the US Chess rating and ID of every player in
  // a dual-rated section, so the federation and any ranking method can use
  // them.
  if (dual) {
    for (final p in t.players) {
      final line = _Line('USA');
      line.right(5, 8, '${t.rankOf[p.id]}');
      final national = p.effectivePairingRating;
      line.right(49, 52, national > 0 ? '$national' : '');
      line.left(54, 56, p.state);
      line.right(58, 68, p.memberId);
      lines.add('$line');
    }
  }

  // C.04.7: the Baku Acceleration Method, as explicit virtual points.
  for (final a in bakuAccelerations(t)) {
    final line = _Line('250');
    line.right(10, 13, _points(a.halves));
    line.right(15, 17, '${a.firstRound}');
    line.right(19, 21, '${a.lastRound}');
    line.right(23, 26, '${a.firstPlayer}');
    line.right(28, 31, '${a.lastPlayer}');
    lines.add('$line');
  }

  // Do-not-pair requests within the section, for every round.
  if (pairRound != null) {
    final seen = <String>{};
    for (final p in t.players) {
      for (final other in p.avoid) {
        final r = t.rankOf[other];
        if (r == null) continue;
        final key = ([p.id, other]..sort()).join('|');
        if (!seen.add(key)) continue;
        final line = _Line('260');
        line.right(5, 7, '1');
        line.right(9, 11, '${section.plannedRounds}');
        line.right(13, 16, '${t.rankOf[p.id]}');
        line.right(18, 21, '$r');
        lines.add('$line');
      }
    }
  }
  return '${lines.join('\r\n')}\r\n';
}
