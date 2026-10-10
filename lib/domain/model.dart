import 'dart:convert';

import 'us_chess.dart';

/// Scores are stored as integer half-points. IDs never depend on list order.
String scoreText(int halves) =>
    halves.isEven ? '${halves ~/ 2}' : '${halves ~/ 2}.5';
typedef Json = Map<String, dynamic>;
const _unset = Object();

/// How a section is paired. The first three are the common formats; the
/// rest are the rulebook's and the club scene's rarer ones, offered behind
/// "Other format" in the section panel.
enum Format {
  quad,
  swiss,
  roundRobin,

  /// Two sides (teams) where every player meets every opposing player on a
  /// fixed table; rounds = boards. Side A is [Section.homeTeam].
  scheveningen,

  /// A single-elimination bracket of mini-matches ([Section.bracket]).
  knockout,

  /// A standing challenge list: positions are the order of
  /// [Section.players]; games are recorded by hand and swap positions.
  ladder,

  /// Two-player partnerships paired as a Swiss on match score; always
  /// unrated ([Section.partners]).
  bughouse;

  /// The label a director sees.
  String get label => switch (this) {
    quad => 'Quads',
    swiss => 'Swiss',
    roundRobin => 'Round robin',
    scheveningen => 'Scheveningen',
    knockout => 'Knockout',
    ladder => 'Ladder',
    bughouse => 'Bughouse',
  };

  /// The three everyday formats sit on the format row; the others are
  /// disclosed behind "Other format".
  bool get common => index <= roundRobin.index;
}

enum Outcome {
  unreported,
  whiteWin,
  draw,
  blackWin,
  whiteForfeit,
  blackForfeit,
  doubleForfeit,
  unfinished,
  disputed;

  bool get resolved => ![unreported, unfinished, disputed].contains(this);
  bool get played => [whiteWin, draw, blackWin].contains(this);
  int get whiteScore => switch (this) {
    whiteWin || whiteForfeit => 2,
    draw => 1,
    _ => 0,
  };
  int get blackScore => switch (this) {
    blackWin || blackForfeit => 2,
    draw => 1,
    _ => 0,
  };
  String get label => switch (this) {
    unreported => '—',
    whiteWin => '1–0',
    draw => '½–½',
    blackWin => '0–1',
    whiteForfeit => 'X–F',
    blackForfeit => 'F–X',
    doubleForfeit => 'F–F',
    unfinished => 'Playing',
    disputed => 'Disputed',
  };
}

class Player {
  Player({
    required this.id,
    required this.name,
    this.memberId = '',
    this.rating = 0,
    this.checkedIn = false,
    this.withdrawn = false,
    this.club = '',
    this.team = '',
    Set<String> avoid = const {},
    this.notes = '',
    this.registrationNote = '',
    this.source = '',
    Map<int, int> byes = const {},
    this.personId,
    this.house = false,
    this.state = '',
    this.reportName = '',
    Json ratingEvidence = const {},
    Json membershipEvidence = const {},
    this.pairingRating = 0,
    this.prizeRating = 0,
    this.ratingNote = '',
    this.foreignRating = 0,
    this.foreignFederation = '',
    this.fixedBoard = 0,
    this.reentryOf = '',
    Set<int> irrevocableByes = const {},
    this.computer = false,
  }) : membershipEvidence = Map.unmodifiable(membershipEvidence),
       ratingEvidence = Map.unmodifiable(ratingEvidence),
       byes = Map.unmodifiable(byes),
       irrevocableByes = Set.unmodifiable(irrevocableByes),
       avoid = Set.unmodifiable(avoid);
  final String id, name, memberId, club, team, notes, source;

  /// Rule 28A TIP / 28F: a rating assigned for pairing only, or for prizes
  /// only. Zero means the published [rating] serves that purpose.
  final int pairingRating, prizeRating;

  /// Rule 28E: the stated cause for a TD-assigned rating.
  final String ratingNote;

  /// Rule 28C2 / 28D1: a disclosed foreign rating and its federation
  /// (`FIDE`, `CFC`, …) before conversion. Zero when none was disclosed.
  final int foreignRating;
  final String foreignFederation;

  /// Rule 20M3 / 35: a board this player always sits at. Zero means the
  /// board follows pairing order.
  final int fixedBoard;

  /// Rule 28S: the ID of this person's earlier entry in the same event,
  /// which this re-entry replaced. Empty for a first entry.
  final String reentryOf;

  /// Rule 22C4: rounds whose requested bye the player declared irrevocable.
  final Set<int> irrevocableByes;

  /// Rule 36: a computer entrant, never paired against another computer.
  final bool computer;

  /// The rating the pairing engine ranks by (rule 28A TIP, 28F).
  int get effectivePairingRating => pairingRating > 0 ? pairingRating : rating;

  /// The rating prize eligibility uses (rule 28F).
  int get effectivePrizeRating => prizeRating > 0 ? prizeRating : rating;

  /// Rule 28L2: an unrated player has no published rating and no assigned
  /// pairing rating.
  bool get unrated => effectivePairingRating == 0;

  /// Free-form registration text from the roster source, separate from private notes.
  final String registrationNote;

  /// Two-letter state for the rating report; empty when unknown.
  final String state;

  /// The name as US Chess should receive it (`LAST, FIRST`); empty to derive
  /// it from [name].
  final String reportName;
  final Json ratingEvidence;

