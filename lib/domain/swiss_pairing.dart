import 'model.dart';
import 'standings.dart';

/// US Chess Swiss pairings for one round (rules 27–29 of the 7th edition).
///
/// The engine follows the rulebook's order of work: the bye (28L), the house
/// player (28M1), score groups from the top (29B), odd players dropped under
/// 29D, upper half against lower half (29C1), repeat avoidance (27A1), then
/// color improvement by transposition and interchange within the 80- and
/// 200-point limits (29E5) and color assignment under 29E4. Every decision
/// that departs from the natural pairing is explained for the director's
/// review (29E TIP). Rule numbers in comments refer to that edition.
const swissPolicy = 'uscf-swiss-29-v1';

/// Announced variations the engine understands (`Section.variations`).
const swissVariations = ['29E4a', '29E4b', '29E4d', '29E5h'];
const swissVariationLabels = {
  '29E4a': 'Color priority to the lower-ranked player in minus score groups',
  '29E4b': 'Alternating color priority within a score group',
  '29E4d': 'Color priority by rank after two identical rounds',
  '29E5h': 'Equalization over ratings: no 80/200-point limits',
};

/// The round-1 toss that applies when the event has not recorded one. It is
/// derived from the event ID so that a proposal is reproducible, and the
/// controller records it on the event when the first round is posted (29E2
/// TIP: one toss serves every section).
String effectiveColorToss(Event event) => event.colorToss.isNotEmpty
    ? event.colorToss
    : event.id.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0xffff).isEven
    ? 'higherWhite'
    : 'higherBlack';

class SwissProposal {
  const SwissProposal(this.games, this.byes, this.explanations);

  /// White and black, in board order (before any fixed boards apply).
  final List<(String, String)> games;
  final List<ByeAward> byes;
  final List<String> explanations;
}

/// Everything the engine knows about one entrant. Scores are half points.
class _Card {
  _Card(this.player, this.rating, this.number);
  final Player player;

  /// The pairing number: the player's position on the section's list
  /// (28B), which breaks rating ties the way numbered pairing cards do.
  final int number;
  String get id => player.id;
  String get name => player.name;

  /// The pairing rating (28A TIP, 28F); 0 means unrated.
  final int rating;
  bool get unrated => rating == 0;

  /// 28L2: an unrated entrant without a US Chess ID is NEW.
  bool get isNew => unrated && player.memberId.isEmpty;

  /// Real score, and the score used to form groups (28R1 may add a point).
  int points = 0, score = 0;

  /// Played colors by round, +1 white and -1 black (29E1: unplayed games
  /// never count).
  final colors = <(int, int)>[];
  final meetings = <String, int>{};
  bool hadFullBye = false, forfeitWin = false, halfBye = false;
  int fullByes = 0;

  int get balance => colors.fold(0, (sum, c) => sum + c.$2);
  int get last => colors.isEmpty ? 0 : colors.last.$2;

  /// 29E3a: the color that equalizes, else the opposite of the last color,
  /// else neither (0).
  int get due => balance < 0
      ? 1
      : balance > 0
      ? -1
      : -last;

  /// How many consecutive games ended with the same color as the last one.
  int get run {
    if (colors.isEmpty) return 0;
    var n = 0;
    for (final c in colors.reversed) {
      if (c.$2 != colors.last.$2) break;
      n++;
    }
    return n;
  }

  /// Giving this player [color]: 0 is fine, 1 denies alternation only
  /// (29E5a), 2 creates a two-game imbalance (29E5b) or a third color in a
  /// row (29E5f).
  int penalty(int color) {
    if (due == 0 || color == due) return 0;
    if ((balance + color).abs() >= 2 || (last == color && run >= 2)) return 2;
    return 1;
  }

  String get colorHistory => colors.isEmpty
      ? 'no colors yet'
      : colors.map((c) => c.$2 == 1 ? 'W' : 'B').join();
}

/// What the director announced for this section.
class _Rules {
  _Rules(this.section, this.round, this.lastRound);
  final Section section;
  final int round;
  final bool lastRound;
  bool has(String v) => section.variations.contains(v);

  /// 29E5a / 29E5b limits, or none under variation 29E5h.
  int limitFor(int penalty) {
    if (has('29E5h')) return 1 << 30;
    return penalty >= 2 ? 200 : 80;
  }
}

/// A board inside a score group: [upper] is the higher-ranked side.
class _Board {
  _Board(this.upper, this.lower, {this.floater = false});
  _Card upper, lower;

  /// A game between an odd player from above and a member of this group.
  final bool floater;
}

class _Failure implements Exception {
  const _Failure(this.message);
  final String message;
}

