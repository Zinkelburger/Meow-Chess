import 'model.dart';

/// A game won by the lower-rated player.
class Upset {
  const Upset({
    required this.round,
    required this.board,
    required this.winner,
    required this.loser,
    required this.gap,
  });
  final int round, board;
  final Player winner, loser;

  /// How many rating points the winner gave away.
  final int gap;

  /// The upset in words: `Ann Lee (1450) beat Bob Roy (1810) in round 3,
  /// 360 points`.
  String get text =>
      '${winner.name} (${winner.effectivePairingRating}) beat ${loser.name} '
      '(${loser.effectivePairingRating}) in round $round, $gap points';
}

/// The upsets of [section], the biggest first and then the earliest: every
/// played win by the lower-rated of two rated players. A forfeit is not an
/// upset, a draw is not a win, and an unrated player has no rating to be
/// upset by. For an upset prize the director announced; the prize table
/// does not award it.
///
/// Ratings are the players' pairing ratings as the event holds them now:
/// the event keeps no rating per game, so refreshing ratings mid-event
/// measures earlier upsets by the new ratings too.
List<Upset> sectionUpsets(Event event, Section section) {
  if (section.format == Format.bughouse) return const [];
  final upsets = <Upset>[];
  for (final r in section.rounds) {
    for (final g in r.games) {
      if (g.outcome != Outcome.whiteWin && g.outcome != Outcome.blackWin) {
        continue;
      }
      final white = event.player(g.white), black = event.player(g.black);
      final winner = g.outcome == Outcome.whiteWin ? white : black;
      final loser = identical(winner, white) ? black : white;
      if (winner.unrated || loser.unrated) continue;
      final gap = loser.effectivePairingRating - winner.effectivePairingRating;
      if (gap <= 0) continue;
      upsets.add(
        Upset(
          round: r.number,
          board: g.board,
          winner: winner,
          loser: loser,
          gap: gap,
        ),
      );
    }
  }
  return upsets..sort(
    (a, b) => a.gap != b.gap
        ? b.gap.compareTo(a.gap)
        : a.round != b.round
        ? a.round.compareTo(b.round)
        : a.board.compareTo(b.board),
  );
}

/// The biggest upset of [section], with any other of the same size.
List<Upset> biggestUpsets(Event event, Section section) {
  final all = sectionUpsets(event, section);
  return [
    for (final u in all)
      if (u.gap == all.first.gap) u,
  ];
}
