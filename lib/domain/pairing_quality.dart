import 'fixed_schedule.dart';
import 'model.dart';
import 'pairing.dart' show pairingRestricted;

/// A count out of the number it could have been: `18 of 20`.
typedef Tally = ({int count, int of});

/// How one Swiss round's pairings came out, worked out afterwards from the
/// posted round and the results before it. It measures the pairings; it
/// does not say why the pairing program chose them (the round's own
/// explanations do that).
class RoundQuality {
  const RoundQuality({
    required this.round,
    required this.boards,
    required this.sameScore,
    required this.colorsDue,
    required this.thirdInRow,
    required this.imbalance,
    required this.repeatFloats,
    required this.rematches,
    required this.teammates,
    required this.requests,
  });
  final int round, boards;

  /// Boards whose two players had the same score before the round.
  final Tally sameScore;

  /// Players who had a color due (29E4: equalize, then alternate) and got
  /// it. Two players due the same color cannot both have it.
  final Tally colorsDue;

  /// Players given the same color for a third game running, out of all
  /// players seated (29E5f).
  final Tally thirdInRow;

  /// Players two or more games out of balance after the round (29E5b).
  final Tally imbalance;

  /// Players paired out of their score group in the same direction as in
  /// the round before, out of those paired out of their group this round.
  final Tally repeatFloats;

  /// Boards that repeat an earlier game (27A1).
  final Tally rematches;

  /// Boards that pair team-mates, when the section avoids them (28N).
  final Tally? teammates;

  /// Boards that pair two players who asked not to meet.
  final Tally requests;

  /// Players paired against another score group.
  int get floats => (boards - sameScore.count) * 2;
}

/// Every posted round of a Swiss section, and the section's totals.
class SectionQuality {
  const SectionQuality(this.sectionId, this.name, this.rounds, this.note);
  final String sectionId, name;
  final List<RoundQuality> rounds;

  /// What to keep in mind when reading the figures, or empty.
  final String note;

  /// The section's rounds added together, as round 0.
  RoundQuality get total {
    Tally sum(Tally Function(RoundQuality) pick) => rounds.fold((
      count: 0,
      of: 0,
    ), (t, r) => (count: t.count + pick(r).count, of: t.of + pick(r).of));
    return RoundQuality(
      round: 0,
      boards: rounds.fold(0, (n, r) => n + r.boards),
      sameScore: sum((r) => r.sameScore),
      colorsDue: sum((r) => r.colorsDue),
      thirdInRow: sum((r) => r.thirdInRow),
      imbalance: sum((r) => r.imbalance),
      repeatFloats: sum((r) => r.repeatFloats),
      rematches: sum((r) => r.rematches),
      teammates: rounds.any((r) => r.teammates != null)
          ? sum((r) => r.teammates ?? (count: 0, of: 0))
          : null,
      requests: sum((r) => r.requests),
    );
  }
}

/// The pairing quality of [section], or null when it is not paired round by
/// round as a Swiss (a round robin's schedule leaves nothing to measure).
SectionQuality? pairingQuality(Event event, Section section) {
  if (pairingFormat(section) != Format.swiss ||
      section.sideGames ||
      section.rounds.isEmpty) {
    return null;
  }
  final scores = <String, int>{};
  // Played colors, +1 white and -1 black, oldest first (29E1: an unplayed
  // game gives no color).
  final colors = <String, List<int>>{};
  final met = <String>{};
  // The direction each player left their score group last round: +1 up
  // (met a higher score), -1 down.
  var lastFloat = <String, int>{};
  final rounds = <RoundQuality>[];
  final half = section.doubleGames;
  for (final r in section.rounds) {
    final games = [
      for (final g in r.games)
        if (g.leg == 1) g,
    ];
    var same = 0, due = 0, got = 0, third = 0, off = 0;
    var again = 0, mates = 0, asked = 0, floated = 0, repeated = 0;
    final floats = <String, int>{};
    for (final g in games) {
      final w = scores[g.white] ?? 0, b = scores[g.black] ?? 0;
      if (w == b) {
        same++;
      } else {
        floats[g.white] = w > b ? -1 : 1;
        floats[g.black] = b > w ? -1 : 1;
      }
      if (met.contains(_pair(g))) again++;
      if (pairingRestricted(event, g.white, g.black)) asked++;
      final team = event.player(g.white).team.trim().toLowerCase();
      if (team.isNotEmpty &&
          team == event.player(g.black).team.trim().toLowerCase()) {
        mates++;
      }
    }
    for (final MapEntry(key: id, value: way) in floats.entries) {
      floated++;
      if (lastFloat[id] == way) repeated++;
    }
    lastFloat = floats;
    // Colors count only in sections that give one color a round.
    var seated = 0;
    if (!half) {
      for (final g in games) {
        // The pairing gave these colors whether or not the game was played.
        for (final (id, color) in [(g.white, 1), (g.black, -1)]) {
          seated++;
          final history = colors[id] ?? const <int>[];
          final balance = history.fold(0, (sum, c) => sum + c);
          final last = history.isEmpty ? 0 : history.last;
          final wants = balance < 0
              ? 1
              : balance > 0
              ? -1
              : -last;
          if (wants != 0) {
            due++;
            if (wants == color) got++;
          }
          if (history.length >= 2 &&
              history.last == color &&
              history[history.length - 2] == color) {
            third++;
          }
          if ((balance + color).abs() >= 2) off++;
        }
      }
    }
    rounds.add(
      RoundQuality(
        round: r.number,
        boards: games.length,
        sameScore: (count: same, of: games.length),
        colorsDue: (count: got, of: due),
        thirdInRow: (count: third, of: seated),
        imbalance: (count: off, of: seated),
        repeatFloats: (count: repeated, of: floated),
        rematches: (count: again, of: games.length),
        teammates: section.avoidTeammates
            ? (count: mates, of: games.length)
            : null,
        requests: (count: asked, of: games.length),
      ),
    );
    // Carry this round into the history the next one is measured against.
    for (final g in r.games) {
      scores[g.white] = (scores[g.white] ?? 0) + g.outcome.whiteScore;
      scores[g.black] = (scores[g.black] ?? 0) + g.outcome.blackScore;
      if (g.outcome.played || !g.outcome.resolved) {
        met.add(_pair(g));
        if (!half) {
          (colors[g.white] ??= []).add(1);
          (colors[g.black] ??= []).add(-1);
        }
      }
    }
    for (final b in r.byes) {
      scores[b.player] = (scores[b.player] ?? 0) + b.points;
    }
  }
  return SectionQuality(
    section.id,
    section.name,
    rounds,
    [
      if (section.accelerated != Acceleration.none)
        'Accelerated rounds pair across scores on purpose.',
      if (half) 'Both colors are played each round, so colors are not counted.',
    ].join(' '),
  );
}

String _pair(Game g) => ([g.white, g.black]..sort()).join('|');