/// Pairs Swiss round [n] of [section]. [available] are the players who play
/// this round; [byes] already holds the requested byes and withdrawals.
SwissProposal pairSwiss(
  Event event,
  Section section,
  int n,
  List<String> available,
  List<ByeAward> byes,
) {
  final explanations = <String>[];
  final rules = _Rules(section, n, n == section.plannedRounds);
  final cards = _cards(event, section, n, available);
  final house = cards.where((c) => c.player.house).toList();
  final field = cards.where((c) => !c.player.house).toList();
  final awards = [...byes];

  // 28M1: a permanent house player is paired only when the field is odd.
  final useHouse = field.length.isOdd && house.isNotEmpty;
  final playing = [...field, if (useHouse) house.first];
  for (final h in house.skip(useHouse ? 1 : 0)) {
    awards.add(ByeAward(h.id, 0, 'House player not needed'));
  }
  if (useHouse) {
    explanations.add(
      'House player ${house.first.name} is paired because the field is odd (28M1).',
    );
  } else if (house.isNotEmpty) {
    explanations.add('House players sit out: the field is even (28M1).');
  }

  _acceleration(rules, playing, explanations);
  final byeCandidates = playing.length.isOdd
      ? _byeCandidates(rules, playing, explanations)
      : const <(_Card, String)>[];
  if (playing.length.isOdd && byeCandidates.isEmpty) {
    throw const TournamentException(
      'No player is eligible for the full-point bye (28L2–28L4). Add a house player or review bye eligibility.',
    );
  }

  _Failure? lastFailure;
  for (var maxMeetings = 0; maxMeetings <= 3; maxMeetings++) {
    final tries = <(_Card?, String)>[
      if (playing.length.isOdd) ...byeCandidates.take(6) else (null, ''),
    ];
    for (final candidate in tries) {
      final bye = candidate.$1;
      final rest = playing.where((c) => c != bye).toList();
      final attempt = <String>[];
      try {
        final boards = _pairField(rules, rest, maxMeetings, attempt);
        if (maxMeetings > 0) {
          attempt.insert(
            0,
            'No pairing without repeat games exists; a ${maxMeetings == 1 ? 'second' : 'further'} meeting is allowed where unavoidable (27A1).',
          );
        }
        if (bye != null) {
          awards.add(
            ByeAward(
              bye.id,
              section.doubleGames ? 4 : 2,
              candidate.$2,
              allocated: true,
            ),
          );
          attempt.insert(0, 'Full-point bye: ${bye.name}. ${candidate.$2}.');
        }
        final games = _assignColors(event, rules, boards, attempt);
        return SwissProposal(games, awards, [...explanations, ...attempt]);
      } on _Failure catch (f) {
        lastFailure = f;
      }
    }
  }
  throw TournamentException(
    'No pairing satisfies the opponent requests and bye limits: ${lastFailure?.message ?? 'unknown'}. Review player requests or adjust the sections.',
  );
}

List<_Card> _cards(
  Event event,
  Section section,
  int n,
  List<String> available,
) {
  final table = standings(event, section, forPairing: true);
  final points = {for (final r in table) r.player.id: r.points};
  final byId = <String, _Card>{};
  for (final id in available) {
    final p = event.player(id);
    final number = section.players.indexOf(id);
    byId[id] = _Card(p, p.effectivePairingRating, number < 0 ? 1 << 20 : number)
      ..points = points[id] ?? 0
      ..score = points[id] ?? 0;
  }
  // 28S1: a re-entry may not meet an opponent of its earlier entry again,
  // unless that opponent re-entered too (28S2). Colors restart (28S3).
  final earlier = <String, Set<String>>{};
  for (final p in event.players) {
    var e = p.reentryOf;
    final chain = <String>{};
    while (e.isNotEmpty && chain.add(e)) {
      e = event.players.where((x) => x.id == e).firstOrNull?.reentryOf ?? '';
    }
    if (chain.isNotEmpty) earlier[p.id] = chain;
  }
  final reentries = {
    for (final p in event.players) p.id: p.reentryOf.isNotEmpty,
  };
  void meet(String a, String b) {
    byId[a]?.meetings.update(b, (m) => m + 1, ifAbsent: () => 1);
  }

  for (final s in event.sections) {
    for (final r in s.rounds) {
      for (final b in r.byes) {
        if (b.allocated) {
          byId[b.player]
            ?..hadFullBye = true
            ..fullByes += 1;
        } else if (b.points > 0) {
          // 28L4: a half-point bye already taken.
          byId[b.player]?.halfBye = true;
        }
      }
      for (final g in r.games) {
        if (g.outcome == Outcome.whiteForfeit) byId[g.white]?.forfeitWin = true;
        if (g.outcome == Outcome.blackForfeit) byId[g.black]?.forfeitWin = true;
        if (!g.outcome.played && g.pairingAssumption == null) continue;
        meet(g.white, g.black);
        meet(g.black, g.white);
        // A double-game round gives both colors, so it carries no color
        // history (and a double-game section pairs without color goals).
        if (!s.doubleGames && !section.doubleGames) {
          byId[g.white]?.colors.add((r.number, 1));
          byId[g.black]?.colors.add((r.number, -1));
        }
        // The earlier entry's opponents carry over to the re-entry.
        for (final (me, opp) in [(g.white, g.black), (g.black, g.white)]) {
          for (final entry in earlier.entries) {
            if (entry.value.contains(me) && !(reentries[opp] ?? false)) {
              meet(entry.key, opp);
              meet(opp, entry.key);
            }
          }
        }
      }
    }
  }
  for (final c in byId.values) {
    c.colors.sort((a, b) => a.$1.compareTo(b.$1));
    // 28L4: a half-point bye committed to for a later round.
    c.halfBye = c.halfBye || c.player.byes.values.any((v) => v > 0);
  }
  return available.map((id) => byId[id]!).toList();
}

/// 28R1: for the first two rounds, the upper half of the round-1 field is
/// paired as if it had an extra point.
void _acceleration(_Rules rules, List<_Card> playing, List<String> out) {
  if (rules.section.accelerated != 'addedScore' || rules.round > 2) return;
  final List<_Card> field;
  if (rules.round == 1) {
    field = [...playing]..sort(_byRank);
    if (field.length.isOdd) field.removeLast();
  } else {
    final first = rules.section.rounds.firstOrNull;
    final ids = {
      for (final g in first?.games ?? const <Game>[]) ...[g.white, g.black],
    };
    field = playing.where((c) => ids.contains(c.id)).toList()..sort(_byRank);
  }
  final upper = field.take(field.length ~/ 2).toSet();
  for (final c in upper) {
    c.score += 2;
  }
  if (upper.isNotEmpty) {
    out.add(
      'Accelerated pairings (28R1): one point added for pairing only to the top ${upper.length} players of the round-1 field.',
    );
  }
}

int _byRank(_Card a, _Card b) {
  final s = b.score.compareTo(a.score);
  return s != 0 ? s : _byRating(a, b);
}

int _byRating(_Card a, _Card b) {
  final r = b.rating.compareTo(a.rating);
  if (r != 0) return r;
  final n = a.number.compareTo(b.number);
  return n != 0 ? n : a.id.compareTo(b.id);
}

/// Lowest rank first: the lowest rating, then the highest pairing number,
/// the exact reverse of [_byRating] (28A: the pairing number ranks equal
/// ratings).
int _lowestFirst(_Card a, _Card b) => _byRating(b, a);

