import '../domain/model.dart';
import 'player_format.dart';

/// What one player's score box shows for a game: 1, 0, ½, or blank, and
/// the US Chess letters for unplayed games: X won by forfeit, F forfeited.
String scoreMark(Outcome o, {required bool white}) => switch (o) {
  Outcome.unreported => '',
  Outcome.draw => '½',
  Outcome.unfinished => '',
  Outcome.disputed => '?',
  Outcome.doubleForfeit => 'F',
  _ when !o.played => (white ? o.whiteScore : o.blackScore) == 2 ? 'X' : 'F',
  _ => (white ? o.whiteScore : o.blackScore) == 2 ? '1' : '0',
};

/// A bye as US Chess crosstables print it: B full point, H half point,
/// U zero (unpaired), with dashes where an opponent number would be.
String byeMark(int points) => switch (points) {
  2 => 'B---',
  1 => 'H---',
  _ => 'U---',
};

/// Half-points as words: "½ point", "1 point", "2½ points".
String pointsText(int n) =>
    '${halves(n)} ${n == 1 || n == 2 ? 'point' : 'points'}';

/// Each player's score, in half-points, before round [number] of [s].
Map<String, int> scoresBefore(Section s, int number) {
  final scores = <String, int>{for (final id in s.players) id: 0};
  for (final r in s.rounds.where((r) => r.number < number)) {
    for (final b in r.byes) {
      scores[b.player] = (scores[b.player] ?? 0) + b.points;
    }
    for (final g in r.games) {
      scores[g.white] = (scores[g.white] ?? 0) + g.outcome.whiteScore;
      scores[g.black] = (scores[g.black] ?? 0) + g.outcome.blackScore;
    }
  }
  return scores;
}
