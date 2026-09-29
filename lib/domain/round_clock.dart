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
  final match = RegExp(
    r'^G\s*/\s*(\d+)(?:\s*([di+])\s*(\d+))?$',
    caseSensitive: false,
  ).firstMatch(timeControl.trim());
  if (match == null || assumedMoves < 1) return null;
  final minutes = int.parse(match[1]!);
  final extra = int.tryParse(match[3] ?? '0') ?? 0;
  if (minutes < 1) return null;
  return RoundEstimate(
    actualStart.add(
      Duration(minutes: minutes * 2, seconds: extra * assumedMoves * 2),
    ),
    assumedMoves,
  );
}