/// Who drops from a score group first (29D1a): rated players before
/// unrated ones (29D1c), each lowest rank first.
List<_Card> _dropOrder(Iterable<_Card> cards) {
  final order = [...cards]..sort(_lowestFirst);
  return [...order.where((c) => !c.unrated), ...order.where((c) => c.unrated)];
}

/// 28L2–28L5: who may take the full-point bye, best candidate first, each
/// with the reason it would be recorded with.
List<(_Card, String)> _byeCandidates(
  _Rules rules,
  List<_Card> playing,
  List<String> out,
) {
  final groups = _groups(playing);
  final result = <(_Card, String)>[];
  final skipped = <String>[];
  String groupLabel(List<_Card> g) => '${scoreText(g.first.score)}-point group';
  // 28L3 / 28L4 exclusions, with 28L4's exception when everyone in the
  // group has had a bye or a forfeit win.
  bool allHadByes(List<_Card> g) =>
      g.every((c) => c.hadFullBye || c.forfeitWin || c.halfBye);
  for (final (gi, g) in groups.reversed.indexed) {
    final eligible = <_Card>[];
    for (final c in g) {
      if (c.hadFullBye) {
        skipped.add('${c.name} already had a bye (28L3)');
      } else if (c.forfeitWin) {
        skipped.add('${c.name} won a game by forfeit (28L3)');
      } else if (c.halfBye && !allHadByes(g)) {
        skipped.add('${c.name} has a half-point bye (28L4)');
      } else {
        eligible.add(c);
      }
    }
    final rated = eligible.where((c) => !c.unrated).toList()
      ..sort(_lowestFirst);
    final recent = eligible.where((c) => c.unrated && !c.isNew).toList()
      ..sort(_lowestFirst);
    final fresh = eligible.where((c) => c.isNew).toList()..sort(_lowestFirst);
    for (final c in rated) {
      result.add((
        c,
        'Lowest-rated eligible player in the ${groupLabel(g)} (28L2)',
      ));
    }
    for (final c in recent) {
      result.add((
        c,
        'Unrated player (recent member) in the ${groupLabel(g)}: no rated player was eligible (28L2)',
      ));
    }
    // 28L5: in a four-round event, try the group above before a NEW player.
    if (fresh.isNotEmpty && rated.isEmpty && recent.isEmpty) {
      if (rules.section.plannedRounds == 4 && gi + 1 < groups.length) {
        final above = groups.reversed.elementAt(gi + 1);
        for (final c
            in above
                .where(
                  (c) =>
                      !c.unrated &&
                      !c.hadFullBye &&
                      !c.forfeitWin &&
                      !c.halfBye,
                )
                .toList()
              ..sort(_lowestFirst)) {
          result.add((
            c,
            'Bye moved one group up so a NEW player keeps playing in a four-round event (28L5)',
          ));
        }
      }
      for (final c in fresh) {
        result.add((
          c,
          'NEW player in the ${groupLabel(g)}: no other player was eligible (28L2)',
        ));
      }
    }
    if (result.isNotEmpty) break;
  }
  // The loop above walks every group from the bottom, so an empty result
  // means no player anywhere passes 28L3 / 28L4.
  if (result.isEmpty) {
    // Everyone has had a bye or a forfeit win: the rulebook's exclusions
    // cannot all hold, so the fewest byes, then the lowest group and
    // rating, decide. The director is told.
    final all = [...playing]
      ..sort((a, b) {
        final byes = a.fullByes.compareTo(b.fullByes);
        if (byes != 0) return byes;
        final score = a.score.compareTo(b.score);
        if (score != 0) return score;
        final unrated = (a.unrated ? 1 : 0).compareTo(b.unrated ? 1 : 0);
        return unrated != 0 ? unrated : _lowestFirst(a, b);
      });
    for (final c in all) {
      result.add((
        c,
        'Every player has had a bye or a forfeit win; fewest byes, then lowest group and rating (28L3 could not be kept)',
      ));
    }
  }
  if (skipped.isNotEmpty) {
    out.add('Bye candidates passed over: ${skipped.join('; ')}.');
  }
  return result;
}

List<List<_Card>> _groups(List<_Card> cards) {
  final sorted = [...cards]..sort(_byRank);
  final groups = <List<_Card>>[];
  for (final c in sorted) {
    if (groups.isNotEmpty && groups.last.first.score == c.score) {
      groups.last.add(c);
    } else {
      groups.add([c]);
    }
  }
  return groups;
}

/// Pairs the whole (even) field, group by group from the top.
List<_Board> _pairField(
  _Rules rules,
  List<_Card> field,
  int maxMeetings,
  List<String> out,
) {
  if (field.length.isOdd) {
    throw const _Failure('an odd number of players remained');
  }
  final groups = _groups(field);
  final boards = <_Board>[];
  var floaters = <_Card>[];
  final notes = <String>[];
  try {
    // When a lower group cannot be paired, the group above sends one more
    // player down (29D2) and pairing resumes from there.
    final extra = <int, int>{};
    final saved = <int, (int, List<_Card>, int)>{};
    var gi = 0, retries = 0;
    while (gi < groups.length) {
      saved[gi] = (boards.length, [...floaters], notes.length);
      final below = groups.skip(gi + 1).expand((g) => g).toList();
      final ctx = _GroupContext(rules, maxMeetings, groups[gi], below);
      try {
        final plan = ctx.pair(floaters, notes, extraDrops: extra[gi] ?? 0);
        boards.addAll(plan.boards);
        floaters = plan.leftover;
        gi++;
      } on _Failure {
        if (gi == 0 || ++retries > 12 || (extra[gi - 1] ?? 0) >= 3) rethrow;
        extra[gi - 1] = (extra[gi - 1] ?? 0) + 1;
        extra.removeWhere((k, _) => k >= gi);
        final (boardCount, savedFloaters, noteCount) = saved[gi - 1]!;
        boards.removeRange(boardCount, boards.length);
        notes.removeRange(noteCount, notes.length);
        floaters = savedFloaters;
        gi--;
      }
    }
    if (floaters.isNotEmpty) {
      throw _Failure(
        '${floaters.map((c) => c.name).join(', ')} could not be paired in any lower score group',
      );
    }
    out.addAll(notes);
    return boards;
  } on _Failure catch (f) {
    // The group-by-group procedure is not a complete search. Before
    // allowing a repeat, look for any legal pairing that keeps players as
    // close to their score groups as possible (29D), and say so.
    final ctx = _GroupContext(rules, maxMeetings, field, const []);
    final fallback = ctx.globalMatching(field);
    if (fallback == null) rethrow;
    out.add(
      'The score groups could not be paired in order (${f.message}); this round uses the closest legal pairing found by search, without color switches (29D2, 29E5).',
    );
    out.addAll(notes.map((n) => 'Attempted before the search: $n'));
    return fallback;
  }
}