  /// Membership observations are independent of pairing ratings.
  final Json membershipEvidence;
  final Set<String> avoid;
  final String? personId;
  final int rating;
  final bool checkedIn, withdrawn, house;
  final Map<int, int> byes;
  Player copy({
    String? name,
    String? memberId,
    int? rating,
    bool? checkedIn,
    bool? withdrawn,
    String? club,
    String? team,
    Set<String>? avoid,
    String? notes,
    String? registrationNote,
    Map<int, int>? byes,
    bool? house,
    String? state,
    String? reportName,
    Json? ratingEvidence,
    Json? membershipEvidence,
    int? pairingRating,
    int? prizeRating,
    String? ratingNote,
    int? foreignRating,
    String? foreignFederation,
    int? fixedBoard,
    String? reentryOf,
    Set<int>? irrevocableByes,
    bool? computer,
  }) => Player(
    id: id,
    personId: personId,
    name: name ?? this.name,
    memberId: memberId ?? this.memberId,
    rating: rating ?? this.rating,
    checkedIn: checkedIn ?? this.checkedIn,
    withdrawn: withdrawn ?? this.withdrawn,
    club: club ?? this.club,
    team: team ?? this.team,
    avoid: avoid ?? this.avoid,
    notes: notes ?? this.notes,
    registrationNote: registrationNote ?? this.registrationNote,
    source: source,
    byes: byes ?? this.byes,
    house: house ?? this.house,
    state: state ?? this.state,
    reportName: reportName ?? this.reportName,
    ratingEvidence: ratingEvidence ?? this.ratingEvidence,
    membershipEvidence: memberId != null && memberId != this.memberId
        ? const {}
        : membershipEvidence ?? this.membershipEvidence,
    pairingRating: pairingRating ?? this.pairingRating,
    prizeRating: prizeRating ?? this.prizeRating,
    ratingNote: ratingNote ?? this.ratingNote,
    foreignRating: foreignRating ?? this.foreignRating,
    foreignFederation: foreignFederation ?? this.foreignFederation,
    fixedBoard: fixedBoard ?? this.fixedBoard,
    reentryOf: reentryOf ?? this.reentryOf,
    irrevocableByes: irrevocableByes ?? this.irrevocableByes,
    computer: computer ?? this.computer,
  );
  Json toJson() => {
    'id': id,
    'personId': personId ?? id,
    'name': name,
    'memberId': memberId,
    'rating': rating,
    'checkedIn': checkedIn,
    'withdrawn': withdrawn,
    'club': club,
    'team': team,
    'avoid': avoid.toList()..sort(),
    'notes': notes,
    'registrationNote': registrationNote,
    'source': source,
    'house': house,
    'byes': byes.map((k, v) => MapEntry('$k', v)),
    'state': state,
    'reportName': reportName,
    'ratingEvidence': ratingEvidence,
    'membershipEvidence': membershipEvidence,
    if (pairingRating != 0) 'pairingRating': pairingRating,
    if (prizeRating != 0) 'prizeRating': prizeRating,
    if (ratingNote.isNotEmpty) 'ratingNote': ratingNote,
    if (foreignRating != 0) 'foreignRating': foreignRating,
    if (foreignFederation.isNotEmpty) 'foreignFederation': foreignFederation,
    if (fixedBoard != 0) 'fixedBoard': fixedBoard,
    if (reentryOf.isNotEmpty) 'reentryOf': reentryOf,
    if (irrevocableByes.isNotEmpty)
      'irrevocableByes': irrevocableByes.toList()..sort(),
    if (computer) 'computer': computer,
  };
  factory Player.fromJson(Json j) => Player(
    id: j['id'],
    personId: j['personId'],
    name: j['name'],
    memberId: j['memberId'],
    rating: j['rating'],
    checkedIn: j['checkedIn'],
    withdrawn: j['withdrawn'],
    club: j['club'],
    team: j['team'] ?? '',
    avoid: Set<String>.from(j['avoid'] ?? const []),
    notes: j['notes'],
    registrationNote: j['registrationNote'] ?? '',
    source: j['source'],
    house: j['house'] ?? false,
    byes: (j['byes'] as Map).map((k, v) => MapEntry(int.parse(k), v as int)),
    state: j['state'] ?? '',
    reportName: j['reportName'] ?? '',
    ratingEvidence: Map<String, dynamic>.from(j['ratingEvidence'] ?? {}),
    membershipEvidence: Map<String, dynamic>.from(
      j['membershipEvidence'] ??
          (j['ratingEvidence'] is Map &&
                  (j['ratingEvidence'] as Map).containsKey('expiration')
              ? j['ratingEvidence']
              : const {}),
    ),
    pairingRating: j['pairingRating'] ?? 0,
    prizeRating: j['prizeRating'] ?? 0,
    ratingNote: j['ratingNote'] ?? '',
    foreignRating: j['foreignRating'] ?? 0,
    foreignFederation: j['foreignFederation'] ?? '',
    fixedBoard: j['fixedBoard'] ?? 0,
    reentryOf: j['reentryOf'] ?? '',
    irrevocableByes: {
      for (final r in j['irrevocableByes'] as List? ?? const []) r as int,
    },
    computer: j['computer'] ?? false,
  );
}

class Game {
  const Game({
    required this.id,
    required this.white,
    required this.black,
    required this.board,
    this.leg = 1,
    this.outcome = Outcome.unreported,
    this.note = '',
    this.pairingAssumption,
    this.pairingReason = '',
    this.adjudicated = false,
    this.prizeOutcome,
    this.whitePartner = '',
    this.blackPartner = '',
  });
  final String id, white, black, note;

