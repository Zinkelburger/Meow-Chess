import 'package:flutter/services.dart';
import '../domain/model.dart';

/// Scores are commands for the focused player. D is the only draw key.
///
/// F is the only forfeit key: F marks the focused player as a no-show (0F,
/// the opponent wins 1F), and F on the other player of that board as well
/// makes it a double forfeit. A forfeit is only ever won or lost, so on a
/// forfeit board 1 and 0 say who won it (1 on one player of a double
/// forfeit turns it back into a single forfeit), while D, P and ? are
/// refused (see [refusedOnForfeit]). Delete clears the result, after which
/// 1, 0 and D record a played game again.
Outcome? resultFromKey(
  KeyEvent event, {
  required bool white,
  Outcome current = Outcome.unreported,
}) {
  final key = event.logicalKey;
  final forfeitBoard = isForfeit(current);
  final wins = white ? Outcome.whiteWin : Outcome.blackWin;
  final loses = white ? Outcome.blackWin : Outcome.whiteWin;
  final winsByForfeit = white ? Outcome.whiteForfeit : Outcome.blackForfeit;
  final forfeits = white ? Outcome.blackForfeit : Outcome.whiteForfeit;
  if (key == LogicalKeyboardKey.keyF) {
    // The opponent was already marked absent: neither player showed.
    return current == winsByForfeit || current == Outcome.doubleForfeit
        ? Outcome.doubleForfeit
        : forfeits;
  }
  if ([
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.keyW,
  ].contains(key)) {
    return forfeitBoard ? winsByForfeit : wins;
  }
  if ([
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.keyL,
  ].contains(key)) {
    return forfeitBoard ? forfeits : loses;
  }
  if ([LogicalKeyboardKey.delete, LogicalKeyboardKey.backspace].contains(key)) {
    return Outcome.unreported;
  }
  if (forfeitBoard) return null;
  if (key == LogicalKeyboardKey.keyD) return Outcome.draw;
  if (key == LogicalKeyboardKey.keyP) return Outcome.unfinished;
  if (event.character == '?') return Outcome.disputed;
  return null;
}

/// A forfeit board: one player won by forfeit, or neither showed.
bool isForfeit(Outcome o) => const {
  Outcome.whiteForfeit,
  Outcome.blackForfeit,
  Outcome.doubleForfeit,
}.contains(o);

/// A result key that has no forfeit meaning: there is no half-point,
/// still-playing or disputed forfeit.
bool refusedOnForfeit(KeyEvent event, Outcome current) =>
    isForfeit(current) &&
    (event.logicalKey == LogicalKeyboardKey.keyD ||
        event.logicalKey == LogicalKeyboardKey.keyP ||
        event.character == '?');

/// What the keys do on a forfeit board, from the focused player's side.
String forfeitKeyHint(Outcome current, {required bool white}) {
  if (current == Outcome.doubleForfeit) {
    return 'Double forfeit · 1 gives this player the forfeit win · Delete clears';
  }
  final forfeited =
      current == (white ? Outcome.blackForfeit : Outcome.whiteForfeit);
  return forfeited
      ? 'Forfeit · F on the other player makes it a double forfeit · 1 gives this player the win · Delete clears'
      : 'Forfeit · F here makes it a double forfeit · 0 gives the win to the other player · Delete clears';
}

const resultKeyHint =
    '1 / W win · 0 / L loss · D draw · F no-show (F on both: double forfeit)';

/// The other result keys, shown when a key that is not a result is typed.
const moreResultKeys = 'P playing · ? disputed · Delete clears';

/// Moving and acting in the results grid.
const gridKeyHint = 'Enter skip · F2 correct · Space player details';
