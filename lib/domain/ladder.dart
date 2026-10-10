import 'model.dart';

/// The club ladder: a standing list where a player challenges someone above
/// them for their place (rule 29L1 TD TIP calls it "the traditional club
/// ladder system"). It has no planned rounds; games are recorded whenever
/// they happen.
///
/// Positions are the order of [Section.players] (index 0 is #1). The house
/// rules are fixed and announced on the ladder itself:
///
/// * a player may challenge anyone up to [ladderChallengeRange] places above
///   them;
/// * if the challenger wins (including a win by forfeit), they take the
///   loser's place and everyone between, the loser included, moves down one;
/// * a draw, a loss or a double forfeit changes nothing;
/// * a declined challenge is not recorded.
///
/// Games are stored in rounds so results, history, printing and the rating
/// report keep working: each round is one batch of challenge games in which
/// every player appears at most once, and [Section.plannedRounds] is the
/// most batches the ladder may hold ([ladderDefaultBatches] by default).
/// The ladder is reordered once, when the game is recorded; a later result
/// correction leaves the order to the director (see `setLadderOrder`).
const ladderChallengeRange = 2;
const ladderDefaultBatches = 32;

/// The ladder from the top: player IDs in position order.
List<String> ladderPositions(Section section) => section.players;

/// [id]'s place on the ladder (1 = top), or null when not on it.
int? ladderPosition(Section section, String id) {
  final index = section.players.indexOf(id);
  return index < 0 ? null : index + 1;
}

/// Why [challenger] may not challenge [defender] on [section], or null when
/// the challenge is allowed. Names are resolved by [name] for the message.
String? ladderChallengeAllowed(
  Section section,
  String challenger,
  String defender, {
  String Function(String id)? name,
}) {
  String who(String id) => name?.call(id) ?? id;
  if (challenger == defender) return 'Choose two different players.';
  final from = ladderPosition(section, challenger);
  final to = ladderPosition(section, defender);
  if (from == null) return '${who(challenger)} is not on this ladder.';
  if (to == null) return '${who(defender)} is not on this ladder.';
  if (to >= from) {
    return '${who(defender)} is below ${who(challenger)} on the ladder: a player may only challenge upward.';
  }
  if (from - to > ladderChallengeRange) {
    return '${who(defender)} is ${from - to} places above ${who(challenger)}; a challenge reaches at most $ladderChallengeRange places up.';
  }
  return null;
}

/// The players [challenger] may challenge right now, nearest first.
List<String> ladderDefenders(Section section, String challenger) => [
  for (final id in section.players.reversed)
    if (ladderChallengeAllowed(section, challenger, id) == null) id,
];

/// How a challenge ended, from the challenger's side. Each value's [name]
/// is its tool wire format.
enum ChallengeResult {
  win,
  draw,
  loss,
  forfeitWin,
  forfeitLoss,
  doubleForfeit;

  /// The game outcome, given who had White.
  Outcome outcome({required bool challengerWhite}) => switch (this) {
    win => challengerWhite ? Outcome.whiteWin : Outcome.blackWin,
    draw => Outcome.draw,
    loss => challengerWhite ? Outcome.blackWin : Outcome.whiteWin,
    forfeitWin => challengerWhite ? Outcome.whiteForfeit : Outcome.blackForfeit,
    forfeitLoss =>
      challengerWhite ? Outcome.blackForfeit : Outcome.whiteForfeit,
    doubleForfeit => Outcome.doubleForfeit,
  };

  /// The result called [name], refusing any other value plainly.
  static ChallengeResult parse(String name) =>
      values.where((r) => r.name == name).firstOrNull ??
      (throw TournamentException(
        'Unknown result "$name". Choose ${values.map((r) => r.name).join(', ')}.',
      ));
}

