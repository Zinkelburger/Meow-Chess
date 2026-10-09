import 'model.dart';
import 'fixed_schedule.dart';
import 'tiebreaks.dart';

export 'tiebreaks.dart';

class Standing {
  const Standing(
    this.player,
    this.points,
    this.buchholz,
    this.sonneborn,
    this.played, {
    this.rank = 0,
    this.tiebreaks = const [],
  });
  final Player player;

  /// [buchholz] is the played opponents' final scores (half-points) and
  /// [sonneborn] is Sonneborn–Berger in quarter-points, kept for callers
  /// that print them; the ranking itself uses [tiebreaks].
  final int points, buchholz, sonneborn, played, rank;

  /// Rule 34: the posted tie-break methods, in order, with this row's value
  /// for each. Empty when the row was built without them.
  final List<TiebreakValue> tiebreaks;

  Standing withRank(int rank) => Standing(
    player,
    points,
    buchholz,
    sonneborn,
    played,
    rank: rank,
    tiebreaks: tiebreaks,
  );

  /// The value of one method, or null when it is not in the posted order.
  TiebreakValue? tiebreak(TiebreakMethod method) =>
      tiebreaks.where((t) => t.method == method).firstOrNull;
}

/// The tie-break methods [section] ranks by, in posted order (rule 34B).
List<TiebreakMethod> standingsTiebreaks(Event event, Section section) =>
    sectionTiebreaks(event, pairingFormat(section));

/// Whether two adjacent rows share a place: equal points and, when
/// [tiebreaks] rank, equal on every posted method.
bool sharePlace(Standing a, Standing b, {required bool tiebreaks}) {
  if (a.points != b.points) return false;
  if (!tiebreaks) return true;
  if (a.tiebreaks.length != b.tiebreaks.length) return false;
  for (var i = 0; i < a.tiebreaks.length; i++) {
    if (a.tiebreaks[i].value != b.tiebreaks[i].value) return false;
  }
  return true;
}

/// Number sorted [rows] 1, 2, 2, 4 … sharing a place per [sharePlace].
List<Standing> rankStandings(List<Standing> rows, {required bool tiebreaks}) {
  final ranked = <Standing>[];
  var rank = 1;
  for (var i = 0; i < rows.length; i++) {
    if (i > 0 && !sharePlace(rows[i], rows[i - 1], tiebreaks: tiebreaks)) {
      rank = i + 1;
    }
    ranked.add(rows[i].withRank(rank));
  }
  return ranked;
}

/// Points first, then the posted rule 34 tie-breaks in order when the event
/// ranks by them (or when pairing asks). Forfeits and byes contribute
/// points, never fictional opponents; the tie-break adjustments for
/// unplayed games are rule 34E1's and 34E3's.
List<Standing> standings(
  Event event,
  Section section, {
  bool forPairing = false,
  bool forPrizes = false,
}) {
  final excluded = <String>{};
  if (forPrizes &&
      !section.sideGames &&
      section.players.length >= 2 &&
      pairingFormat(section) != Format.swiss) {
    // Count actual opponents in the planned schedule; odd fields have sit-outs.
    final scheduled = <String, int>{for (final id in section.players) id: 0};
    for (final round in sectionSchedule(section).take(section.plannedRounds)) {
      for (final (white, black) in round) {
        if (white == null || black == null) continue;
        final games = section.doubleGames ? 2 : 1;
        scheduled[white] = scheduled[white]! + games;
        scheduled[black] = scheduled[black]! + games;
      }
    }
    for (final id in section.players) {
      final played = section.rounds
          .expand((r) => r.games)
          .where((g) => g.outcome.played && (g.white == id || g.black == id))
          .length;
      if (event.player(id).withdrawn && played * 2 < scheduled[id]!) {
        excluded.add(id);
      }
    }
  }
  bool contributes(Game g) =>
      !excluded.contains(g.white) && !excluded.contains(g.black);
  // Rule 15I / 22C5: prizes may count a different result from the one on
  // the wall chart and the rating report.
  Outcome outcomeOf(Game g) => forPairing && !g.outcome.resolved
      ? g.pairingAssumption ?? g.outcome
      : forPrizes
      ? g.prizeOutcome ?? g.outcome
      : g.outcome;
  final scores = <String, int>{for (final p in event.players) p.id: 0};
  for (final s in event.sections) {
    for (final r in s.rounds) {
      for (final b in r.byes) {
        scores[b.player] = scores[b.player]! + b.points;
      }
      for (final g in r.games) {
        if (!contributes(g)) continue;
        final outcome = outcomeOf(g);
        scores[g.white] = scores[g.white]! + outcome.whiteScore;
        scores[g.black] = scores[g.black]! + outcome.blackScore;
      }
    }
  }
  final ids = section.players.where((id) => !excluded.contains(id)).toList();
  final methods = standingsTiebreaks(event, section);
  final values = tiebreakValues(
    event: event,
    section: section,
    players: ids,
    methods: methods,
    scores: scores,
    outcomeOf: outcomeOf,
    counts: contributes,
  );
  final rows = ids.map((id) {
    var bh = 0, sb = 0, played = 0;
    for (final g in event.games.where(
      (g) =>
          contributes(g) &&
          outcomeOf(g).played &&
          (g.white == id || g.black == id),
    )) {
      final opponent = g.white == id ? g.black : g.white;
      final outcome = outcomeOf(g);
      bh += scores[opponent]!;
      sb +=
          scores[opponent]! *
          (g.white == id ? outcome.whiteScore : outcome.blackScore);
      played++;
    }
    return Standing(
      event.player(id),
      scores[id]!,
      bh,
      sb,
      played,
      tiebreaks: values[id]!,
    );
  }).toList();
  final ranked = event.useTiebreaks || forPairing;
  rows.sort((a, b) {
    for (final c in [
      b.points.compareTo(a.points),
      if (ranked)
        for (var i = 0; i < methods.length; i++)
          b.tiebreaks[i].value.compareTo(a.tiebreaks[i].value),
      a.player.name.compareTo(b.player.name),
      a.player.id.compareTo(b.player.id),
    ]) {
      if (c != 0) return c;
    }
    return 0;
  });
  return rankStandings(rows, tiebreaks: ranked);
}