  /// Bughouse: the second-board partner of each side. The game is one match
  /// result for the partnership; empty for ordinary chess.
  final String whitePartner, blackPartner;
  final int board, leg;
  final Outcome outcome;
  final Outcome? pairingAssumption;
  final String pairingReason;

  /// Rule 18G: the result was adjudicated by the director, not played out.
  final bool adjudicated;

  /// Rule 15I / 22C5 / 28M4: the result that counts for prizes when it
  /// differs from [outcome] (which is what the wall chart and the rating
  /// report carry). Null means prizes use [outcome].
  final Outcome? prizeOutcome;
  Game copy({
    String? id,
    Outcome? outcome,
    String? white,
    String? black,
    int? board,
    String? note,
    Object? pairingAssumption = _unset,
    String? pairingReason,
    bool? adjudicated,
    Object? prizeOutcome = _unset,
    String? whitePartner,
    String? blackPartner,
  }) => Game(
    id: id ?? this.id,
    white: white ?? this.white,
    black: black ?? this.black,
    board: board ?? this.board,
    leg: leg,
    outcome: outcome ?? this.outcome,
    note: note ?? this.note,
    pairingAssumption: identical(pairingAssumption, _unset)
        ? this.pairingAssumption
        : pairingAssumption as Outcome?,
    pairingReason: pairingReason ?? this.pairingReason,
    adjudicated: adjudicated ?? this.adjudicated,
    prizeOutcome: identical(prizeOutcome, _unset)
        ? this.prizeOutcome
        : prizeOutcome as Outcome?,
    whitePartner: whitePartner ?? this.whitePartner,
    blackPartner: blackPartner ?? this.blackPartner,
  );
  Json toJson() => {
    'id': id,
    'white': white,
    'black': black,
    'board': board,
    'leg': leg,
    'outcome': outcome.name,
    'note': note,
    'pairingAssumption': pairingAssumption?.name,
    'pairingReason': pairingReason,
    if (adjudicated) 'adjudicated': adjudicated,
    if (prizeOutcome != null) 'prizeOutcome': prizeOutcome!.name,
    if (whitePartner.isNotEmpty) 'whitePartner': whitePartner,
    if (blackPartner.isNotEmpty) 'blackPartner': blackPartner,
  };
  factory Game.fromJson(Json j) => Game(
    id: j['id'],
    white: j['white'],
    black: j['black'],
    board: j['board'],
    leg: j['leg'],
    outcome: Outcome.values.byName(j['outcome']),
    note: j['note'],
    pairingAssumption: j['pairingAssumption'] == null
        ? null
        : Outcome.values.byName(j['pairingAssumption']),
    pairingReason: j['pairingReason'] ?? '',
    adjudicated: j['adjudicated'] ?? false,
    prizeOutcome: j['prizeOutcome'] == null
        ? null
        : Outcome.values.byName(j['prizeOutcome']),
    whitePartner: j['whitePartner'] ?? '',
    blackPartner: j['blackPartner'] ?? '',
  );
}

class ByeAward {
  const ByeAward(
    this.player,
    this.points,
    this.reason, {
    this.allocated = false,
  });
  final String player, reason;
  final int points;
  final bool allocated;
  Json toJson() => {
    'player': player,
    'points': points,
    'reason': reason,
    'allocated': allocated,
  };
  factory ByeAward.fromJson(Json j) => ByeAward(
    j['player'],
    j['points'],
    j['reason'],
    allocated: j['allocated'],
  );
}

class Round {
  Round({
    required this.number,
    required List<Game> games,
    List<ByeAward> byes = const [],
    this.postedAt,
    this.startedAt,
    this.revision = 1,
    this.policy = 'quad-30G-v1',
    this.note = '',
    List<String> explanations = const [],
  }) : games = List.unmodifiable(games),
       explanations = List.unmodifiable(explanations),
       byes = List.unmodifiable(byes);
  final int number, revision;
  final List<Game> games;
  final List<ByeAward> byes;
  final String? postedAt, startedAt;
  final String policy, note;

  /// Rule 29E TIP: why each pairing decision was made (transpositions,
  /// interchanges, drop-downs, the bye), for the director's review.
  final List<String> explanations;
  bool get complete => games.every((g) => g.outcome.resolved);
  bool get hasPlay =>
      startedAt != null || games.any((g) => g.outcome != Outcome.unreported);
  Round copy({
    List<Game>? games,
    List<ByeAward>? byes,
    String? postedAt,
    String? startedAt,
    int? revision,
    String? note,
    List<String>? explanations,
  }) => Round(
    number: number,
    games: games ?? this.games,
    byes: byes ?? this.byes,
    postedAt: postedAt ?? this.postedAt,
    startedAt: startedAt ?? this.startedAt,
    revision: revision ?? this.revision,
    policy: policy,
    note: note ?? this.note,
    explanations: explanations ?? this.explanations,
  );
  Json toJson() => {
    'number': number,
    'games': games.map((g) => g.toJson()).toList(),
    'byes': byes.map((b) => b.toJson()).toList(),
    'postedAt': postedAt,
    'startedAt': startedAt,
    'revision': revision,
    'policy': policy,
    'note': note,
    if (explanations.isNotEmpty) 'explanations': explanations,
  };
  factory Round.fromJson(Json j) => Round(
    number: j['number'],
    games: (j['games'] as List).map((g) => Game.fromJson(g)).toList(),
    byes: (j['byes'] as List).map((b) => ByeAward.fromJson(b)).toList(),
    postedAt: j['postedAt'],
    startedAt: j['startedAt'],
    revision: j['revision'],
    policy: j['policy'],
    note: j['note'],
    explanations: List<String>.from(j['explanations'] ?? const []),
  );
}

