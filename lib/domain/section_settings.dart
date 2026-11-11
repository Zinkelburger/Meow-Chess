import 'model.dart';

// Typed section and event settings. Each is read once, when the event is
// decoded, and written back exactly as it was read: the settings objects
// keep the stored JSON they came from, so a file that is opened and saved
// again is byte for byte the same, unknown keys and key order included.
// Settings built in code are stored in the order they always have been.

/// Rule 28R: accelerated pairings for rounds 1–2. A FIDE-rated Swiss may
/// use only [baku], the Baku Acceleration Method (C.04.7 1). Announced
/// before round 1.
enum Acceleration {
  none(''),

  /// 28R1: the top half plays as if it had an extra point.
  addedScore('addedScore'),

  /// 28R2: each half of the field is paired as its own score group.
  adjustedRating('adjustedRating'),

  /// 28R3: the same by thirds.
  sixths('sixths'),

  /// C.04.7 1: the Baku Acceleration Method.
  baku('baku');

  const Acceleration(this.code);

  /// As stored under `Section.accelerated`.
  final String code;

  static Acceleration parse(String code) =>
      values.where((a) => a.code == code).firstOrNull ??
      (throw const TournamentException('Invalid accelerated pairing method.'));
}

/// Rule 29E2 / 28J: the round-1 coin toss, shared by every section.
enum ColorToss {
  /// Before round 1 is posted.
  none(''),
  higherWhite('higherWhite'),
  higherBlack('higherBlack');

  const ColorToss(this.code);

  /// As stored under `Event.colorToss`.
  final String code;

  static ColorToss parse(String code) =>
      values.where((t) => t.code == code).firstOrNull ??
      (throw const TournamentException('Invalid round-1 color toss.'));
}

/// An announced pairing variation the Swiss engine understands, by rule.
enum Variation {
  lowerRankedColorPriority(
    '29E4a',
    'Color priority to the lower-ranked player in minus score groups',
  ),
  alternatingColorPriority(
    '29E4b',
    'Alternating color priority within a score group',
  ),
  rankColorPriority(
    '29E4d',
    'Color priority by rank after two identical rounds',
  ),
  equalizeOverRatings(
    '29E5h',
    'Equalization over ratings: no 80/200-point limits',
  ),
  byeForColors('28L2a', 'Bye to a higher-rated player when it improves colors'),
  classPairings(
    '29I',
    'Class pairings in the last round, each class as its own Swiss',
  ),
  partialClassPairings(
    '29I2',
    'Partial class pairings in the last round: class-prize contenders',
  ),
  unratedsTogether('29J', 'Unrateds on plus scores paired together'),
  reentryLatestScore(
    '28S5latest',
    'Re-entries carry the latest score, not the better one',
  );

  const Variation(this.code, this.label);

  /// The rule number, as stored in `Section.variations`.
  final String code;
  final String label;

  static Variation parse(String code) =>
      values.where((v) => v.code == code).firstOrNull ??
      (throw TournamentException(
        'Unknown pairing variation "$code". Use ${values.map((v) => v.code).join(', ')}.',
      ));

  /// [variations] as stored: their codes, sorted.
  static List<String> codes(Iterable<Variation> variations) =>
      [for (final v in variations) v.code]..sort();
}

/// A Holland stage's role ([Holland.role]).
enum HollandRole {
  none(''),
  prelim('prelim'),
  finalStage('final');

  const HollandRole(this.code);
  final String code;

  /// Any other stored role belongs to neither stage, as it always has.
  static HollandRole read(Object? code) =>
      values.where((r) => r.code == code && r != none).firstOrNull ?? none;
}

/// Rule 30H / 30I: the section's place in a Holland system, stored as
/// `Section.holland` = {group, role, qualifiers, unbalanced}.
class Holland {
  const Holland({
    this.group = '',
    this.role = HollandRole.none,
    this.qualifiers = 1,
    this.unbalanced = false,
  }) : _stored = null;

