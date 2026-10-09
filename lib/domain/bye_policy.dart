import 'model.dart';

/// Rule 22C: a section's announced half-point bye policy, read from
/// `Section.byeRules`. Every value is optional; zero means no limit.
class ByePolicy {
  const ByePolicy({
    this.lastHalfByeRound = 0,
    this.maxHalfByes = 0,
    this.deadlineMinutes = 60,
    this.irrevocableFromRound = 0,
  });

  factory ByePolicy.fromJson(Json j) => ByePolicy(
    lastHalfByeRound: (j['lastHalfByeRound'] as num?)?.toInt() ?? 0,
    maxHalfByes: (j['maxHalfByes'] as num?)?.toInt() ?? 0,
    deadlineMinutes: (j['deadlineMinutes'] as num?)?.toInt() ?? 60,
    irrevocableFromRound: (j['irrevocableFromRound'] as num?)?.toInt() ?? 0,
  );

  /// Rule 22C1: the last round a half-point bye may be requested for.
  final int lastHalfByeRound;

  /// Rule 22C3: half-point byes allowed per player.
  final int maxHalfByes;

  /// Rule 22C2: how long before the round requests close. Informational.
  final int deadlineMinutes;

  /// Rule 22C4: byes for this round and later must be declared irrevocable.
  final int irrevocableFromRound;

  Json toJson() => {
    if (lastHalfByeRound > 0) 'lastHalfByeRound': lastHalfByeRound,
    if (maxHalfByes > 0) 'maxHalfByes': maxHalfByes,
    if (deadlineMinutes != 60) 'deadlineMinutes': deadlineMinutes,
    if (irrevocableFromRound > 0) 'irrevocableFromRound': irrevocableFromRound,
  };

  bool get isDefault =>
      lastHalfByeRound == 0 &&
      maxHalfByes == 0 &&
      deadlineMinutes == 60 &&
      irrevocableFromRound == 0;

  /// Rule 22C4: a half-point bye for [round] needs an irrevocable notice.
  bool requiresIrrevocable(int round) =>
      irrevocableFromRound > 0 && round >= irrevocableFromRound;

  /// Why a half-point bye for [round] cannot be reserved for [player], or
  /// null when the policy allows it. Zero-point byes are never limited.
  /// [declared] is whether the request carries, or the player already gave,
  /// the irrevocable notice.
  String? halfByeProblem(Player player, int round, {required bool declared}) {
    if (lastHalfByeRound > 0 && round > lastHalfByeRound) {
      return 'Half-point byes were announced only through round $lastHalfByeRound (rule 22C1). Round $round can take a zero-point bye.';
    }
    final others = player.byes.entries
        .where((b) => b.key != round && b.value == 1)
        .length;
    if (maxHalfByes > 0 && others >= maxHalfByes) {
      return 'This section allows ${maxHalfByes == 1 ? 'one half-point bye' : '$maxHalfByes half-point byes'} per player (rule 22C3). Cancel another or give a zero-point bye.';
    }
    if (requiresIrrevocable(round) && !declared) {
      return 'A half-point bye for round $round must be declared irrevocable (rule 22C4). Tick Irrevocable to confirm the player accepts it.';
    }
    return null;
  }

  /// One line for the player panel and the conditions sheet.
  String describe() {
    final parts = [
      lastHalfByeRound > 0
          ? 'half-point byes through round $lastHalfByeRound'
          : 'half-point byes in any round',
      if (maxHalfByes > 0)
        '${maxHalfByes == 1 ? 'one' : '$maxHalfByes'} per player',
      'requests $deadlineMinutes minutes before the round',
      if (irrevocableFromRound > 0)
        'irrevocable from round $irrevocableFromRound',
    ];
    return parts.join(' · ');
  }
}

/// Marker kept in a game note when rule 22C5 reduced a win to a draw for
/// prize purposes, so later corrections can lift it again.
const irrevocableByeNote =
    'Rule 22C5: played after cancelling an irrevocable bye; a win counts as a draw for prizes.';

/// Rule 22C5: a player who cancelled an irrevocable half-point bye for
/// [roundNumber] and then won has the result counted as a draw for prizes.
/// Returns [game] with `prizeOutcome` and its note set or cleared.
Game applyIrrevocableByeRule(Event e, Game game, int roundNumber) {
  bool cancelledBye(String id) {
    final p = e.players.where((p) => p.id == id).firstOrNull;
    return p != null &&
        p.irrevocableByes.contains(roundNumber) &&
        p.byes[roundNumber] == null;
  }

  final winnerCancelled =
      (game.outcome == Outcome.whiteWin && cancelledBye(game.white)) ||
      (game.outcome == Outcome.blackWin && cancelledBye(game.black));
  final hadNote = game.note.contains(irrevocableByeNote);
  if (winnerCancelled) {
    return game.copy(
      prizeOutcome: Outcome.draw,
      note: hadNote
          ? game.note
          : [
              if (game.note.trim().isNotEmpty) game.note.trim(),
              irrevocableByeNote,
            ].join(' '),
    );
  }
  if (!hadNote) return game;
  return game.copy(
    prizeOutcome: game.prizeOutcome == Outcome.draw ? null : game.prizeOutcome,
    note: game.note.replaceAll(irrevocableByeNote, '').trim(),
  );
}