class Section {
  Section({
    required this.id,
    required this.name,
    required List<String> players,
    this.format = Format.swiss,
    this.plannedRounds = 3,
    this.boardStart = 1,
    this.doubleGames = false,
    List<Round> rounds = const [],
    this.ratingCeiling = 0,
    this.timeControl = '',
    this.sideGames = false,
    List<List<int>> quadPairings = const [],
    this.accelerated = '',
    this.avoidTeammates = false,
    Set<String> variations = const {},
    Json byeRules = const {},
    Json prizes = const {},
    this.rrTable = '',
    this.doubleCycle = false,
    this.homeTeam = '',
    Json holland = const {},
    Json bracket = const {},
    List<List<String>> partners = const [],
    this.unrated = false,
  }) : players = List.unmodifiable(players),
       holland = Map.unmodifiable(holland),
       bracket = Map.unmodifiable(bracket),
       partners = List.unmodifiable(
         partners.map((p) => List<String>.unmodifiable(p)),
       ),
       quadPairings = List.unmodifiable(
         quadPairings.map((r) => List<int>.unmodifiable(r)),
       ),
       variations = Set.unmodifiable(variations),
       byeRules = Map.unmodifiable(byeRules),
       prizes = Map.unmodifiable(prizes),
       rounds = List.unmodifiable(rounds);
  final String id, name;

  /// Rule 28R: accelerated pairings. Empty for none, `addedScore` (28R1) or
  /// `adjustedRating` (28R2). Announced before round 1.
  final String accelerated;

  /// Rule 28N: avoid pairing team-mates using the plus-two method.
  final bool avoidTeammates;

  /// Announced pairing variations by rule number, such as `29E4a`,
  /// `29E5b1`, `29E5f1`, `29E5h`, `29E6b`, `29E8`, `29I`, `29J`, `28L2a`.
  final Set<String> variations;

  /// Rule 22C: announced bye availability. Keys: `lastHalfByeRound` (the
  /// last round a half-point bye may be requested for; 0 = any round),
  /// `maxHalfByes` (0 = unlimited), `deadlineMinutes` (before the round;
  /// default 60), `irrevocableFromRound` (byes for this round and later
  /// must be declared irrevocable; 0 = never).
  final Json byeRules;

  /// Rules 32–33: the announced prize table and payout terms. See
  /// `prizes.dart` for the schema.
  final Json prizes;

  /// Rule 30A: the round-robin table. Empty keeps the circle method
  /// (`circle-rr-v1`); `crenshaw` uses the Crenshaw-Berger tables.
  final String rrTable;

  /// Rule 30F: a double round robin played as a second cycle with colors
  /// reversed, instead of both games in the same round.
  final bool doubleCycle;

  /// Scheveningen: the team label of side A; every other player is side B.
  final String homeTeam;

  /// Rule 30H / 30I Holland system. Keys: `group` (shared by the prelims and
  /// their final), `role` (`prelim` or `final`), `qualifiers` (how many
  /// advance from each prelim), `unbalanced` (30I).
  final Json holland;

  /// Knockout bracket. Keys: `gamesPerMatch` (default 2), `tiebreak`
  /// (`none`, `rapid`, `blitz`, `armageddon`; default `none`), `seeds`
  /// (player IDs in seeding order), `rounds` (the bracket as played).
  final Json bracket;

  /// Bughouse partnerships: two player IDs each.
  final List<List<String>> partners;

  /// Left out of the rating report (bughouse, ladders, unrated events).
  final bool unrated;

  /// Empty inherits the event default. Ladders may use different controls.
  final String timeControl;
  final bool sideGames;
  String effectiveTimeControl(Event event) =>
      timeControl.isEmpty ? event.timeControl : timeControl;
  final List<String> players;
  final Format format;
  final int plannedRounds, boardStart, ratingCeiling;
  final bool doubleGames;
  final List<Round> rounds;

  /// Results may arrive out of order, or an earlier result may be reopened.
  /// Every unresolved persisted round still reserves its players and boards.
  Iterable<Round> get unresolvedRounds => rounds.where((r) => !r.complete);

  /// Three rounds of White/Black roster slots, independent of player identity.
  /// Empty uses the standard quad schedule.
  final List<List<int>> quadPairings;