  Holland._(
    Json stored, {
    required this.group,
    required this.role,
    required this.qualifiers,
    required this.unbalanced,
  }) : _stored = Map.unmodifiable(stored);

  factory Holland.fromJson(Json j) => Holland._(
    j,
    group: (j['group'] as String?) ?? '',
    role: HollandRole.read(j['role']),
    qualifiers: (j['qualifiers'] as int?) ?? 1,
    unbalanced: j['unbalanced'] == true,
  );

  /// Shared by the prelims and their final; empty outside a Holland.
  final String group;
  final HollandRole role;

  /// How many advance from each prelim.
  final int qualifiers;

  /// Rule 30I: prelims of unequal strength.
  final bool unbalanced;
  final Json? _stored;

  bool get _blank =>
      group.isEmpty &&
      role == HollandRole.none &&
      qualifiers == 1 &&
      !unbalanced;

  Json toJson() =>
      _stored ??
      (_blank
          ? const {}
          : {
              'group': group,
              'role': role.code,
              'qualifiers': qualifiers,
              'unbalanced': unbalanced,
            });
}

/// What happens when a knockout match is drawn.
enum KnockoutTiebreak {
  none('none', 'Director decides'),
  rapid('rapid', 'Rapid games'),
  blitz('blitz', 'Blitz games'),
  armageddon('armageddon', 'Armageddon');

  const KnockoutTiebreak(this.code, this.label);

  /// As stored under `bracket['tiebreak']`.
  final String code;
  final String label;
}

