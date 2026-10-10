import 'model.dart';

/// Knockout: a single-elimination bracket of mini-matches.
///
/// The bracket is rebuilt from `Section.rounds` (the games as played),
/// `bracket['seeds']` (frozen when round 1 is posted) and the director's
/// decisions on drawn matches in `bracket['rounds']`. Nothing else is stored,
/// so correcting a result re-derives who advanced.
///
/// `Section.bracket` keys: `gamesPerMatch` (1 or 2; default 2), `tiebreak`
/// (`none`, `rapid`, `blitz`, `armageddon`; default `none`), `seeds` (player
/// IDs in seeding order), `rounds` (one entry per bracket round as played:
/// `stage`, `name`, `rounds` (section round numbers, tie-break postings
/// included) and `decisions` (`board`, `advanced`, `reason`)).
const knockoutPolicy = 'knockout-v1';

/// What happens when a match is drawn, keyed as stored in `bracket['tiebreak']`.
const knockoutTiebreakLabels = <String, String>{
  'none': 'Director decides',
  'rapid': 'Rapid games',
  'blitz': 'Blitz games',
  'armageddon': 'Armageddon',
};

int knockoutGamesPerMatch(Section section) =>
    switch (section.bracket['gamesPerMatch']) {
      final int n => n,
      final num n => n.toInt(),
      _ => 2,
    };

String knockoutTiebreak(Section section) =>
    section.bracket['tiebreak'] as String? ?? 'none';

/// Why these bracket settings cannot be used, or null.
String? knockoutSettingsProblem(Json bracket) {
  final games = bracket['gamesPerMatch'] ?? 2;
  if (games is! int || (games != 1 && games != 2)) {
    return 'Matches of 1 or 2 games are supported. Choose 1 or 2 games per match.';
  }
  final tiebreak = bracket['tiebreak'] ?? 'none';
  if (tiebreak is! String || !knockoutTiebreakLabels.containsKey(tiebreak)) {
    return 'Tie-break must be ${knockoutTiebreakLabels.keys.join(', ')}.';
  }
  final seeds = bracket['seeds'];
  if (seeds != null && (seeds is! List || seeds.any((s) => s is! String))) {
    return 'Seeds must be a list of player IDs.';
  }
  final rounds = bracket['rounds'];
  if (rounds != null && (rounds is! List || rounds.any((r) => r is! Map))) {
    return 'Bracket rounds must be a list of bracket round records.';
  }
  return null;
}

/// Why the section cannot be paired as a knockout, or null.
String? knockoutProblem(Event event, Section section) {
  if (knockoutSettingsProblem(section.bracket) case final problem?) {
    return problem;
  }
  if (knockoutSeeds(event, section).length < 2) {
    return 'A knockout needs at least two players.';
  }
  return null;
}

/// One line for the closed Pairing rules group.
String knockoutSummary(Section section) {
  final games = knockoutGamesPerMatch(section);
  final tiebreak = switch (knockoutTiebreak(section)) {
    'rapid' => 'rapid tie-break games',
    'blitz' => 'blitz tie-break games',
    'armageddon' => 'armageddon tie-breaks',
    _ => 'director decides ties',
  };
  return '$games-game matches · $tiebreak';
}