class _Plan {
  _Plan(
    this.boards,
    this.leftover,
    this.penalty,
    this.cost,
    this.notes, {
    this.naturalOpponents = const {},
  });
  final List<_Board> boards;
  final List<_Card> leftover;
  final int penalty, cost;
  final List<String> notes;

  /// For each floater paired here, the opponent 29D1a would give it before
  /// any color switch (the basis of the 29E5c arithmetic).
  final Map<String, _Card> naturalOpponents;
}

class _GroupContext {
  _GroupContext(this.rules, this.maxMeetings, this.members, this.below)
    : next = below.isEmpty ? null : _groups(below).first,
      after = _groups(below).length > 1 ? _groups(below)[1] : null;
  final _Rules rules;
  final int maxMeetings;
  final List<_Card> members;

  /// Every player in the lower score groups, in rank order.
  final List<_Card> below;
  final List<_Card>? next, after;
  final _failed = <String>{};
  var _nodes = 0;

  String get label => '${scoreText(members.first.score)}-point group';

  /// 28N1: team-mates stay apart below plus-two; at plus-two or above they
  /// are not moved out of the group to avoid each other.
  bool get belowPlusTwo =>
      members.first.points - (rules.round - 1) * 1 < 2 * 1 + 0 &&
      members.first.points - (rules.round - 1) < 2;

  bool teammates(_Card a, _Card b) =>
      rules.section.avoidTeammates &&
      a.player.team.trim().isNotEmpty &&
      a.player.team.trim().toLowerCase() == b.player.team.trim().toLowerCase();

  bool legal(_Card a, _Card b, {bool teamsBlocked = true}) {
    if (a == b) return false;
    if ((a.meetings[b.id] ?? 0) > maxMeetings) return false;
    if (a.player.avoid.contains(b.id) || b.player.avoid.contains(a.id)) {
      return false;
    }
    if (a.player.computer && b.player.computer) return false; // Rule 36.
    if (teamsBlocked && teammates(a, b)) return false;
    return true;
  }

  /// Whether [cards] can be perfectly matched legally, leaving at most
  /// [spare] players over.
  bool matchable(List<_Card> cards, {int spare = 0, bool teamsBlocked = true}) {
    _nodes = 0;
    bool go(List<_Card> left, int spare) {
      if (left.isEmpty) return true;
      if (left.length == 1) return spare >= 1;
      // A bounded search: when the budget runs out, assume a matching
      // exists and let a later step report any real impossibility.
      if (++_nodes > 20000) return true;
      final key = '$spare/$teamsBlocked/${left.map((c) => c.id).join(',')}';
      if (_failed.contains(key)) return false;
      final a = left.first;
      if (spare > 0 && go(left.sublist(1), spare - 1)) return true;
      for (var i = 1; i < left.length; i++) {
        if (legal(a, left[i], teamsBlocked: teamsBlocked) &&
            go([...left.sublist(1, i), ...left.sublist(i + 1)], spare)) {
          return true;
        }
      }
      _failed.add(key);
      return false;
    }

    return go(cards, spare);
  }

  /// A legal pairing of the whole field by search: each player in rank
  /// order takes the legal partner with the smallest score difference,
  /// then the one closest to the natural half-split position.
  List<_Board>? globalMatching(List<_Card> field) {
    final sorted = [...field]..sort(_byRank);
    var nodes = 0;
    List<_Board>? go(List<_Card> left) {
      if (left.isEmpty) return [];
      if (++nodes > 200000) return null;
      final a = left.first;
      final target = left.length ~/ 2;
      final position = {for (final (i, c) in left.indexed) c.id: i};
      final choices = left.skip(1).where((b) => legal(a, b)).toList()
        ..sort((b, c) {
          final db = (a.score - b.score).abs(), dc = (a.score - c.score).abs();
          if (db != dc) return db.compareTo(dc);
          final pb = (position[b.id]! - target).abs();
          final pc = (position[c.id]! - target).abs();
          return pb != pc ? pb.compareTo(pc) : _byRank(b, c);
        });
      for (final b in choices) {
        final rest = go(left.where((c) => c != a && c != b).toList());
        if (rest != null) return [_Board(a, b), ...rest];
      }
      return null;
    }

    return go(sorted);
  }

  _Plan pair(List<_Card> floaters, List<String> out, {int extraDrops = 0}) {
    // Odd players from above are paired first, the highest-ranked first.
    final sortedFloaters = [...floaters]..sort(_byRank);
    final best = _bestPlan(
      sortedFloaters,
      lookAhead: true,
      extraDrops: extraDrops,
    );
    out.addAll(best.notes);
    return best;
  }

