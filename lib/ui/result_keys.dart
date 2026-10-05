import 'package:flutter/services.dart';
import '../domain/model.dart';

/// Scores are commands for the focused player. D is the only draw key.
/// F marks the focused player as a no-show (forfeit loss); F on both
/// players of a board is a double forfeit. X is a forfeit win.
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

const resultKeyHint = '1 / W win · 0 / L loss · D draw · F no-show';