  /// A ladder has no planned round count: it is finished whenever every
  /// recorded challenge game has a result.
  bool get finished => format == Format.ladder
      ? rounds.isNotEmpty && rounds.every((r) => r.complete)
      : rounds.length >= plannedRounds && rounds.every((r) => r.complete);
  Section copy({
    String? name,
    List<String>? players,
    Format? format,
    int? plannedRounds,
    int? boardStart,
    bool? doubleGames,
    List<Round>? rounds,
    int? ratingCeiling,
    String? timeControl,
    bool? sideGames,
    List<List<int>>? quadPairings,
    String? accelerated,
    bool? avoidTeammates,
    Set<String>? variations,
    Json? byeRules,
    Json? prizes,
    String? rrTable,
    bool? doubleCycle,
    String? homeTeam,
    Json? holland,
    Json? bracket,
    List<List<String>>? partners,
    bool? unrated,
  }) => Section(
    id: id,
    name: name ?? this.name,
    players: players ?? this.players,
    format: format ?? this.format,
    plannedRounds: plannedRounds ?? this.plannedRounds,
    boardStart: boardStart ?? this.boardStart,
    doubleGames: doubleGames ?? this.doubleGames,
    rounds: rounds ?? this.rounds,
    ratingCeiling: ratingCeiling ?? this.ratingCeiling,
    timeControl: timeControl ?? this.timeControl,
    sideGames: sideGames ?? this.sideGames,
    quadPairings: quadPairings ?? this.quadPairings,
    accelerated: accelerated ?? this.accelerated,
    avoidTeammates: avoidTeammates ?? this.avoidTeammates,
    variations: variations ?? this.variations,
    byeRules: byeRules ?? this.byeRules,
    prizes: prizes ?? this.prizes,
    rrTable: rrTable ?? this.rrTable,
    doubleCycle: doubleCycle ?? this.doubleCycle,
    homeTeam: homeTeam ?? this.homeTeam,
    holland: holland ?? this.holland,
    bracket: bracket ?? this.bracket,
    partners: partners ?? this.partners,
    unrated: unrated ?? this.unrated,
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'players': players,
    'format': format.name,
    'plannedRounds': plannedRounds,
    'boardStart': boardStart,
    'doubleGames': doubleGames,
    'rounds': rounds.map((r) => r.toJson()).toList(),
    'ratingCeiling': ratingCeiling,
    'timeControl': timeControl,
    'sideGames': sideGames,
    if (quadPairings.isNotEmpty) 'quadPairings': quadPairings,
    if (accelerated.isNotEmpty) 'accelerated': accelerated,
    if (avoidTeammates) 'avoidTeammates': avoidTeammates,
    if (variations.isNotEmpty) 'variations': variations.toList()..sort(),
    if (byeRules.isNotEmpty) 'byeRules': byeRules,
    if (prizes.isNotEmpty) 'prizes': prizes,
    if (rrTable.isNotEmpty) 'rrTable': rrTable,
    if (doubleCycle) 'doubleCycle': doubleCycle,
    if (homeTeam.isNotEmpty) 'homeTeam': homeTeam,
    if (holland.isNotEmpty) 'holland': holland,
    if (bracket.isNotEmpty) 'bracket': bracket,
    if (partners.isNotEmpty) 'partners': partners,
    if (unrated) 'unrated': unrated,
  };
  factory Section.fromJson(Json j) => Section(
    id: j['id'],
    name: j['name'],
    players: List<String>.from(j['players']),
    format: Format.values.byName(j['format']),
    plannedRounds: j['plannedRounds'],
    boardStart: j['boardStart'],
    doubleGames: j['doubleGames'],
    rounds: (j['rounds'] as List).map((r) => Round.fromJson(r)).toList(),
    ratingCeiling: j['ratingCeiling'] ?? 0,
    timeControl: j['timeControl'] ?? '',
    sideGames: j['sideGames'] ?? false,
    quadPairings: [
      for (final r in j['quadPairings'] as List? ?? const []) List<int>.from(r),
    ],
    accelerated: j['accelerated'] ?? '',
    avoidTeammates: j['avoidTeammates'] ?? false,
    variations: Set<String>.from(j['variations'] ?? const []),
    byeRules: Map<String, dynamic>.from(j['byeRules'] ?? const {}),
    prizes: Map<String, dynamic>.from(j['prizes'] ?? const {}),
    rrTable: j['rrTable'] ?? '',
    doubleCycle: j['doubleCycle'] ?? false,
    homeTeam: j['homeTeam'] ?? '',
    holland: Map<String, dynamic>.from(j['holland'] ?? const {}),
    bracket: Map<String, dynamic>.from(j['bracket'] ?? const {}),
    partners: [
      for (final p in j['partners'] as List? ?? const []) List<String>.from(p),
    ],
    unrated: j['unrated'] ?? false,
  );
}

class Event {
  Event({
    required this.id,
    required this.name,
    required this.date,
    this.revision = 0,
    this.timeControl = 'G/65 d10',
    this.venue = '',
    this.tdId = '',
    this.assistantTdId = '',
    this.otherTdIds = '',
    this.affiliateId = '',
    this.practice = false,
    this.backupFolder = '',
    this.lastBackupRevision,
    List<Player> players = const [],
    List<Section> sections = const [],
    List<Json> transitions = const [],
    this.notes = '',
    this.submission = '',
    Json rosterSource = const {},
    this.endDate = '',
    this.city = '',
    this.state = '',
    this.zip = '',
    this.level = 'N',
    this.useTiebreaks = false,
    this.policy =
        'Requested byes: ½ point before the round is posted. Equal scores share a place unless tie-break rankings are enabled.',
    this.colorToss = '',
    List<String> tiebreaks = const [],
    this.online = false,
    List<Json> rulings = const [],
  }) : rosterSource = Map.unmodifiable(rosterSource),
       players = List.unmodifiable(players),
       sections = List.unmodifiable(sections),
       tiebreaks = List.unmodifiable(tiebreaks),
       rulings = List.unmodifiable(
         rulings.map((r) => Map<String, dynamic>.unmodifiable(r)),
       ),
       transitions = List.unmodifiable(
         transitions.map((t) => Map<String, dynamic>.unmodifiable(t)),
       );