  /// Compares the default odd player (29D1a) with alternatives within the
  /// transposition limits (29E7 example 5), judging each by the colors of
  /// this group and the next.
  _Plan _bestPlan(
    List<_Card> floaters, {
    required bool lookAhead,
    int extraDrops = 0,
  }) {
    final base = _planWith(
      floaters,
      forcedOdd: null,
      notes: [],
      extraDrops: extraDrops,
    );
    if (!lookAhead || base.leftover.isEmpty || next == null) return base;
    final odd = base.leftover.last;
    if (!members.contains(odd)) return base;
    final baseNext = _nextPlan(base.leftover);
    final baseTotal = base.penalty + (baseNext?.penalty ?? (1 << 20));
    final baseCost = _max(base.cost, baseNext?.cost ?? 0);
    if (baseTotal == 0) return base;
    _Plan chosen = base;
    var chosenTotal = baseTotal, chosenCost = baseCost;
    // 29D1b: try the next-lowest rated player first, and take the first
    // alternative that does better than the natural odd player.
    final alternatives = members.where((c) => c != odd && !c.unrated).toList()
      ..sort(_lowestFirst);
    for (final alt in alternatives) {
      final diff = (alt.rating - odd.rating).abs();
      if (diff > 200 && !odd.unrated && !rules.has('29E5h')) continue;
      final _Plan plan;
      try {
        plan = _planWith(
          floaters,
          forcedOdd: alt,
          notes: [],
          extraDrops: extraDrops,
        );
      } on _Failure {
        continue;
      }
      final altNext = _nextPlan(plan.leftover);
      if (altNext == null) continue;
      if (plan.leftover.length > base.leftover.length ||
          altNext.leftover.length > (baseNext?.leftover.length ?? 0)) {
        continue; // 29D2: colors never justify extra drop-downs.
      }
      final total = plan.penalty + altNext.penalty;
      // 29E5c: the switch of odd players is measured by the smaller of the
      // two differences: the players switched, or the partners they trade
      // (29E7 example 5: 2080–1990 = 90 or 2100–2050 = 50, counting as 50).
      final partnerOfAlt = _partner(base.boards, alt);
      final partnerOfOdd = baseNext?.naturalOpponents[odd.id];
      var cost = diff;
      if (partnerOfAlt != null &&
          partnerOfOdd != null &&
          partnerOfAlt != partnerOfOdd) {
        cost = _min(cost, (partnerOfAlt.rating - partnerOfOdd.rating).abs());
      }
      // 29D1a makes the lowest-rated player the odd player "ordinarily";
      // another choice for colors stays within the 80-point rule.
      final removedStrong = baseTotal - total >= 2;
      final limit = rules.limitFor(1);
      if (cost > limit && !odd.unrated && !alt.unrated) continue;
      final planCost = _max(_max(plan.cost, altNext.cost), cost);
      final better =
          total < chosenTotal ||
          (total == chosenTotal && planCost < chosenCost);
      if (better) {
        chosen = _Plan(plan.boards, plan.leftover, plan.penalty, planCost, [
          '${alt.name} (${alt.rating}) is the odd player of the $label instead of ${odd.name} (${odd.rating}) to improve colors: a $cost-point switch (29D1b, 29E5${removedStrong ? 'b' : 'a'}).',
          ...plan.notes,
        ]);
        chosenTotal = total;
        chosenCost = planCost;
        break;
      }
    }
    return chosen;
  }

  static _Card? _partner(List<_Board> boards, _Card c) => boards
      .where((b) => b.upper == c || b.lower == c)
      .map((b) => b.upper == c ? b.lower : b.upper)
      .firstOrNull;

  /// How the next group would pair with these floaters, or null when it
  /// could not.
  _Plan? _nextPlan(List<_Card> floaters) {
    final n = next;
    if (n == null) return null;
    try {
      final ctx = _GroupContext(
        rules,
        maxMeetings,
        n,
        below.skip(n.length).toList(),
      );
      return ctx._planWith(
        [...floaters]..sort(_byRank),
        forcedOdd: null,
        notes: [],
      );
    } on _Failure {
      return null;
    }
  }

