import 'package:flutter/services.dart';
import '../domain/model.dart';

/// Scores are commands for the focused player. D is the only draw key.
/// F marks the focused player as a no-show (forfeit loss); F on both
/// players of a board is a double forfeit. X is a forfeit win. + and -
/// (number row or numpad) are the older forfeit win and loss keys, P marks
/// the game still playing and ? disputed.
///
/// F on a box that already shows a forfeit win means double forfeit. The
/// stored result cannot say whether that win came from the opponent's F or
/// a mistaken X on this box, so after a mistaken X correct with L, 0 or
/// Delete rather than F.
Outcome? resultFromKey(
  KeyEvent event, {
  required bool white,
  Outcome current = Outcome.unreported,
}) {
  final key = event.logicalKey;
  final wins = white ? Outcome.whiteWin : Outcome.blackWin;
  final loses = white ? Outcome.blackWin : Outcome.whiteWin;
  final winsByForfeit = white ? Outcome.whiteForfeit : Outcome.blackForfeit;
  final forfeits = white ? Outcome.blackForfeit : Outcome.whiteForfeit;
  if (key == LogicalKeyboardKey.keyD) return Outcome.draw;
  if ([
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.keyW,
  ].contains(key)) {
    return wins;
  }
  if ([
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.keyL,
  ].contains(key)) {
    return loses;
  }
  if (key == LogicalKeyboardKey.keyF) {
    // The opponent was already marked absent: neither player showed.
    return current == winsByForfeit || current == Outcome.doubleForfeit
        ? Outcome.doubleForfeit
        : forfeits;
  }
  if (key == LogicalKeyboardKey.keyX ||
      event.character == '+' ||
      key == LogicalKeyboardKey.numpadAdd) {
    return winsByForfeit;
  }
  if (event.character == '-' || key == LogicalKeyboardKey.numpadSubtract) {
    return forfeits;
  }
  if (key == LogicalKeyboardKey.keyP) return Outcome.unfinished;
  if (event.character == '?') return Outcome.disputed;
  if ([LogicalKeyboardKey.delete, LogicalKeyboardKey.backspace].contains(key)) {
    return Outcome.unreported;
  }
  return null;
}

const resultKeyHint =
    '1 / W win · 0 / L loss · D draw · F no-show · X forfeit win';

/// The other result keys, shown when a key that is not a result is typed.
const moreResultKeys = '+ forfeit win · − no-show · P playing · ? disputed';

/// Moving and acting in the results grid.
const gridKeyHint = 'Enter skip · F2 correct · Space player details';
