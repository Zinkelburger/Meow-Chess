import '../domain/model.dart';
import '../domain/reentry.dart';
import '../infrastructure/reports.dart' show cumulativeScores;
import 'player_format.dart';

// The crosstable's bye mark: one rule for the screen and the reports.
export '../infrastructure/reports.dart' show byeMark;

/// What one player's score box shows for a game: 1, 0, ½, or blank, and
/// the US Chess letters for unplayed games: X won by forfeit, F forfeited.
String scoreMark(Outcome o, {required bool white}) => switch (o) {
  Outcome.unreported => '',
  Outcome.draw => '½',
  Outcome.unfinished => '',
  Outcome.disputed => '?',
  Outcome.doubleForfeit => 'F',
  _ when !o.played => (white ? o.whiteScore : o.blackScore) == 2 ? 'X' : 'F',
  _ => const ['0', '½', '1'][white ? o.whiteScore : o.blackScore],
};

/// A game's result as a TD writes it, White first: 1–0, ½–½, 0–1, with F
/// for a side that forfeited (1–F, F–1, F–F), and words while there is none.
String resultText(Outcome o) => switch (o) {
  Outcome.unreported => 'no result',
  Outcome.unfinished => 'still playing',
  Outcome.disputed => 'disputed',
  _ => '${scoreMark(o, white: true)}–${scoreMark(o, white: false)}'.replaceAll(
    'X',
    '1',
  ),
};

/// What replacing a recorded result did, for the notice that offers Undo:
/// "Board 7 was 1–0, now ½–½".
String resultChangeText(int board, Outcome before, Outcome now) =>
    'Board $board was ${resultText(before)}, now ${resultText(now)}';

/// Half-points as words: "½ point", "1 point", "2½ points".
String pointsText(int n) =>
    '${halves(n)} ${n == 1 || n == 2 ? 'point' : 'points'}';

/// Each player's score, in half-points, before round [number] of [s]: the
/// wall chart's running total after the round before ([cumulativeScores]),
/// so bughouse partners and 28S5 re-entries count as the standings count
/// them. Players paired in [s] who have since left it are included.
Map<String, int> scoresBefore(Event e, Section s, int number) {
  final carries = reentryCarries(e, s);
  final earlier = s.rounds.where((r) => r.number < number).length;
  final ids = {
    ...s.players,
    for (final r in s.rounds) ...[
      for (final g in r.games) ...[g.white, g.black],
      for (final b in r.byes) b.player,
    ],
  };
  return {
    for (final id in ids)
      id: earlier == 0
          ? 0
          : cumulativeScores(e, s, id, carries: carries)[earlier - 1],
  };
}
