import 'model.dart';

class Standing {
  const Standing(
    this.player,
    this.points,
    this.buchholz,
    this.sonneborn,
    this.played, {
    this.rank = 0,
  });
  final Player player;
  final int points, buchholz, sonneborn, played, rank;
}

/// Buchholz includes played opponents only; SB is in quarter-point units.
/// Forfeits and byes contribute points, never fictional opponents.
List<Standing> standings(
  Event event,
  Section section, {
  bool forPairing = false,
  bool forPrizes = false,
}) {
  final excluded = <String>{};
  if (forPrizes && section.format != Format.swiss) {
    final scheduled = section.plannedRounds * (section.doubleGames ? 2 : 1);
    for (final id in section.players) {
      final played = section.rounds
          .expand((r) => r.games)
          .where((g) => g.outcome.played && (g.white == id || g.black == id))
          .length;
      if (event.player(id).withdrawn && played * 2 < scheduled) {
        excluded.add(id);
      }
    }
  }
  bool contributes(Game g) =>
      !excluded.contains(g.white) && !excluded.contains(g.black);
  final scores = <String, int>{for (final p in event.players) p.id: 0};
  for (final s in event.sections) {
    for (final r in s.rounds) {
      for (final b in r.byes) {
        scores[b.player] = scores[b.player]! + b.points;
      }
      for (final g in r.games) {
        if (!contributes(g)) continue;
        final outcome = forPairing && !g.outcome.resolved
            ? g.pairingAssumption ?? g.outcome
            : g.outcome;
        scores[g.white] = scores[g.white]! + s.scoring.points(outcome, true);
        scores[g.black] = scores[g.black]! + s.scoring.points(outcome, false);
      }
    }
  }
  final rows = section.players.where((id) => !excluded.contains(id)).map((id) {
    var bh = 0, sb = 0, played = 0;
    for (final g in event.games.where(
      (g) =>
          g.outcome.played &&
          contributes(g) &&
          (g.white == id || g.black == id),
    )) {
      final opponent = g.white == id ? g.black : g.white;
      bh += scores[opponent]!;
      sb +=
          scores[opponent]! *
          (g.white == id ? g.outcome.whiteScore : g.outcome.blackScore);
      played++;
    }
    return Standing(event.player(id), scores[id]!, bh, sb, played);
  }).toList();
  List<int> tieValues(Standing r) => switch (section.tiebreakOrder) {
    TiebreakOrder.buchholzSonneborn => [r.buchholz, r.sonneborn],
    TiebreakOrder.sonnebornBuchholz => [r.sonneborn, r.buchholz],
    TiebreakOrder.buchholz => [r.buchholz],
    TiebreakOrder.scoreOnly => [],
  };
  bool tied(Standing a, Standing b) {
    final av = tieValues(a), bv = tieValues(b);
    return a.points == b.points &&
        List.generate(av.length, (i) => av[i] == bv[i]).every((v) => v);
  }

  rows.sort((a, b) {
    final av = tieValues(a), bv = tieValues(b);
    for (final c in [
      b.points.compareTo(a.points),
      for (var i = 0; i < av.length; i++) bv[i].compareTo(av[i]),
      a.player.name.compareTo(b.player.name),
      a.player.id.compareTo(b.player.id),
    ]) {
      if (c != 0) return c;
    }
    return 0;
  });
  var rank = 1;
  final ranked = <Standing>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (i > 0 && !tied(row, rows[i - 1])) {
      rank = i + 1;
    }
    ranked.add(
      Standing(
        row.player,
        row.points,
        row.buchholz,
        row.sonneborn,
        row.played,
        rank: rank,
      ),
    );
  }
  return ranked;
}