  /// Rule 29E2 / 28J: the round-1 coin toss, shared by every section.
  /// `higherWhite` or `higherBlack` once tossed; empty before round 1.
  final String colorToss;

  /// Rule 34B: the announced tie-break order, by method code (see
  /// `tiebreaks.dart`). Empty means the US Chess default order.
  final List<String> tiebreaks;

  /// Chapter 10: an online event, reported with online rating categories.
  final bool online;

  /// Rules 13I, 20K, 21H–L, 18G: the ruling, penalty and appeal log.
  /// Each entry has `id`, `at`, `kind`, `round`, `section`, `players`,
  /// `text`, `decidedBy` and `outcome`.
  final List<Json> rulings;
  final String id,
      name,
      date,
      timeControl,
      venue,
      tdId,
      affiliateId,
      backupFolder,
      notes,
      submission,
      policy;

  /// Last day of a multi-day event; empty for a one-day event.
  final String endDate;

  /// Assistant chief TD's US Chess ID (`H_ATD_ID`/`S_ATD_ID`) and the other
  /// TDs who worked the event, comma separated (`H_OTHER_TD`). US Chess
  /// credits them as event officials from the report.
  final String assistantTdId, otherTdIds;

  /// Rating report location and 2C section type (`S_SCH_LVL`).
  final String city, state, zip, level;
  String get lastDate => endDate.isEmpty ? date : endDate;
  final int revision;
  final int? lastBackupRevision;
  final bool practice;
  final bool useTiebreaks;
  final Json rosterSource;
  final List<Player> players;
  final List<Section> sections;
  final List<Json> transitions;
  Player player(String id) => players.firstWhere(
    (p) => p.id == id,
    orElse: () => throw TournamentException('No player has the ID "$id".'),
  );
  Section? sectionOf(String id) =>
      sections.where((s) => s.players.contains(id)).firstOrNull;
  Iterable<Game> get games =>
      sections.expand((s) => s.rounds).expand((r) => r.games);
  Event copy({
    String? name,
    String? date,
    String? timeControl,
    String? venue,
    String? tdId,
    String? assistantTdId,
    String? otherTdIds,
    String? affiliateId,
    int? revision,
    bool? practice,
    String? backupFolder,
    Object? lastBackupRevision = _unset,
    List<Player>? players,
    List<Section>? sections,
    List<Json>? transitions,
    String? notes,
    String? submission,
    Json? rosterSource,
    String? policy,
    String? endDate,
    String? city,
    String? state,
    String? zip,
    String? level,
    bool? useTiebreaks,
    String? colorToss,
    List<String>? tiebreaks,
    bool? online,
    List<Json>? rulings,
  }) => Event(
    id: id,
    name: name ?? this.name,
    date: date ?? this.date,
    timeControl: timeControl ?? this.timeControl,
    venue: venue ?? this.venue,
    tdId: tdId ?? this.tdId,
    assistantTdId: assistantTdId ?? this.assistantTdId,
    otherTdIds: otherTdIds ?? this.otherTdIds,
    affiliateId: affiliateId ?? this.affiliateId,
    revision: revision ?? this.revision,
    practice: practice ?? this.practice,
    backupFolder: backupFolder ?? this.backupFolder,
    lastBackupRevision: identical(lastBackupRevision, _unset)
        ? this.lastBackupRevision
        : lastBackupRevision as int?,
    players: players ?? this.players,
    sections: sections ?? this.sections,
    transitions: transitions ?? this.transitions,
    notes: notes ?? this.notes,
    submission: submission ?? this.submission,
    rosterSource: rosterSource ?? this.rosterSource,
    policy: policy ?? this.policy,
    endDate: endDate ?? this.endDate,
    city: city ?? this.city,
    state: state ?? this.state,
    zip: zip ?? this.zip,
    level: level ?? this.level,
    useTiebreaks: useTiebreaks ?? this.useTiebreaks,
    colorToss: colorToss ?? this.colorToss,
    tiebreaks: tiebreaks ?? this.tiebreaks,
    online: online ?? this.online,
    rulings: rulings ?? this.rulings,
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'date': date,
    'timeControl': timeControl,
    'venue': venue,
    'tdId': tdId,
    'assistantTdId': assistantTdId,
    'otherTdIds': otherTdIds,
    'affiliateId': affiliateId,
    'revision': revision,
    'practice': practice,
    'backupFolder': backupFolder,
    'lastBackupRevision': lastBackupRevision,
    'players': players.map((p) => p.toJson()).toList(),
    'sections': sections.map((s) => s.toJson()).toList(),
    'transitions': transitions,
    'notes': notes,
    'submission': submission,
    'rosterSource': rosterSource,
    'policy': policy,
    'endDate': endDate,
    'city': city,
    'state': state,
    'zip': zip,
    'level': level,
    'useTiebreaks': useTiebreaks,
    if (colorToss.isNotEmpty) 'colorToss': colorToss,
    if (tiebreaks.isNotEmpty) 'tiebreaks': tiebreaks,
    if (online) 'online': online,
    if (rulings.isNotEmpty) 'rulings': rulings,
  };
  factory Event.fromJson(Json j) => Event(
    id: j['id'],
    name: j['name'],
    date: j['date'],
    useTiebreaks: j['useTiebreaks'] ?? false,
    timeControl: j['timeControl'],
    venue: j['venue'],
    tdId: j['tdId'],
    assistantTdId: j['assistantTdId'] ?? '',
    otherTdIds: j['otherTdIds'] ?? '',
    affiliateId: j['affiliateId'],
    revision: j['revision'],
    practice: j['practice'],
    backupFolder: j['backupFolder'],
    lastBackupRevision: j['lastBackupRevision'],
    players: (j['players'] as List).map((p) => Player.fromJson(p)).toList(),
    sections: (j['sections'] as List).map((s) => Section.fromJson(s)).toList(),
    transitions: List<Json>.from(j['transitions']),
    notes: j['notes'] ?? '',
    submission: j['submission'] ?? '',
    rosterSource: Map<String, dynamic>.from(j['rosterSource'] ?? {}),
    policy: j['policy'] ?? '',
    endDate: j['endDate'] ?? '',
    city: j['city'] ?? '',
    state: j['state'] ?? '',
    zip: j['zip'] ?? '',
    level: j['level'] ?? 'N',
    colorToss: j['colorToss'] ?? '',
    tiebreaks: List<String>.from(j['tiebreaks'] ?? const []),
    online: j['online'] ?? false,
    rulings: List<Json>.from(
      (j['rulings'] as List? ?? const []).map(
        (r) => Map<String, dynamic>.from(r as Map),
      ),
    ),
  );
  String encode() => jsonEncode(toJson());
  factory Event.decode(String source) => Event.fromJson(jsonDecode(source));
}

