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
        scores[g.white] = scores[g.white]! + outcome.whiteScore;
        scores[g.black] = scores[g.black]! + outcome.blackScore;
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
  rows.sort((a, b) {
    for (final c in [
      b.points.compareTo(a.points),
      b.buchholz.compareTo(a.buchholz),
      b.sonneborn.compareTo(a.sonneborn),
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
    if (i > 0 &&
        (row.points != rows[i - 1].points ||
            row.buchholz != rows[i - 1].buchholz ||
            row.sonneborn != rows[i - 1].sonneborn)) {
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
