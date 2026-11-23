import 'package:flutter/services.dart';
import '../domain/model.dart';

/// The key [event] stands for in the results grid.
///
/// A keyboard layout that types Latin letters is taken at its word: the
/// logical key, so W is wherever that layout puts W (AZERTY, Dvorak). A
/// layout of another script (Cyrillic, Greek, Hebrew, Arabic, Thai) has no
/// W, L, D, F or P at all, so there the key is read by its position on a US
/// keyboard. Punctuation and accented Latin letters never fall back: the
/// key Dvorak types a comma with must not score a win.
LogicalKeyboardKey commandKey(KeyEvent event) {
  final logical = event.logicalKey;
  final printable =
      logical.keyId & LogicalKeyboardKey.planeMask ==
      LogicalKeyboardKey.unicodePlane;
  // Code points below Greek are Latin letters, digits and punctuation.
  if (!printable || logical.keyId < 0x370) return logical;
  return _byPosition[event.physicalKey] ?? logical;
}

final _byPosition = {
  PhysicalKeyboardKey.keyW: LogicalKeyboardKey.keyW,
  PhysicalKeyboardKey.keyL: LogicalKeyboardKey.keyL,
  PhysicalKeyboardKey.keyD: LogicalKeyboardKey.keyD,
  PhysicalKeyboardKey.keyF: LogicalKeyboardKey.keyF,
  PhysicalKeyboardKey.keyP: LogicalKeyboardKey.keyP,
  PhysicalKeyboardKey.keyA: LogicalKeyboardKey.keyA,
  PhysicalKeyboardKey.digit1: LogicalKeyboardKey.digit1,
  PhysicalKeyboardKey.digit0: LogicalKeyboardKey.digit0,
};

/// Scores are commands for the focused player. D is the only draw key.
///
/// F is the only forfeit key, and it switches the focused player's no-show
/// mark on and off. F marks the player absent (0F, the opponent wins 1F); F
/// on the other player of that board as well makes it a double forfeit; F
/// on a player already marked absent takes that mark back, which leaves the
/// other player's forfeit, or no result when there was only the one.
///
/// 1, 0, D, P and ? never mean a forfeit: on any board, a forfeit board
/// included, they enter a played game. Delete or Backspace clears.
///
/// Keys are read through [commandKey], so they also work on a keyboard
/// layout without Latin letters.
Outcome? resultFromKey(
  KeyEvent event, {
  required bool white,
  Outcome current = Outcome.unreported,
}) {
  final key = commandKey(event);
  final wins = white ? Outcome.whiteWin : Outcome.blackWin;
  final loses = white ? Outcome.blackWin : Outcome.whiteWin;
  final winsByForfeit = white ? Outcome.whiteForfeit : Outcome.blackForfeit;
  final forfeits = white ? Outcome.blackForfeit : Outcome.whiteForfeit;
  if (key == LogicalKeyboardKey.keyF) {
    // The opponent was already marked absent: neither player showed.
    if (current == winsByForfeit) return Outcome.doubleForfeit;
    // F again takes this player's mark back; the opponent's stays.
    if (current == Outcome.doubleForfeit) return winsByForfeit;
    if (current == forfeits) return Outcome.unreported;
    return forfeits;
  }
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
  if ([LogicalKeyboardKey.delete, LogicalKeyboardKey.backspace].contains(key)) {
    return Outcome.unreported;
  }
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

/// A key a director reaches for to enter a draw as "0.5" or "=": 5, = and
/// the decimal point, on the number row or the numpad. None of them is a
/// result key, and the legend answers them with [drawKeyHint]. The numpad
/// decimal key may carry no character, so the key itself is matched.
bool isDrawAttempt(KeyEvent event) {
  final typed = (event.character ?? '').trim();
  if (typed.isNotEmpty) return const {'5', '=', '.', ',', '½'}.contains(typed);
  return {
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.equal,
    LogicalKeyboardKey.numpadEqual,
    LogicalKeyboardKey.period,
    LogicalKeyboardKey.numpadDecimal,
    LogicalKeyboardKey.comma,
    LogicalKeyboardKey.numpadComma,
  }.contains(event.logicalKey);
}

/// What the keys do on a forfeit board, from the focused player's side.
String forfeitKeyHint(Outcome current, {required bool white}) {
  const played = '1, 0 or D enters a played game';
  if (current == Outcome.doubleForfeit) {
    return 'Double forfeit · F takes this player\'s no-show back · $played';
  }
  final forfeited =
      current == (white ? Outcome.blackForfeit : Outcome.whiteForfeit);
  return forfeited
      ? 'No-show · F takes it back · F on the other player makes it a double forfeit · $played'
      : 'Won by forfeit · F here makes it a double forfeit · $played';
}

/// The longest of the [forfeitKeyHint]s, which the legend keeps room for.
String longestForfeitKeyHint() => [
  for (final o in [Outcome.whiteForfeit, Outcome.doubleForfeit])
    for (final white in [true, false]) forfeitKeyHint(o, white: white),
].reduce((a, b) => a.length >= b.length ? a : b);

const resultKeyHint =
    '1 / W win · 0 / L loss · D draw · F no-show (F on both: double forfeit)';

/// The other result keys, shown when a key that is not a result is typed.
const moreResultKeys = 'P playing · ? disputed · Delete or Backspace clears';

/// Said first when a key that looks like half a point is typed.
const drawKeyHint = 'Draw is D. 5, = and the decimal point are not result keys';

/// Moving and acting in the results grid.
const gridKeyHint = 'Enter skip · F2 correct · Space player details';