/// Why [playerId] can no longer be removed from the event, or null while
/// they can. Removal is only for entries that never took part: once their
/// section is paired, or a round anywhere names them, they withdraw instead.
/// Unpairing the section makes them removable again.
String? removeBlocker(Event e, String playerId) {
  final p = e.player(playerId), s = e.sectionOf(playerId);
  if (s != null && s.rounds.isNotEmpty) {
    return '${s.name} has been paired. Withdraw ${p.name} instead.';
  }
  final named = e.sections
      .expand((s) => s.rounds)
      .any(
        (r) =>
            r.byes.any((b) => b.player == playerId) ||
            r.games.any((g) => g.white == playerId || g.black == playerId),
      );
  final transferred = e.transitions.any(
    (t) =>
        (t['effectiveRound'] as int) > 1 &&
        (t['players'] as List).contains(playerId),
  );
  if (named || transferred) {
    return '${p.name} has played in this event. Withdraw them instead.';
  }
  return null;
}

/// The first board after every board [sections] use.
int nextBoard(Iterable<Section> sections) => sections.fold(1, (max, s) {
  final end = s.boardStart + (s.players.length + 1) ~/ 2;
  return end > max ? end : max;
});

/// Ids of the sections that moving all of [players] out would leave empty.
Set<String> sectionsEmptiedBy(Event e, Set<String> players) => {
  for (final s in e.sections)
    if (s.players.isNotEmpty && s.players.every(players.contains)) s.id,
};

/// Which of [incoming] are new to a roster of [existing] players, in order.
/// A member ID is identity; a name only identifies someone when either side
/// lacks an ID, so two members who share a name are both admitted.
List<Player> newEntries(Iterable<Player> existing, Iterable<Player> incoming) {
  // The 2C placeholder `00000000` identifies nobody.
  final ids = {
    for (final p in existing)
      if (isMemberId(p.memberId)) p.memberId,
  };
  // Name -> whether every entry with that name has a member ID.
  final names = <String, bool>{};
  void remember(Player p) {
    final key = nameKey(p.name);
    names[key] = (names[key] ?? true) && isMemberId(p.memberId);
  }

  existing.forEach(remember);
  final additions = <Player>[];
  for (final player in incoming) {
    final identified = isMemberId(player.memberId);
    if (identified && ids.contains(player.memberId)) continue;
    final allIdentified = names[nameKey(player.name)];
    if (allIdentified != null && !(allIdentified && identified)) {
      continue;
    }
    if (identified) ids.add(player.memberId);
    remember(player);
    additions.add(player);
  }
  return additions;
}

class TournamentException implements Exception {
  const TournamentException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Official event dates are calendar dates, never instants: `2026-02-30` and
/// `2026-9-1` are rejected rather than normalized.
bool isEventDate(String date) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return false;
  final parsed = DateTime.tryParse(date);
  return parsed != null && parsed.toIso8601String().startsWith(date);
}

