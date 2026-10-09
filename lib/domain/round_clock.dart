import 'model.dart';
import 'us_chess.dart';

/// A planning estimate, never a deadline or a bound on game duration.
class RoundEstimate {
  const RoundEstimate(this.finish, this.assumedMoves);
  final DateTime finish;
  final int assumedMoves;
  String get label =>
      'Estimated ${finish.hour.toString().padLeft(2, '0')}:${finish.minute.toString().padLeft(2, '0')} · $assumedMoves moves/player';
}

RoundEstimate? estimateRoundFinish(
  String timeControl,
  DateTime actualStart, {
  int assumedMoves = 40,
}) {
  if (assumedMoves < 1) return null;
  final TimeControl control;
  try {
    // Every form the app accepts or writes: `G/60;d5`, `G/90 inc/30`,
    // `Game/45`, `40/90, SD/30 d/5`.
    control = TimeControl.parse(timeControl);
  } on TournamentException {
    return null;
  }
  // A move-count control (`40/90, SD/30`) has no single game length.
  if (control.stages.length != 1) return null;
  final minutes = control.stages.single.$2;
  final extra = control.bonusSeconds;
  return RoundEstimate(
    actualStart.add(
      Duration(minutes: minutes * 2, seconds: extra * assumedMoves * 2),
    ),
    assumedMoves,
  );
}
