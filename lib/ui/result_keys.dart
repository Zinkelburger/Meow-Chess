import 'package:flutter/services.dart';
import '../domain/model.dart';

/// Scores are commands for the focused player. D is the only draw key.
Outcome? resultFromKey(
  KeyEvent event, {
  required bool white,
  bool forfeit = false,
}) {
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.keyD) return forfeit ? null : Outcome.draw;
  if ([
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.keyW,
  ].contains(key)) {
    return white
        ? (forfeit ? Outcome.whiteForfeit : Outcome.whiteWin)
        : (forfeit ? Outcome.blackForfeit : Outcome.blackWin);
  }
  if ([
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.keyL,
  ].contains(key)) {
    return white
        ? (forfeit ? Outcome.blackForfeit : Outcome.blackWin)
        : (forfeit ? Outcome.whiteForfeit : Outcome.whiteWin);
  }
  if (event.character == '+' || key == LogicalKeyboardKey.numpadAdd) {
    return white ? Outcome.whiteForfeit : Outcome.blackForfeit;
  }
  if (event.character == '-' || key == LogicalKeyboardKey.numpadSubtract) {
    return white ? Outcome.blackForfeit : Outcome.whiteForfeit;
  }
  if (key == LogicalKeyboardKey.keyX) return Outcome.doubleForfeit;
  if (key == LogicalKeyboardKey.keyP) return Outcome.unfinished;
  if (event.character == '?') return Outcome.disputed;
  if ([LogicalKeyboardKey.delete, LogicalKeyboardKey.backspace].contains(key)) {
    return Outcome.unreported;
  }
  return null;
}

const resultKeyHint = '1 / W win · 0 / L loss · D draw';