void validateEvent(Event e) {
  void require(bool ok, String message) {
    if (!ok) throw TournamentException(message);
  }

  require(e.name.trim().isNotEmpty, 'Give the event a name.');
  require(isEventDate(e.date), 'Use a valid YYYY-MM-DD event date.');
  require(
    e.endDate.isEmpty ||
        (isEventDate(e.endDate) && e.endDate.compareTo(e.date) >= 0),
    'The end date must be a valid YYYY-MM-DD date on or after the start date.',
  );
  require(
    e.players.map((p) => p.id).toSet().length == e.players.length,
    'Duplicate entry identity.',
  );
  require(
    e.sections.map((s) => s.id).toSet().length == e.sections.length,
    'Duplicate section identity.',
  );
  final assigned = <String>{};
  final gameIds = <String>{};
  final ids = e.players.map((p) => p.id).toSet();
  for (final p in e.players) {
    require(p.name.trim().isNotEmpty, 'Player names cannot be empty.');
    require(
      p.rating >= 0 && p.rating <= 4000,
      'Rating must be between 0 and 4000.',
    );
    // Files may hold the 2C placeholder `00000000` ("ID unavailable");
    // identity and rating checks treat it as no ID ([isMemberId]).
    require(
      p.memberId.isEmpty || RegExp(r'^\d{8}$').hasMatch(p.memberId),
      'US Chess IDs must contain eight digits.',
    );
    require(
      p.state.isEmpty || RegExp(r'^[A-Z]{2}$').hasMatch(p.state),
      'A player\'s state must be two capital letters.',
    );
    require(
      p.byes.entries.every((b) => b.key > 0 && b.value >= 0 && b.value <= 2),
      'Invalid bye reservation.',
    );
    require(
      [
        p.pairingRating,
        p.prizeRating,
        p.foreignRating,
      ].every((r) => r >= 0 && r <= 4000),
      'Assigned ratings must be between 0 and 4000.',
    );
    require(p.fixedBoard >= 0, 'A fixed board number must be 1 or more.');
    require(
      p.reentryOf.isEmpty || (p.reentryOf != p.id && ids.contains(p.reentryOf)),
      'A re-entry must name an earlier entry in this event.',
    );
    require(
      p.irrevocableByes.every((r) => r > 0),
      'Invalid irrevocable bye round.',
    );
  }
  require(
    ['', 'higherWhite', 'higherBlack'].contains(e.colorToss),
    'Invalid round-1 color toss.',
  );
  final liveBoards = <int>{};
  final livePeople = <String>{};
  for (final s in e.sections) {
    final sectionPeople = <String>{};
    if (s.quadPairings.isNotEmpty) {
      require(
        s.quadPairings.length == 3 &&
            s.quadPairings.every(
              (r) =>
                  r.length == 4 &&
                  r.toSet().length == 4 &&
                  r.every((slot) => slot >= 0 && slot < 4),
            ),
        'A manual quad schedule needs four distinct roster slots in each of three rounds.',
      );
      final opponents = <String>{};
      for (final row in s.quadPairings) {
        for (var i = 0; i < 4; i += 2) {
          final pair = [row[i], row[i + 1]]..sort();
          require(
            opponents.add(pair.join('-')),
            'A quad must pair each opponent once.',
          );
        }
      }
    }
    require(
      s.name.trim().isNotEmpty && s.plannedRounds > 0 && s.boardStart > 0,
      'Invalid section settings.',
    );
    require(
      ['', 'addedScore', 'adjustedRating'].contains(s.accelerated),
      'Invalid accelerated pairing method.',
    );
    require(['', 'crenshaw'].contains(s.rrTable), 'Invalid round-robin table.');
    final partnered = <String>{};
    for (final pair in s.partners) {
      require(
        pair.length == 2 &&
            pair[0] != pair[1] &&
            pair.every((id) => s.players.contains(id) && partnered.add(id)),
        'A bughouse partnership is two distinct players of the section, each in one partnership.',
      );
    }
    require(
      s.format != Format.bughouse || s.unrated,
      'Bughouse sections are always unrated.',
    );
    for (final id in s.players) {
      require(
        ids.contains(id) && assigned.add(id),
        'An entry belongs to more than one active section.',
      );
      require(
        sectionPeople.add(e.player(id).personId ?? id),
        'A person cannot have two entries in the same section.',
      );
    }
    final liveGames = s.unresolvedRounds.expand((r) => r.games).toList();
    if (liveGames.isNotEmpty) {
      final sectionBoards = liveGames.map((g) => g.board).toSet();
      for (final board in sectionBoards) {
        require(
          liveBoards.add(board),
          'Two active sections reserve the same board.',
        );
      }
      final people = liveGames
          .where((g) => !g.outcome.resolved)
          .expand((g) => [g.white, g.black])
          .toSet();
      for (final id in people) {
        require(ids.contains(id), 'Unknown player in an active round.');
        require(
          livePeople.add(e.player(id).personId ?? id),
          'A person is scheduled in two active sections.',
        );
      }
    }
    for (var i = 0; i < s.rounds.length; i++) {
      final r = s.rounds[i];
      require(r.number == i + 1, 'Round history must be consecutive.');
      final participants = <String>{};
      final boards = <String>{};
      for (final g in r.games) {
        require(gameIds.add(g.id), 'Duplicate game identity.');
        require(
          g.pairingAssumption == null ||
              (!g.outcome.resolved &&
                  g.pairingAssumption!.played &&
                  g.pairingReason.trim().isNotEmpty),
          'A temporary pairing treatment needs an unresolved game and a reason.',
        );
        require(
          ids.contains(g.white) && ids.contains(g.black) && g.white != g.black,
          'A game needs two distinct registered entries.',
        );
        require(
          g.board > 0 && boards.add('${g.board}/${g.leg}'),
          'Board collision inside a round.',
        );
        require(
          participants.add('${g.white}/${g.leg}') &&
              participants.add('${g.black}/${g.leg}'),
          'A player is paired twice in one leg.',
        );
      }
      for (final b in r.byes) {
        require(
          ids.contains(b.player) &&
              participants.add('${b.player}/1') &&
              b.points >= 0 &&
              b.points <= (s.doubleGames ? 4 : 2),
          'A bye conflicts with a game or another bye.',
        );
      }
    }
  }
}