/// The seeding: `bracket['seeds']` once frozen, otherwise the section's
/// players by rating (ties keep pairing-number order). A player who
/// withdrew before playing is left out; one who withdrew mid-bracket keeps
/// the seed, so the bracket does not shift under the other players.
List<String> knockoutSeeds(Event event, Section section) {
  final members = section.players.toSet();
  final played = <String>{
    for (final r in section.rounds) ...[
      for (final g in r.games) ...[g.white, g.black],
      for (final b in r.byes) b.player,
    ],
  };
  bool active(String id) => played.contains(id) || !event.player(id).withdrawn;
  final stored = <String>[
    for (final id in section.bracket['seeds'] as List? ?? const [])
      if (id is String && members.contains(id) && active(id)) id,
  ];
  final rest = [
    for (final (index, id) in section.players.indexed)
      if (!stored.contains(id) && active(id)) (index, id),
  ];
  int rating(String id) => event.player(id).effectivePairingRating;
  rest.sort((a, b) {
    final c = rating(b.$2).compareTo(rating(a.$2));
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [...stored, for (final (_, id) in rest) id];
}

/// The smallest power of two that holds [players] (at least 2).
int knockoutBracketSize(int players) {
  var size = 2;
  while (size < players) {
    size *= 2;
  }
  return size;
}

/// Bracket rounds for a field of [players].
int knockoutStages(int players) {
  var stages = 0;
  for (var size = knockoutBracketSize(players); size > 1; size ~/= 2) {
    stages++;
  }
  return stages;
}

/// Standard bracket order for [size] slots: seed 1 at the top, seed 2 at
/// the bottom, so seeds 1 and 2 can only meet in the final (1 v 16, 8 v 9,
/// 4 v 13, 5 v 12 …).
List<int> knockoutBracketOrder(int size) {
  var order = [1];
  while (order.length < size) {
    final n = order.length * 2;
    order = [
      for (final s in order) ...[s, n + 1 - s],
    ];
  }
  return order;
}

/// What the bracket calls round [stage] of [stages].
String knockoutStageName(int stage, int stages) => switch (stages - stage) {
  0 => 'Final',
  1 => 'Semifinals',
  2 => 'Quarterfinals',
  final left => 'Round of ${1 << (left + 1)}',
};

/// What a player eliminated in [stage] of [stages] placed.
String knockoutEliminatedLabel(int stage, int stages) =>
    switch (stages - stage) {
      0 => 'Runner-up',
      1 => 'Semifinalist',
      2 => 'Quarterfinalist',
      _ => knockoutStageName(stage, stages),
    };

enum KnockoutMatchStatus {
  /// Stage 1: the opponent's slot is empty, so the seed advances unplayed.
  bye,

  /// A participant is not known yet: the previous stage is unresolved.
  waiting,

  /// Both participants known; the stage has not been posted.
  unpaired,

  /// Posted games not yet reported.
  pending,

  /// Equal game points with no tie-break game or decision yet.
  tied,

  /// Someone advanced: on points, by tie-break game or by the director.
  decided,
}

/// One match of the bracket. [high] is the better seed of the two.
class KnockoutMatch {
  const KnockoutMatch({
    required this.stage,
    required this.index,
    required this.high,
    required this.low,
    required this.highSeed,
    required this.lowSeed,
    required this.games,
    required this.status,
    this.advanced,
    this.reason = '',
    this.byDirector = false,
  });
  final int stage, index;
  final String? high, low;

  /// Seed numbers (1-based); 0 for an empty slot or an unknown player.
  final int highSeed, lowSeed;
  final List<Game> games;
  final KnockoutMatchStatus status;
  final String? advanced;

  /// Why [advanced] advanced when it was not on points: a bye, an
  /// armageddon draw, or the director's reason.
  final String reason;
  final bool byDirector;

  /// The board the match is played on; 0 before it is posted.
  int get board => games.firstOrNull?.board ?? 0;

  /// Half-points scored by [high] and [low] in reported games.
  int get highPoints => _points(high);
  int get lowPoints => _points(low);
  int _points(String? id) => games.fold(
    0,
    (sum, g) =>
        sum +
        (g.white == id ? g.outcome.whiteScore : 0) +
        (g.black == id ? g.outcome.blackScore : 0),
  );

  /// The eliminated player, once the match is decided between two players.
  String? get eliminated => advanced == null || high == null || low == null
      ? null
      : advanced == high
      ? low
      : high;
  bool get resolved => advanced != null;
}

class KnockoutStage {
  const KnockoutStage({
    required this.number,
    required this.name,
    required this.matches,
    required this.rounds,
  });
  final int number;
  final String name;
  final List<KnockoutMatch> matches;

  /// The section rounds this stage was played in: the bracket round and
  /// any tie-break postings that followed it.
  final List<Round> rounds;
  bool get posted => rounds.isNotEmpty;
  bool get resolved => matches.every((m) => m.resolved);
}

class KnockoutBracket {
  const KnockoutBracket({
    required this.seeds,
    required this.size,
    required this.stages,
    required this.gamesPerMatch,
    required this.tiebreak,
  });
  final List<String> seeds;
  final int size, gamesPerMatch;
  final String tiebreak;
  final List<KnockoutStage> stages;
  int seedOf(String id) => seeds.indexOf(id) + 1;
  String? get winner => stages.lastOrNull?.matches.single.advanced;
  bool get complete => winner != null;

  /// The first stage with an unresolved match, or null once complete.
  KnockoutStage? get current => stages.where((s) => !s.resolved).firstOrNull;
}

/// The director's decisions by stage, then board.
Map<int, Map<int, (String, String)>> _decisions(Section section) {
  final out = <int, Map<int, (String, String)>>{};
  for (final entry in section.bracket['rounds'] as List? ?? const []) {
    if (entry is! Map) continue;
    final stage = entry['stage'];
    if (stage is! int) continue;
    for (final d in entry['decisions'] as List? ?? const []) {
      if (d is! Map || d['board'] is! int || d['advanced'] is! String) {
        continue;
      }
      (out[stage] ??= {})[d['board'] as int] = (
        d['advanced'] as String,
        '${d['reason'] ?? ''}',
      );
    }
  }
  return out;
}

bool _isTiebreakRound(Round round, int gamesPerMatch) =>
    round.games.isNotEmpty && round.games.every((g) => g.leg > gamesPerMatch);

/// Posted rounds grouped by bracket round: a tie-break posting belongs to
/// the bracket round before it.
List<List<Round>> _stageRounds(Section section, int gamesPerMatch) {
  final groups = <List<Round>>[];
  for (final r in section.rounds) {
    if (groups.isNotEmpty && _isTiebreakRound(r, gamesPerMatch)) {
      groups.last.add(r);
    } else {
      groups.add([r]);
    }
  }
  return groups;
}

/// The bracket as it stands, rebuilt from results and decisions.
KnockoutBracket knockoutBracket(Event event, Section section) {
  final seeds = knockoutSeeds(event, section);
  final size = knockoutBracketSize(seeds.length);
  final count = knockoutStages(seeds.length);
  final gamesPerMatch = knockoutGamesPerMatch(section);
  final tiebreak = knockoutTiebreak(section);
  final groups = _stageRounds(section, gamesPerMatch);
  final decisions = _decisions(section);
  var slots = [
    for (final s in knockoutBracketOrder(size))
      (seed: s, player: s <= seeds.length ? seeds[s - 1] : null),
  ];
  final stages = <KnockoutStage>[];
  for (var k = 1; k <= count; k++) {
    final rounds = k <= groups.length ? groups[k - 1] : const <Round>[];
    final games = rounds.expand((r) => r.games).toList();
    final matches = <KnockoutMatch>[];
    for (var i = 0; i < slots.length ~/ 2; i++) {
      var a = slots[2 * i], b = slots[2 * i + 1];
      // The better seed is "high"; an empty or unknown slot ranks last.
      if (a.player == null || (b.player != null && b.seed < a.seed)) {
        (a, b) = (b, a);
      }
      final mine =
          games
              .where(
                (g) =>
                    a.player != null &&
                    b.player != null &&
                    {g.white, g.black}.containsAll([a.player, b.player]),
              )
              .toList()
            ..sort((x, y) => x.leg.compareTo(y.leg));
      matches.add(
        _resolve(
          stage: k,
          index: i,
          high: a.player,
          highSeed: a.player == null ? 0 : a.seed,
          low: b.player,
          lowSeed: b.player == null ? 0 : b.seed,
          games: mine,
          gamesPerMatch: gamesPerMatch,
          tiebreak: tiebreak,
          decision: mine.isEmpty ? null : decisions[k]?[mine.first.board],
        ),
      );
    }
    stages.add(
      KnockoutStage(
        number: k,
        name: knockoutStageName(k, count),
        matches: matches,
        rounds: rounds,
      ),
    );
    slots = [
      for (final m in matches)
        (
          seed: m.advanced == null ? 0 : seeds.indexOf(m.advanced!) + 1,
          player: m.advanced,
        ),
    ];
  }
  return KnockoutBracket(
    seeds: seeds,
    size: size,
    stages: stages,
    gamesPerMatch: gamesPerMatch,
    tiebreak: tiebreak,
  );
}

KnockoutMatch _resolve({
  required int stage,
  required int index,
  required String? high,
  required String? low,
  required int highSeed,
  required int lowSeed,
  required List<Game> games,
  required int gamesPerMatch,
  required String tiebreak,
  required (String, String)? decision,
}) {
  KnockoutMatch result(
    KnockoutMatchStatus status, {
    String? advanced,
    String reason = '',
    bool byDirector = false,
  }) => KnockoutMatch(
    stage: stage,
    index: index,
    high: high,
    low: low,
    highSeed: highSeed,
    lowSeed: lowSeed,
    games: games,
    status: status,
    advanced: advanced,
    reason: reason,
    byDirector: byDirector,
  );
  if (high == null && low == null) return result(KnockoutMatchStatus.waiting);
  if (high == null || low == null) {
    return stage == 1
        ? result(
            KnockoutMatchStatus.bye,
            advanced: high ?? low,
            reason: 'Advances without a game',
          )
        : result(KnockoutMatchStatus.waiting);
  }
  if (games.isEmpty) return result(KnockoutMatchStatus.unpaired);
  if (games.length < gamesPerMatch || games.any((g) => !g.outcome.resolved)) {
    return result(KnockoutMatchStatus.pending);
  }
  final pending = result(KnockoutMatchStatus.pending);
  final hp = pending.highPoints, lp = pending.lowPoints;
  if (hp != lp) {
    return result(KnockoutMatchStatus.decided, advanced: hp > lp ? high : low);
  }
  final last = games.last;
  if (tiebreak == 'armageddon' &&
      last.leg > gamesPerMatch &&
      last.outcome == Outcome.draw) {
    return result(
      KnockoutMatchStatus.decided,
      advanced: last.black,
      reason: 'Armageddon draw: Black advances',
    );
  }
  if (decision != null && (decision.$1 == high || decision.$1 == low)) {
    return result(
      KnockoutMatchStatus.decided,
      advanced: decision.$1,
      reason: decision.$2,
      byDirector: true,
    );
  }
  return result(KnockoutMatchStatus.tied);
}

/// Who is white in leg [leg] of a match in bracket round [stage]: the
/// higher seed takes white in game 1 of odd-numbered rounds and black in
/// even-numbered ones, and colors alternate leg by leg, so they balance
/// across the event.
(String, String) knockoutColors(int stage, int leg, String high, String low) {
  final highWhiteFirst = stage.isOdd;
  final highWhite = leg.isOdd ? highWhiteFirst : !highWhiteFirst;
  return highWhite ? (high, low) : (low, high);
}

/// The next posting for the bracket: the next bracket round once the
/// previous one is resolved, or tie-break legs for drawn matches when the
/// section plays them. Refuses while games are unreported or a drawn match
/// waits on the director.
Round knockoutRound(Event event, Section section, int n, String Function() id) {
  if (knockoutProblem(event, section) case final problem?) {
    throw TournamentException(problem);
  }
  final bracket = knockoutBracket(event, section);
  final stage = bracket.current;
  if (stage == null) {
    throw TournamentException(
      'The bracket is complete: ${event.player(bracket.winner!).name} won the final.',
    );
  }
  String name(String? pid) => pid == null ? '—' : event.player(pid).name;
  String seeded(String? pid) =>
      pid == null ? '—' : '#${bracket.seedOf(pid)} ${name(pid)}';
  if (!stage.posted) {
    final games = <Game>[];
    final byes = <ByeAward>[];
    final explanations = <String>[];
    var board = section.boardStart;
    for (final m in stage.matches) {
      if (m.status == KnockoutMatchStatus.bye) {
        byes.add(ByeAward(m.advanced!, 0, 'Advances without a game'));
        explanations.add(
          '${seeded(m.advanced)} advances without a game (no opponent in the bracket).',
        );
        continue;
      }
      if (m.high == null || m.low == null) {
        throw TournamentException(
          'Resolve every ${bracket.stages[stage.number - 2].name} match before pairing the ${stage.name}.',
        );
      }
      for (var leg = 1; leg <= bracket.gamesPerMatch; leg++) {
        final (white, black) = knockoutColors(
          stage.number,
          leg,
          m.high!,
          m.low!,
        );
        games.add(
          Game(id: id(), white: white, black: black, board: board, leg: leg),
        );
      }
      explanations.add(
        'Board $board: ${seeded(m.high)} – ${seeded(m.low)}'
        '${stage.number == 1 ? '' : ' (winners of the ${bracket.stages[stage.number - 2].name})'}.',
      );
      board++;
    }
    return Round(
      number: n,
      games: games,
      byes: byes,
      policy: knockoutPolicy,
      note:
          '${stage.name}${stage.number == 1 ? ': seeded by rating; byes to the top seeds' : ''}.',
      explanations: explanations,
    );
  }
  final pending = stage.matches.where(
    (m) => m.status == KnockoutMatchStatus.pending,
  );
  if (pending.isNotEmpty) {
    throw TournamentException(
      'Record the ${stage.name} results on board${pending.length == 1 ? '' : 's'} ${pending.map((m) => m.board).join(', ')} before the next round.',
    );
  }
  final tied = stage.matches
      .where((m) => m.status == KnockoutMatchStatus.tied)
      .toList();
  if (tied.isEmpty) {
    // Every match has an outcome, so the stage is resolved; the caller sees
    // this only when a later stage is also unresolved, which cannot happen.
    throw const TournamentException('The bracket round is already resolved.');
  }
  if (bracket.tiebreak == 'none') {
    final m = tied.first;
    throw TournamentException(
      '${stage.name}, board ${m.board}: ${name(m.high)} and ${name(m.low)} drew the match. Choose who advances in the bracket.',
    );
  }
  final games = <Game>[];
  final explanations = <String>[];
  for (final m in tied) {
    final from = m.games.map((g) => g.leg).reduce((a, b) => a > b ? a : b) + 1;
    final legs = bracket.tiebreak == 'armageddon' ? [from] : [from, from + 1];
    for (final leg in legs) {
      final (white, black) = knockoutColors(stage.number, leg, m.high!, m.low!);
      games.add(
        Game(id: id(), white: white, black: black, board: m.board, leg: leg),
      );
    }
    explanations.add(
      'Board ${m.board}: ${seeded(m.high)} – ${seeded(m.low)} drew the match ${scoreText(m.highPoints)}–${scoreText(m.lowPoints)}; '
      '${bracket.tiebreak == 'armageddon' ? 'armageddon game ${legs.first}, ${name(games.last.white)} white: a draw advances ${name(games.last.black)}.' : '${knockoutTiebreakLabels[bracket.tiebreak]!.toLowerCase()} ${legs.first} and ${legs.last}.'}',
    );
  }
  return Round(
    number: n,
    games: games,
    policy: knockoutPolicy,
    note:
        'Tie-break games (${bracket.tiebreak}) for the ${stage.name}: '
        '${tied.map((m) => '${name(m.high)} – ${name(m.low)}').join(', ')}. The bracket round does not advance.',
    explanations: explanations,
  );
}

/// The section after a bracket posting: seeds frozen at round 1, the
/// bracket rounds as played listed with the director's decisions kept, and
/// the planned rounds equal to the bracket's stages plus the tie-break
/// postings so far.
Section knockoutAfterPost(Event event, Section section) {
  final stored = section.bracket['seeds'] as List? ?? const [];
  final frozen = section.copy(
    bracket: {
      ...section.bracket,
      'seeds': stored.isNotEmpty
          ? List<String>.from(stored)
          : knockoutSeeds(event, section),
    },
  );
  final bracket = knockoutBracket(event, frozen);
  final previous = {
    for (final entry in section.bracket['rounds'] as List? ?? const [])
      if (entry is Map && entry['stage'] is int)
        entry['stage'] as int: [
          for (final d in entry['decisions'] as List? ?? const [])
            if (d is Map) Map<String, dynamic>.from(d),
        ],
  };
  var tiebreakRounds = 0;
  final rounds = <Json>[];
  for (final stage in bracket.stages.where((s) => s.posted)) {
    tiebreakRounds += stage.rounds.length - 1;
    rounds.add({
      'stage': stage.number,
      'name': stage.name,
      'rounds': [for (final r in stage.rounds) r.number],
      'decisions': previous[stage.number] ?? const [],
    });
  }
  return frozen.copy(
    bracket: {...frozen.bracket, 'rounds': rounds},
    plannedRounds: bracket.stages.length + tiebreakRounds,
  );
}

/// The section with the director's decision that [playerId] advances from
/// the drawn match on [board]. Refuses unless the match is drawn and the
/// following bracket round has not been posted.
Section knockoutDecided(
  Event event,
  Section section,
  int board,
  String playerId,
  String reason,
) {
  final bracket = knockoutBracket(event, section);
  // Every bracket round reuses the boards from the first, so a board names
  // the latest match on it, or an earlier one that [playerId] played there.
  final onBoard = [
    for (final s in bracket.stages.where((s) => s.posted))
      if (s.matches.where((m) => m.board == board).firstOrNull case final m?)
        (s, m),
  ];
  final (stage, match) =
      onBoard.reversed
          .where((e) => e.$2.high == playerId || e.$2.low == playerId)
          .firstOrNull ??
      onBoard.lastOrNull ??
      (null, null);
  if (stage == null || match == null) {
    throw TournamentException('No bracket match is on board $board.');
  }
  if (match.status != KnockoutMatchStatus.tied && !match.byDirector) {
    throw TournamentException(
      match.status == KnockoutMatchStatus.pending
          ? 'Board $board still has unreported games.'
          : 'Board $board was decided on the board: ${event.player(match.advanced!).name} advanced.',
    );
  }
  if (bracket.stages.length > stage.number &&
      bracket.stages[stage.number].posted) {
    throw TournamentException(
      'The ${bracket.stages[stage.number].name} has been posted. Replace its pairings before changing who advanced.',
    );
  }
  if (playerId != match.high && playerId != match.low) {
    throw TournamentException(
      'Choose ${event.player(match.high!).name} or ${event.player(match.low!).name}.',
    );
  }
  final text = reason.trim().isEmpty ? 'Director’s decision' : reason.trim();
  final rounds = [
    for (final entry in section.bracket['rounds'] as List? ?? const [])
      if (entry is Map) Map<String, dynamic>.from(entry),
  ];
  var entry = rounds.where((r) => r['stage'] == stage.number).firstOrNull;
  if (entry == null) {
    entry = {
      'stage': stage.number,
      'name': stage.name,
      'rounds': [for (final r in stage.rounds) r.number],
      'decisions': const [],
    };
    rounds.add(entry);
  }
  entry['decisions'] = [
    for (final d in entry['decisions'] as List? ?? const [])
      if (d is Map && d['board'] != board) Map<String, dynamic>.from(d),
    {'board': board, 'advanced': playerId, 'reason': text},
  ];
  return section.copy(bracket: {...section.bracket, 'rounds': rounds});
}

/// Placement rather than points: Winner, Runner-up, Semifinalist, and so
/// on, in that order; players still in the bracket come first by seed.
List<(String playerId, String placing)> knockoutPlacings(
  Event event,
  Section section,
) {
  final bracket = knockoutBracket(event, section);
  final count = bracket.stages.length;
  final placed = <String, (int, String)>{};
  for (final stage in bracket.stages) {
    for (final m in stage.matches) {
      if (m.eliminated case final out?) {
        placed[out] = (
          count - stage.number + 2,
          knockoutEliminatedLabel(stage.number, count),
        );
      }
      if (stage.number == count && m.advanced != null) {
        placed[m.advanced!] = (1, 'Winner');
      }
    }
  }
  final current = bracket.current;
  final rows = <(int, int, String, String)>[
    for (final (i, id) in bracket.seeds.indexed)
      if (placed[id] case (final rank, final label))
        (rank, i, id, label)
      else
        (1, i, id, 'In the ${current?.name ?? 'bracket'}'),
  ];
  rows.sort(
    (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
  );
  return [for (final r in rows) (r.$3, r.$4)];
}

/// The match score as seen from [high]: each leg, then the total.
String knockoutMatchScore(KnockoutMatch m) {
  if (m.games.isEmpty) return '';
  String leg(Game g) {
    final highWhite = g.white == m.high;
    return switch (g.outcome) {
      Outcome.unreported => '—',
      Outcome.unfinished => 'playing',
      Outcome.disputed => 'disputed',
      Outcome.doubleForfeit => 'F–F',
      Outcome.whiteForfeit => highWhite ? 'X–F' : 'F–X',
      Outcome.blackForfeit => highWhite ? 'F–X' : 'X–F',
      _ =>
        '${scoreText(highWhite ? g.outcome.whiteScore : g.outcome.blackScore)}–'
            '${scoreText(highWhite ? g.outcome.blackScore : g.outcome.whiteScore)}',
    };
  }

  final legs = m.games.map(leg).join(' ');
  return m.games.length == 1
      ? legs
      : '$legs (${scoreText(m.highPoints)}–${scoreText(m.lowPoints)})';
}

/// The bracket as plain text for the crosstable export and the standings
/// PDF: one line per match per stage, then the placings.
List<String> knockoutBracketLines(Event event, Section section) {
  final bracket = knockoutBracket(event, section);
  String name(String? id) => id == null ? '—' : event.player(id).name;
  String seeded(String? id) =>
      id == null ? '—' : '#${bracket.seedOf(id)} ${name(id)}';
  final lines = <String>['Bracket: ${knockoutSummary(section)}'];
  for (final stage in bracket.stages) {
    lines.add(stage.name);
    for (final m in stage.matches) {
      final outcome = switch (m.status) {
        KnockoutMatchStatus.bye =>
          '${name(m.advanced)} advances without a game',
        KnockoutMatchStatus.waiting => 'waiting for the previous round',
        KnockoutMatchStatus.unpaired => 'not yet paired',
        KnockoutMatchStatus.pending => 'in progress',
        KnockoutMatchStatus.tied => 'drawn match; who advances is undecided',
        KnockoutMatchStatus.decided =>
          '${name(m.advanced)} advances${m.reason.isEmpty ? '' : ' (${m.reason})'}',
      };
      final board = m.board == 0 ? '' : 'Board ${m.board}: ';
      final score = knockoutMatchScore(m);
      lines.add(
        '  $board${seeded(m.high)} – ${seeded(m.low)}'
        '${score.isEmpty ? '' : '  $score'}  $outcome',
      );
    }
  }
  lines.add(
    'Placings: ${knockoutPlacings(event, section).map((p) => '${name(p.$1)} – ${p.$2}').join('; ')}',
  );
  return lines;
}