/// A challenge game. The challenger has Black unless [challengerWhite].
Game ladderGame({
  required String id,
  required String challenger,
  required String defender,
  required int board,
  Outcome outcome = Outcome.unreported,
  bool challengerWhite = false,
  String note = '',
}) => Game(
  id: id,
  white: challengerWhite ? challenger : defender,
  black: challengerWhite ? defender : challenger,
  board: board,
  outcome: outcome,
  note: note,
);

/// The challenger of [game] on [section]: the lower-placed of its players.
/// Null when either player is off the ladder.
String? ladderChallenger(Section section, Game game) {
  final white = ladderPosition(section, game.white);
  final black = ladderPosition(section, game.black);
  if (white == null || black == null) return null;
  return white > black ? game.white : game.black;
}

/// Whether [game]'s challenger took the place: a win, by play or forfeit.
bool ladderChallengerWon(Section section, Game game) {
  final challenger = ladderChallenger(section, game);
  if (challenger == null) return false;
  return game.white == challenger
      ? game.outcome.whiteScore == 2
      : game.outcome.blackScore == 2;
}

/// The ladder after [game]: the challenger moves into the defender's place
/// on a win and everyone from the defender down to the challenger's old
/// place moves down one; otherwise the order is unchanged.
List<String> ladderAfterResult(Section section, Game game) {
  final order = [...section.players];
  if (!ladderChallengerWon(section, game)) return order;
  final challenger = ladderChallenger(section, game)!;
  final defender = challenger == game.white ? game.black : game.white;
  final to = order.indexOf(defender);
  order
    ..remove(challenger)
    ..insert(to, challenger);
  return order;
}

/// What changed between two orders of the same ladder, for history:
/// "Alex Chen up to #3, Bo Li down to #4, Cy Dee down to #5", or
/// "no change on the ladder".
String ladderMoves(
  List<String> before,
  List<String> after,
  String Function(String id) name,
) {
  final moves = <String>[];
  for (final (i, id) in after.indexed) {
    final was = before.indexOf(id);
    if (was < 0 || was == i) continue;
    moves.add('${name(id)} ${was > i ? 'up' : 'down'} to #${i + 1}');
  }
  return moves.isEmpty ? 'no change on the ladder' : moves.join(', ');
}

/// Resolved challenge games of [id] on [section], oldest first.
List<Game> ladderGames(Section section, String id) => [
  for (final r in section.rounds)
    for (final g in r.games)
      if ((g.white == id || g.black == id) && g.outcome.resolved) g,
];

/// A score from one player's side: "1–0", "½–½", "0–1", "1–0 (forfeit)".
/// [fromWhite] says which side is reading it.
String ladderScoreLabel(Outcome outcome, {required bool fromWhite}) {
  final mine = fromWhite ? outcome.whiteScore : outcome.blackScore;
  final theirs = fromWhite ? outcome.blackScore : outcome.whiteScore;
  String half(int n) => n == 2
      ? '1'
      : n == 1
      ? '½'
      : '0';
  final forfeit = const {
    Outcome.whiteForfeit,
    Outcome.blackForfeit,
    Outcome.doubleForfeit,
  }.contains(outcome);
  return '${half(mine)}–${half(theirs)}${forfeit ? ' (forfeit)' : ''}';
}

/// [id]'s last result on the ladder from their own side ("1–0 v. Bo Li",
/// "½–½ v. Cy Dee"), or an empty string before their first game.
String ladderLastResult(
  Section section,
  String id,
  String Function(String id) name,
) {
  final game = ladderGames(section, id).lastOrNull;
  if (game == null) return '';
  final white = game.white == id;
  return '${ladderScoreLabel(game.outcome, fromWhite: white)} v. ${name(white ? game.black : game.white)}';
}

/// Why [order] is not a reordering of [section]'s ladder, or null.
String? ladderOrderProblem(Section section, List<String> order) {
  if (order.toSet().length != order.length) {
    return 'A player is listed twice.';
  }
  if (order.length != section.players.length ||
      !section.players.every(order.contains)) {
    return 'List every player of the ladder exactly once.';
  }
  return null;
}