  _Plan _planWith(
    List<_Card> floaters, {
    required _Card? forcedOdd,
    required List<String> notes,
    int extraDrops = 0,
  }) {
    var pool = [...members];
    final boards = <_Board>[];
    final leftover = <_Card>[];
    final naturalOpponents = <String, _Card>{};
    var cost = 0;

    // 29D1a: each odd player meets the highest-rated opponent it can play;
    // 29D1b allows a lower opponent within the color-switch limits.
    for (final f in floaters) {
      final candidates = [...pool]
        ..sort(_byRating)
        ..retainWhere((m) => legal(f, m, teamsBlocked: belowPlusTwo));
      // The rest of the field, including floaters still to be placed and
      // those that already dropped further, must stay pairable.
      final others = floaters.skip(floaters.indexOf(f) + 1).toList();
      bool completes(_Card m) => matchable([
        ...pool.where((x) => x != m),
        ...others,
        ...leftover,
        ...below,
      ], teamsBlocked: false);
      _Card? chosen;
      for (final m in candidates) {
        if (!completes(m)) continue;
        chosen = m;
        break;
      }
      if (chosen == null) {
        notes.add(
          '${f.name} (${scoreText(f.score)}) has no available opponent in the $label and drops further (29D2).',
        );
        leftover.add(f);
        continue;
      }
      naturalOpponents[f.id] = chosen;
      var opponent = chosen;
      var note =
          '${f.name} (${scoreText(f.score)}, ${f.rating}) drops to the $label as the odd player and plays ${chosen.name} (${chosen.rating}), the highest-rated available opponent (29D1a).';
      if (f.due != 0 && f.due == chosen.due) {
        final strength = f.penalty(-f.due) > chosen.penalty(-chosen.due)
            ? f.penalty(-f.due)
            : chosen.penalty(-chosen.due);
        final limit = rules.limitFor(strength);
        for (final m in candidates.skip(candidates.indexOf(chosen) + 1)) {
          final diff = (chosen.rating - m.rating).abs();
          if (diff > limit && !m.unrated && !chosen.unrated) break;
          if (m.due == f.due && m.due != 0) continue;
          if (!completes(m)) continue;
          // 29D2: a switch for colors must not force extra drop-downs.
          final rest = pool.where((x) => x != m).toList();
          if (!matchable(rest, spare: rest.length.isOdd ? 1 : 0)) continue;
          opponent = m;
          cost = cost > diff ? cost : diff;
          note =
              '${f.name} (${scoreText(f.score)}, ${f.rating}) drops to the $label as the odd player and plays ${m.name} (${m.rating}) instead of ${chosen.name} (${chosen.rating}): a $diff-point switch for colors (29D1b, 29E5${strength >= 2 ? 'b' : 'a'}).';
          break;
        }
      }
      notes.add(note);
      boards.add(_Board(f, opponent, floater: true));
      pool.remove(opponent);
    }

    // 28N1b: below plus-two, move a team-mate out rather than pair them.
    if (belowPlusTwo && !matchable(pool, spare: pool.length.isOdd ? 1 : 0)) {
      final movable =
          pool.where((c) => pool.any((d) => d != c && teammates(c, d))).toList()
            ..sort(_lowestFirst);
      for (final c in movable) {
        final rest = pool.where((x) => x != c).toList();
        if (matchable(rest, spare: rest.length.isOdd ? 1 : 0) &&
            (next != null)) {
          notes.add(
            '${c.name} moves down from the $label so team-mates do not meet (28N1b).',
          );
          leftover.add(c);
          pool = rest;
          break;
        }
      }
    }

    // 29D: a group whose members have all met (or are restricted) sends
    // players down, lowest-rated first, until the rest can be paired.
    while (pool.isNotEmpty &&
        !matchable(pool, spare: pool.length.isOdd ? 1 : 0) &&
        !matchable(
          pool,
          spare: pool.length.isOdd ? 1 : 0,
          teamsBlocked: false,
        )) {
      if (next == null) {
        throw _Failure('the $label cannot be paired among itself');
      }
      final drop = _dropOrder(pool)
          .where(
            (c) =>
                forcedOdd != c &&
                below.any((m) => legal(c, m, teamsBlocked: false)) &&
                matchable(
                  [c, ...below],
                  spare: below.length.isEven ? 1 : 0,
                  teamsBlocked: false,
                ),
          )
          .firstOrNull;
      if (drop == null) {
        throw _Failure('the $label cannot be paired among itself');
      }
      notes.add(
        '${drop.name} (${drop.rating}) drops from the $label: its members have already met or are restricted (27A1, 29D).',
      );
      pool.remove(drop);
      leftover.add(drop);
    }

    // 29D2: a lower group that could not be paired asked for more players
    // from here; the lowest-rated who can play below go first.
    for (var k = 0; k < extraDrops; k++) {
      if (next == null) throw _Failure('the $label has no group below');
      final drop = _dropOrder(pool).where((c) {
        if (c == forcedOdd) return false;
        final rest = pool.where((x) => x != c).toList();
        return below.any((m) => legal(c, m, teamsBlocked: false)) &&
            matchable(rest, spare: rest.length.isOdd ? 1 : 0);
      }).firstOrNull;
      if (drop == null) {
        throw _Failure('the $label cannot send another player down');
      }
      notes.add(
        '${drop.name} (${drop.rating}) drops from the $label so the groups below can be paired (29D2).',
      );
      pool.remove(drop);
      leftover.add(drop);
    }

    // 29D1: the odd player is the lowest-rated who can be paired below.
    if (pool.length.isOdd) {
      if (next == null) {
        throw _Failure('the $label cannot be paired evenly');
      }
      final ratedFirst = _dropOrder(forcedOdd != null ? [forcedOdd] : pool);
      _Card? odd;
      // 29D1a: the odd player must have an opponent in the next group;
      // 29D2: failing that, in a lower one. Either way the rest of the
      // field must still be pairable.
      for (final tryDeeper in [false, true]) {
        for (final c in ratedFirst) {
          if (!pool.contains(c)) continue;
          final rest = pool.where((x) => x != c).toList();
          if (!matchable(rest, teamsBlocked: belowPlusTwo) &&
              !matchable(rest, teamsBlocked: false)) {
            continue;
          }
          final reach = tryDeeper ? below : next!;
          if (!reach.any((m) => legal(c, m, teamsBlocked: false))) continue;
          if (!matchable(
            [c, ...below],
            spare: below.length.isEven ? 1 : 0,
            teamsBlocked: false,
          )) {
            continue;
          }
          odd = c;
          break;
        }
        if (odd != null) break;
      }
      if (odd == null) {
        throw _Failure('no odd player of the $label can be paired below');
      }
      if (forcedOdd == null) {
        notes.add(
          '${odd.name} (${odd.rating}) is the odd player of the $label: the lowest-rated ${odd.unrated ? 'player, as the group is unrated (29D1c)' : 'rated player (29D1a)'}.',
        );
      }
      pool.remove(odd);
      leftover.add(odd);
    }

    // 29C1: upper half against lower half in rank order.
    pool.sort(_byRating);
    final half = pool.length ~/ 2;
    final group = <_Board>[
      for (var i = 0; i < half; i++) _Board(pool[i], pool[half + i]),
    ];
    var teamsBlocked = belowPlusTwo || rules.section.avoidTeammates;
    if (!_fixIllegal(group, teamsBlocked: teamsBlocked, notes: notes)) {
      if (teamsBlocked &&
          _fixIllegal(group, teamsBlocked: false, notes: notes)) {
        teamsBlocked = false;
        notes.add(
          'Team-mates meet in the $label: no other pairing was possible (28N1${belowPlusTwo ? 'a' : 'c'}).',
        );
      } else {
        throw _Failure('the $label cannot be paired without a repeat');
      }
    }
    cost = _improveColors(
      group,
      teamsBlocked: teamsBlocked,
      notes: notes,
      cost: cost,
    );
    // Boards follow rank even after an interchange moved players.
    group.sort((a, b) => _byRank(a.upper, b.upper));
    boards.addAll(group);
    var penalty = 0;
    for (final b in boards) {
      penalty += _boardPenalty(b);
    }
    return _Plan(
      boards,
      leftover,
      penalty,
      cost,
      notes,
      naturalOpponents: naturalOpponents,
    );
  }

  /// The color conflict a board carries once colors are assigned by 29E4.
  int _boardPenalty(_Board b) {
    final (white, black) = _decide(b.upper, b.lower, rules, board: 0);
    return white.penalty(1) + black.penalty(-1);
  }

