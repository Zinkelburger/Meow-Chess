import 'model.dart';

/// Rule 28S5: the score a re-entry carries when it is not its own.
class ReentryCarry {
  const ReentryCarry({
    required this.entry,
    required this.through,
    required this.carried,
    required this.own,
  });

  /// The earlier entry whose score, color and opponent history the
  /// re-entry carries.
  final String entry;

  /// The last round the earlier entries played: the comparison covers
  /// rounds up to here, and later rounds are the re-entry's own.
  final int through;

  /// Half points through [through]: the carried entry's, and the
  /// re-entry's own that it replaces.
  final int carried, own;
}

/// Rule 28S5: for each re-entry in [section] whose earlier entry (withdrawn,
/// as a re-entry requires) had the better score when the entries merged,
/// the score it carries instead of its own. Equal scores keep the latest
/// entry, and so does the announced variation `28S5latest` (the organizer's
/// option that a re-entry abandons its earlier entries); neither appears
/// here. [outcomeOf] reads a game the way the caller scores it.
Map<String, ReentryCarry> reentryCarries(
  Event event,
  Section section, {
  Outcome Function(Game)? outcomeOf,
}) {
  if (section.variations.contains('28S5latest')) return const {};
  final byId = {for (final p in event.players) p.id: p};
  final chains = <String, List<String>>{};
  for (final id in section.players) {
    final p = byId[id];
    if (p == null || p.reentryOf.isEmpty) continue;
    final earlier = <String>[];
    final seen = {id};
    var e = p.reentryOf;
    while (e.isNotEmpty && seen.add(e) && byId[e] != null) {
      if (byId[e]!.withdrawn) earlier.insert(0, e);
      e = byId[e]!.reentryOf;
    }
    if (earlier.isNotEmpty) chains[id] = earlier;
  }
  if (chains.isEmpty) return const {};
  final wanted = {
    for (final MapEntry(:key, :value) in chains.entries) ...[key, ...value],
  };
  // Points by round for each entry, and the last round with a result (a
  // withdrawal's zero-point byes are not results).
  final points = <String, Map<int, int>>{for (final id in wanted) id: {}};
  final lastRound = <String, int>{};
  void credit(String id, int round, int p, {required bool counts}) {
    final rounds = points[id];
    if (rounds == null) return;
    rounds[round] = (rounds[round] ?? 0) + p;
    if (counts && round > (lastRound[id] ?? 0)) lastRound[id] = round;
  }

  for (final s in event.sections) {
    for (final r in s.rounds) {
      for (final b in r.byes) {
        credit(b.player, r.number, b.points, counts: b.points > 0);
      }
      for (final g in r.games) {
        final o = outcomeOf?.call(g) ?? g.outcome;
        credit(g.white, r.number, o.whiteScore, counts: true);
        credit(g.black, r.number, o.blackScore, counts: true);
      }
    }
  }
  int upTo(String id, int round) => points[id]!.entries
      .where((e) => e.key <= round)
      .fold(0, (sum, e) => sum + e.value);
  final result = <String, ReentryCarry>{};
  for (final MapEntry(key: id, value: earlier) in chains.entries) {
    final merge = earlier.fold(0, (m, e) {
      final last = lastRound[e] ?? 0;
      return last > m ? last : m;
    });
    if (merge == 0) continue;
    // The best score; between equal scores the latest entry.
    var best = id, bestScore = upTo(id, merge);
    for (final e in earlier.reversed) {
      final score = upTo(e, merge);
      if (score > bestScore) {
        best = e;
        bestScore = score;
      }
    }
    if (best == id) continue;
    result[id] = ReentryCarry(
      entry: best,
      through: merge,
      carried: bestScore,
      own: upTo(id, merge),
    );
  }
  return result;
}