/// Why these stored bracket settings cannot be used, or null.
String? knockoutSettingsProblem(Json bracket) {
  final games = bracket['gamesPerMatch'] ?? 2;
  if (games is! int || (games != 1 && games != 2)) {
    return 'Matches of 1 or 2 games are supported. Choose 1 or 2 games per match.';
  }
  final tiebreak = bracket['tiebreak'] ?? 'none';
  if (tiebreak is! String ||
      !KnockoutTiebreak.values.any((t) => t.code == tiebreak)) {
    return 'Tie-break must be ${KnockoutTiebreak.values.map((t) => t.code).join(', ')}.';
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

/// A knockout section's bracket, stored as `Section.bracket`: the match
/// rules (`gamesPerMatch`, `tiebreak`), the `seeds` frozen when round 1 is
/// posted, and the bracket `rounds` as played with the director's
/// decisions on drawn matches. See knockout.dart.
class Bracket {
  const Bracket()
    : gamesPerMatch = 2,
      tiebreak = KnockoutTiebreak.none,
      seeds = const [],
      rounds = const [],
      problem = null,
      _stored = const {};

  Bracket._(
    Json stored, {
    required this.gamesPerMatch,
    required this.tiebreak,
    required List<String> seeds,
    required List<BracketRound> rounds,
    required this.problem,
  }) : seeds = List.unmodifiable(seeds),
       rounds = List.unmodifiable(rounds),
       _stored = Map.unmodifiable(stored);

  /// Reads whatever is stored. Settings that cannot be used are kept, with
  /// [problem] saying why; the readers below fall back to the defaults.
  factory Bracket.fromJson(Json j) {
    final seeds = j['seeds'], rounds = j['rounds'], tiebreak = j['tiebreak'];
    return Bracket._(
      j,
      gamesPerMatch: switch (j['gamesPerMatch']) {
        final int n => n,
        final num n => n.toInt(),
        _ => 2,
      },
      tiebreak:
          KnockoutTiebreak.values
              .where((t) => t.code == tiebreak)
              .firstOrNull ??
          KnockoutTiebreak.none,
      seeds: [
        if (seeds is List)
          for (final id in seeds)
            if (id is String) id,
      ],
      rounds: [
        if (rounds is List)
          for (final r in rounds)
            if (r is Map) BracketRound.fromJson(Map<String, dynamic>.from(r)),
      ],
      problem: knockoutSettingsProblem(j),
    );
  }

  /// Games in each match: 1, or 2 (one with each color). The default is 2.
  final int gamesPerMatch;
  final KnockoutTiebreak tiebreak;

  /// Player IDs in seeding order; empty until round 1 is posted.
  final List<String> seeds;

  /// The bracket rounds as played.
  final List<BracketRound> rounds;

  /// Why the stored settings cannot be used, or null.
  final String? problem;
  final Json _stored;

  Json toJson() => _stored;

  /// The bracket with these settings changed and everything else as stored.
  Bracket withSettings(Json settings) =>
      Bracket.fromJson({..._stored, ...settings});

  Bracket withSeeds(List<String> seeds) =>
      Bracket.fromJson({..._stored, 'seeds': seeds});

  Bracket withRounds(List<BracketRound> rounds) => Bracket.fromJson({
    ..._stored,
    'rounds': [for (final r in rounds) r.toJson()],
  });

  /// The match rules without the seeds and rounds, which name players.
  Bracket get rulesOnly => Bracket.fromJson({
    for (final e in _stored.entries)
      if (e.key != 'seeds' && e.key != 'rounds') e.key: e.value,
  });
}

/// One bracket round as played: its `stage` (1 for the first), `name`, the
/// section `rounds` it took (tie-break postings included) and the
/// director's `decisions` on its drawn matches.
class BracketRound {
  BracketRound({
    required int this.stage,
    required this.name,
    required List<int> rounds,
    List<BracketDecision> decisions = const [],
  }) : rounds = List.unmodifiable(rounds),
       decisions = List.unmodifiable(decisions),
       _stored = null;

  BracketRound._(
    Json stored, {
    required this.stage,
    required this.name,
    required List<int> rounds,
    required List<BracketDecision> decisions,
  }) : rounds = List.unmodifiable(rounds),
       decisions = List.unmodifiable(decisions),
       _stored = Map.unmodifiable(stored);

  factory BracketRound.fromJson(Json j) {
    final rounds = j['rounds'], decisions = j['decisions'];
    return BracketRound._(
      j,
      stage: j['stage'] is int ? j['stage'] as int : null,
      name: j['name'] is String ? j['name'] as String : '',
      rounds: [
        if (rounds is List)
          for (final r in rounds)
            if (r is int) r,
      ],
      decisions: [
        if (decisions is List)
          for (final d in decisions)
            if (d is Map)
              BracketDecision.fromJson(Map<String, dynamic>.from(d)),
      ],
    );
  }

  /// Null when the stored stage is not a number; such a record is kept as
  /// it is, but no stage reads it.
  final int? stage;
  final String name;
  final List<int> rounds;
  final List<BracketDecision> decisions;
  final Json? _stored;

  Json toJson() =>
      _stored ??
      {
        'stage': stage,
        'name': name,
        'rounds': rounds,
        'decisions': [for (final d in decisions) d.toJson()],
      };

  /// The round with [decisions] in place of its own, the rest as stored.
  BracketRound withDecisions(List<BracketDecision> decisions) =>
      BracketRound.fromJson({
        ...toJson(),
        'decisions': [for (final d in decisions) d.toJson()],
      });
}

/// The director's decision that [advanced] goes through from the drawn
/// match on [board].
class BracketDecision {
  BracketDecision({
    required int this.board,
    required String this.advanced,
    required String this.reason,
  }) : _stored = null;

  BracketDecision._(
    Json stored, {
    required this.board,
    required this.advanced,
    required this.reason,
  }) : _stored = Map.unmodifiable(stored);

  factory BracketDecision.fromJson(Json j) => BracketDecision._(
    j,
    board: j['board'] is int ? j['board'] as int : null,
    advanced: j['advanced'] is String ? j['advanced'] as String : null,
    reason: j['reason'] == null ? null : '${j['reason']}',
  );

  /// Null when the stored value is missing or of the wrong kind; a
  /// decision without both is kept but decides nothing.
  final int? board;
  final String? advanced;
  final String? reason;
  final Json? _stored;

  bool get decides => board != null && advanced != null;

  Json toJson() =>
      _stored ?? {'board': board, 'advanced': advanced, 'reason': reason};
}