  bool _illegal(_Board b, bool teamsBlocked) =>
      !legal(b.upper, b.lower, teamsBlocked: teamsBlocked);

  /// 27A1 / 29C2: removes repeat and restricted pairings with the
  /// smallest switches; there is no rating limit for keeping a score group
  /// intact (29D1b).
  bool _fixIllegal(
    List<_Board> group, {
    required bool teamsBlocked,
    required List<String> notes,
  }) {
    for (var guard = 0; guard < group.length * 2; guard++) {
      final bad = group.indexWhere((b) => _illegal(b, teamsBlocked));
      if (bad < 0) return true;
      var illegalCount = group.where((b) => _illegal(b, teamsBlocked)).length;
      (int cost, void Function() apply, String note)? best;
      for (var j = 0; j < group.length; j++) {
        if (j == bad) continue;
        for (final move in _moves(group, bad, j)) {
          move.apply();
          final count = group.where((b) => _illegal(b, teamsBlocked)).length;
          final fixed = !_illegal(group[bad], teamsBlocked);
          move.undo();
          if (!fixed || count >= illegalCount) continue;
          if (best == null || move.cost < best.$1) {
            best = (
              move.cost,
              move.apply,
              move.describe('to avoid a repeat or restricted pairing (27A1)'),
            );
          }
        }
      }
      if (best == null) break;
      best.$2();
      notes.add(best.$3);
    }
    // Local switches were not enough: rebuild the group legally, staying as
    // close to the natural order as possible.
    final cards = group.expand((b) => [b.upper, b.lower]).toList()
      ..sort(_byRating);
    final half = cards.length ~/ 2;
    final natural = {
      for (var i = 0; i < half; i++) cards[i].id: cards[half + i],
    };
    List<_Board>? solve(List<_Card> left) {
      if (left.isEmpty) return [];
      final a = left.first;
      final choices =
          left
              .skip(1)
              .where((b) => legal(a, b, teamsBlocked: teamsBlocked))
              .toList()
            ..sort((x, y) {
              final tx = (x.rating - (natural[a.id]?.rating ?? x.rating)).abs();
              final ty = (y.rating - (natural[a.id]?.rating ?? y.rating)).abs();
              return tx != ty ? tx.compareTo(ty) : _byRating(x, y);
            });
      for (final b in choices) {
        final rest = solve(left.where((c) => c != a && c != b).toList());
        if (rest != null) return [_Board(a, b), ...rest];
      }
      return null;
    }

    final rebuilt = solve(cards);
    if (rebuilt == null) return false;
    group
      ..clear()
      ..addAll(rebuilt);
    notes.add(
      'The $label was re-paired from the top to avoid repeat or restricted pairings (27A1, 29C2).',
    );
    return true;
  }

  /// 29E6a Look Ahead: switches that reduce the group's color conflicts,
  /// within 29E5a/29E5b, preferring transpositions inside 80 points to
  /// interchanges (29E5e) and smaller switches otherwise.
  int _improveColors(
    List<_Board> group, {
    required bool teamsBlocked,
    required List<String> notes,
    required int cost,
  }) {
    int total() => group.fold(0, (s, b) => s + _boardPenalty(b));
    for (var guard = 0; guard < group.length * 3; guard++) {
      final before = total();
      if (before == 0) break;
      _Move? best;
      var bestGain = 0;
      for (var i = 0; i < group.length; i++) {
        if (_boardPenalty(group[i]) == 0) continue;
        final strength = _boardPenalty(group[i]) >= 2 ? 2 : 1;
        final limit = rules.limitFor(strength);
        for (var j = 0; j < group.length; j++) {
          if (j == i) continue;
          for (final move in _moves(group, i, j)) {
            // 29E5g: switches to or from an unrated player are exempt.
            if (move.cost > limit && !move.unratedInvolved) continue;
            move.apply();
            final legalNow = !group.any((b) => _illegal(b, teamsBlocked));
            final after = total();
            move.undo();
            if (!legalNow) continue;
            final gain = before - after;
            if (gain <= 0) continue;
            if (best == null || _preferred(move, gain, best, bestGain)) {
              best = move;
              bestGain = gain;
            }
          }
        }
      }
      if (best == null) break;
      best.apply();
      cost = cost > best.cost ? cost : best.cost;
      notes.add(
        best.describe(
          'for colors (${best.interchange ? '29E5d' : '29E5c'}, ${rules.limitFor(2) == best.limitUsed ? '29E5b' : '29E5a'})',
        ),
      );
    }
    return cost;
  }

  bool _preferred(_Move m, int gain, _Move best, int bestGain) {
    if (gain != bestGain) return gain > bestGain;
    // 29E5e: a transposition within 80 points beats any interchange; else
    // the smaller switch wins.
    final mWithin = !m.interchange && m.cost <= 80;
    final bWithin = !best.interchange && best.cost <= 80;
    if (mWithin != bWithin) return mWithin;
    if (m.cost != best.cost) return m.cost < best.cost;
    return !m.interchange && best.interchange;
  }

  /// The two kinds of switch between boards [i] and [j]: a transposition
  /// (the lower-half players trade boards, measured by the smaller of the
  /// two differences, 29E5c) and an interchange (an upper-half player
  /// trades with a lower-half player, 29E5d).
  Iterable<_Move> _moves(List<_Board> group, int i, int j) sync* {
    final a = group[i], b = group[j];
    if (a.floater || b.floater) return;
    final ua = a.upper, la = a.lower, ub = b.upper, lb = b.lower;
    void restore() {
      a.upper = ua;
      a.lower = la;
      b.upper = ub;
      b.lower = lb;
    }

    yield _Move(
      cost: _min((la.rating - lb.rating).abs(), (ua.rating - ub.rating).abs()),
      interchange: false,
      unratedInvolved: la.unrated || lb.unrated || ua.unrated || ub.unrated,
      apply: () {
        a.lower = lb;
        b.lower = la;
      },
      undo: restore,
      describe: (why) =>
          'Boards ${i + 1} and ${j + 1} of the $label: transposed ${la.name} (${la.rating}) and ${lb.name} (${lb.rating}) $why.',
      limitUsed: rules.limitFor(2),
    );
    // An interchange: a's upper-half player trades places with b's
    // lower-half player.
    yield _Move(
      cost: (ua.rating - lb.rating).abs(),
      interchange: true,
      unratedInvolved: ua.unrated || lb.unrated,
      apply: () {
        a.upper = lb;
        b.lower = ua;
        _orient(a);
        _orient(b);
      },
      undo: restore,
      describe: (why) =>
          'Boards ${i + 1} and ${j + 1} of the $label: interchanged ${ua.name} (${ua.rating}) and ${lb.name} (${lb.rating}) $why.',
      limitUsed: rules.limitFor(2),
    );
    // The other direction: b's upper-half player trades with a's
    // lower-half player (29E7 example 4: 1920 with 1900).
    yield _Move(
      cost: (ub.rating - la.rating).abs(),
      interchange: true,
      unratedInvolved: ub.unrated || la.unrated,
      apply: () {
        b.upper = la;
        a.lower = ub;
        _orient(a);
        _orient(b);
      },
      undo: restore,
      describe: (why) =>
          'Boards ${i + 1} and ${j + 1} of the $label: interchanged ${ub.name} (${ub.rating}) and ${la.name} (${la.rating}) $why.',
      limitUsed: rules.limitFor(2),
    );
  }

  void _orient(_Board b) {
    if (_byRating(b.upper, b.lower) > 0) {
      final t = b.upper;
      b.upper = b.lower;
      b.lower = t;
    }
  }
}

int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;

class _Move {
  _Move({
    required this.cost,
    required this.interchange,
    required this.unratedInvolved,
    required this.apply,
    required this.undo,
    required this.describe,
    required this.limitUsed,
  });
  final int cost, limitUsed;
  final bool interchange, unratedInvolved;
  final void Function() apply, undo;
  final String Function(String why) describe;
}

/// 29E4: which of two players takes white. [board] numbers the game within
/// the round for the round-1 alternation (29E2) and its later analogue.
(_Card white, _Card black) _decide(
  _Card a,
  _Card b,
  _Rules rules, {
  required int board,
  String toss = 'higherWhite',
}) {
  final higher = _byRank(a, b) <= 0 ? a : b, lower = higher == a ? b : a;
  (_Card, _Card) give(_Card w) => w == a ? (a, b) : (b, a);
  if (a.due != b.due) {
    if (a.due == 0) return give(b.due == 1 ? b : a);
    if (b.due == 0) return give(a.due == 1 ? a : b);
    return give(a.due == 1 ? a : b);
  }
  if (a.due == 0) {
    // 29E2 / 28J: the toss decides board one, then colors alternate.
    final higherWhite = (toss == 'higherWhite') == board.isEven;
    return give(higherWhite ? higher : lower);
  }
  final due = a.due;
  // Rules 1 and 2: the greater imbalance takes its due color.
  final ia = a.balance.abs(), ib = b.balance.abs();
  if (ia != ib) {
    final w = ia > ib ? a : b;
    return give(due == 1 ? w : (w == a ? b : a));
  }
  if (!rules.has('29E4d')) {
    // Rules 3 and 4: the latest round in which their colors differed; the
    // player who did not have the due color then receives it now.
    final ca = {for (final c in a.colors) c.$1: c.$2};
    final cb = {for (final c in b.colors) c.$1: c.$2};
    for (var r = rules.round - 1; r >= 1; r--) {
      final x = ca[r] ?? 0, y = cb[r] ?? 0;
      if (x == y) continue;
      final w = x == due ? b : (y == due ? a : (x == 0 ? a : b));
      return give(due == 1 ? w : (w == a ? b : a));
    }
  } else {
    final ca = {for (final c in a.colors) c.$1: c.$2};
    final cb = {for (final c in b.colors) c.$1: c.$2};
    final r = rules.round - 1;
    if (r >= 2 && (ca[r] != cb[r] || ca[r - 1] != cb[r - 1])) {
      for (var k = r; k >= r - 1; k--) {
        final x = ca[k] ?? 0, y = cb[k] ?? 0;
        if (x == y) continue;
        final w = x == due ? b : (y == due ? a : (x == 0 ? a : b));
        return give(due == 1 ? w : (w == a ? b : a));
      }
    }
  }
  // Rule 5: the higher-ranked player takes the due color (29E4a: the
  // lower-ranked in minus groups).
  final minus = higher.points < rules.round - 1;
  final priority = rules.has('29E4a') && minus ? lower : higher;
  return give(due == 1 ? priority : (priority == a ? b : a));
}

/// Colors for the paired boards, in board order, and the 29E5f check.
List<(String, String)> _assignColors(
  Event event,
  _Rules rules,
  List<_Board> boards,
  List<String> out,
) {
  final toss = effectiveColorToss(event);
  final games = <(String, String)>[];
  var alternate = 0;
  // 29E4b: alternate entitlement within a group when several boards tie
  // on rule 5.
  for (final (i, b) in boards.indexed) {
    var (white, black) = _decide(b.upper, b.lower, rules, board: i, toss: toss);
    if (rules.has('29E4b') &&
        b.upper.due == b.lower.due &&
        b.upper.due != 0 &&
        b.upper.balance.abs() == b.lower.balance.abs() &&
        b.upper.colorHistory == b.lower.colorHistory) {
      if (alternate.isOdd) (white, black) = (black, white);
      alternate++;
    }
    for (final (c, color) in [(white, 1), (black, -1)]) {
      if (c.last == color && c.run >= 2 && c.due != color) {
        out.add(
          '${c.name} receives ${color == 1 ? 'white' : 'black'} for the third time in a row: no other reasonable pairing of the group${rules.lastRound ? ' in the last round' : ''} (29E5f).',
        );
      }
    }
    games.add((white.id, black.id));
  }
  if (rules.round == 1) {
    out.add(
      'Round 1 colors: the ${toss == 'higherWhite' ? 'higher' : 'lower'}-rated player has white on board 1, alternating down the boards (28J, 29E2).',
    );
  }
  return games;
}
