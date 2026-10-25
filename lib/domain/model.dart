import 'dart:convert';

/// Scores are stored as integer half-points. IDs never depend on list order.
String scoreText(int halves) =>
    halves.isEven ? '${halves ~/ 2}' : '${halves ~/ 2}.5';

int parsePoints(String text) {
  if (!RegExp(r'^\d+(\.0|\.5)?$').hasMatch(text.trim())) {
    throw const TournamentException(
      'Use whole or half points, such as 1 or 0.5.',
    );
  }
  final parts = text.trim().split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null || whole > 10) {
    throw const TournamentException('Points must be between 0 and 10.');
  }
  final value = whole * 2 + (parts.length == 2 && parts[1] == '5' ? 1 : 0);
  if (value > 20) {
    throw const TournamentException('Points must be between 0 and 10.');
  }
  return value;
}

typedef Json = Map<String, dynamic>;
const _unset = Object();

enum Format { quad, swiss, roundRobin }

enum TiebreakOrder {
  buchholzSonneborn('Buchholz, then Sonneborn-Berger'),
  sonnebornBuchholz('Sonneborn-Berger, then Buchholz'),
  buchholz('Buchholz only'),
  scoreOnly('Score only (share places)');

  const TiebreakOrder(this.label);
  final String label;
}

/// Competition points are separate from the actual result sent for rating.
/// All values are exact half-points, including in nonstandard scoring events.
class Scoring {
  const Scoring({this.win = 2, this.draw = 1, this.loss = 0, this.bye = 2});
  final int win, draw, loss, bye;
  int points(Outcome outcome, bool white) => switch (outcome) {
    Outcome.whiteWin => white ? win : loss,
    Outcome.blackWin => white ? loss : win,
    Outcome.whiteForfeit => white ? win : 0,
    Outcome.blackForfeit => white ? 0 : win,
    Outcome.draw => draw,
    _ => 0,
  };
  Json toJson() => {'win': win, 'draw': draw, 'loss': loss, 'bye': bye};
  factory Scoring.fromJson(Json j) =>
      Scoring(win: j['win'], draw: j['draw'], loss: j['loss'], bye: j['bye']);
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
    whiteForfeit => '1F–0F',
    blackForfeit => '0F–1F',
    doubleForfeit => '0F–0F',
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
    this.source = '',
    Map<int, int> byes = const {},
    this.personId,
    this.house = false,
    this.state = '',
    this.reportName = '',
    this.title = '',
    this.fideId = '',
    this.federation = '',
    this.birthDate = '',
    this.school = '',
    this.grade = '',
    this.fideRating = 0,
  }) : byes = Map.unmodifiable(byes),
       avoid = Set.unmodifiable(avoid);
  final String id, name, memberId, club, team, notes, source;

  /// Two-letter state for the rating report; empty when unknown.
  final String state;

  /// The name as US Chess should receive it (`LAST, FIRST`); empty to derive
  /// it from [name].
  final String reportName;

  /// Optional registration details; they do not change US Chess pairing ratings.
  final String title, fideId, federation, birthDate, school, grade;
  final int fideRating;
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
    Map<int, int>? byes,
    bool? house,
    String? state,
    String? reportName,
    String? title,
    String? fideId,
    String? federation,
    String? birthDate,
    String? school,
    String? grade,
    int? fideRating,
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
    source: source,
    byes: byes ?? this.byes,
    house: house ?? this.house,
    state: state ?? this.state,
    reportName: reportName ?? this.reportName,
    title: title ?? this.title,
    fideId: fideId ?? this.fideId,
    federation: federation ?? this.federation,
    birthDate: birthDate ?? this.birthDate,
    school: school ?? this.school,
    grade: grade ?? this.grade,
    fideRating: fideRating ?? this.fideRating,
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
    'source': source,
    'house': house,
    'byes': byes.map((k, v) => MapEntry('$k', v)),
    'state': state,
    'reportName': reportName,
    'title': title,
    'fideId': fideId,
    'federation': federation,
    'birthDate': birthDate,
    'school': school,
    'grade': grade,
    'fideRating': fideRating,
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
    source: j['source'],
    house: j['house'] ?? false,
    byes: (j['byes'] as Map).map((k, v) => MapEntry(int.parse(k), v as int)),
    state: j['state'] ?? '',
    reportName: j['reportName'] ?? '',
    title: j['title'] ?? '',
    fideId: j['fideId'] ?? '',
    federation: j['federation'] ?? '',
    birthDate: j['birthDate'] ?? '',
    school: j['school'] ?? '',
    grade: j['grade'] ?? '',
    fideRating: j['fideRating'] ?? 0,
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
  });
  final String id, white, black, note;
  final int board, leg;
  final Outcome outcome;
  final Outcome? pairingAssumption;
  final String pairingReason;
  Game copy({
    Outcome? outcome,
    String? white,
    String? black,
    int? board,
    String? note,
    Object? pairingAssumption = _unset,
    String? pairingReason,
  }) => Game(
    id: id,
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
    this.pairingInput = '',
    List<String> warnings = const [],
  }) : games = List.unmodifiable(games),
       byes = List.unmodifiable(byes),
       warnings = List.unmodifiable(warnings);
  final int number, revision;
  final List<Game> games;
  final List<ByeAward> byes;
  final String? postedAt, startedAt;
  final String policy, note;

  /// Versioned, immutable Swiss inputs for reproducible checks after edits.
  final String pairingInput;
  final List<String> warnings;
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
  }) => Round(
    number: number,
    games: games ?? this.games,
    byes: byes ?? this.byes,
    postedAt: postedAt ?? this.postedAt,
    startedAt: startedAt ?? this.startedAt,
    revision: revision ?? this.revision,
    policy: policy,
    note: note ?? this.note,
    pairingInput: pairingInput,
    warnings: warnings,
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
    'pairingInput': pairingInput,
    'warnings': warnings,
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
    pairingInput: j['pairingInput'] ?? '',
    warnings: List<String>.from(j['warnings'] ?? const []),
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
    this.scoring = const Scoring(),
    this.tiebreakOrder = TiebreakOrder.buchholzSonneborn,
    this.firstColorWhite = true,
    Map<String, List<int>> acceleration = const {},
  }) : players = List.unmodifiable(players),
       rounds = List.unmodifiable(rounds),
       acceleration = Map.unmodifiable(
         acceleration.map(
           (id, points) => MapEntry(id, List<int>.unmodifiable(points)),
         ),
       );
  final String id, name;
  final List<String> players;
  final Format format;
  final int plannedRounds, boardStart, ratingCeiling;
  final bool doubleGames;
  final List<Round> rounds;
  final Scoring scoring;
  final TiebreakOrder tiebreakOrder;
  final bool firstColorWhite;

  /// Per-player, per-round pairing-only half-points; never competition points.
  final Map<String, List<int>> acceleration;
  int accelerationFor(String id, int round) {
    final points = acceleration[id];
    return points != null && round > 0 && round <= points.length
        ? points[round - 1]
        : 0;
  }

  bool get finished =>
      rounds.length >= plannedRounds && rounds.every((r) => r.complete);
  Section copy({
    String? name,
    List<String>? players,
    Format? format,
    int? plannedRounds,
    int? boardStart,
    bool? doubleGames,
    List<Round>? rounds,
    int? ratingCeiling,
    Scoring? scoring,
    TiebreakOrder? tiebreakOrder,
    bool? firstColorWhite,
    Map<String, List<int>>? acceleration,
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
    scoring: scoring ?? this.scoring,
    tiebreakOrder: tiebreakOrder ?? this.tiebreakOrder,
    firstColorWhite: firstColorWhite ?? this.firstColorWhite,
    acceleration: acceleration ?? this.acceleration,
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
    'scoring': scoring.toJson(),
    'tiebreakOrder': tiebreakOrder.name,
    'firstColorWhite': firstColorWhite,
    'acceleration': acceleration,
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
    scoring: j['scoring'] == null
        ? const Scoring()
        : Scoring.fromJson(j['scoring']),
    tiebreakOrder: TiebreakOrder.values.byName(
      j['tiebreakOrder'] ?? 'buchholzSonneborn',
    ),
    firstColorWhite: j['firstColorWhite'] ?? true,
    acceleration: (j['acceleration'] as Map? ?? const {}).map(
      (id, points) => MapEntry(id as String, List<int>.from(points)),
    ),
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
    this.affiliateId = '',
    this.practice = false,
    this.backupFolder = '',
    this.lastBackupRevision,
    List<Player> players = const [],
    List<Section> sections = const [],
    List<Json> transitions = const [],
    this.notes = '',
    this.submission = '',
    this.endDate = '',
    this.city = '',
    this.state = '',
    this.zip = '',
    this.level = 'N',
    this.policy =
        'Requested byes: ½ point before the round is posted. Standings: points, then Buchholz, then Sonneborn–Berger.',
  }) : players = List.unmodifiable(players),
       sections = List.unmodifiable(sections),
       transitions = List.unmodifiable(
         transitions.map((t) => Map<String, dynamic>.unmodifiable(t)),
       );
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

  /// Rating report location and 2C section type (`S_SCH_LVL`).
  final String city, state, zip, level;
  String get lastDate => endDate.isEmpty ? date : endDate;
  final int revision;
  final int? lastBackupRevision;
  final bool practice;
  final List<Player> players;
  final List<Section> sections;
  final List<Json> transitions;
  Player player(String id) => players.firstWhere((p) => p.id == id);
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
    String? policy,
    String? endDate,
    String? city,
    String? state,
    String? zip,
    String? level,
  }) => Event(
    id: id,
    name: name ?? this.name,
    date: date ?? this.date,
    timeControl: timeControl ?? this.timeControl,
    venue: venue ?? this.venue,
    tdId: tdId ?? this.tdId,
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
    policy: policy ?? this.policy,
    endDate: endDate ?? this.endDate,
    city: city ?? this.city,
    state: state ?? this.state,
    zip: zip ?? this.zip,
    level: level ?? this.level,
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'date': date,
    'timeControl': timeControl,
    'venue': venue,
    'tdId': tdId,
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
    'policy': policy,
    'endDate': endDate,
    'city': city,
    'state': state,
    'zip': zip,
    'level': level,
  };
  factory Event.fromJson(Json j) => Event(
    id: j['id'],
    name: j['name'],
    date: j['date'],
    timeControl: j['timeControl'],
    venue: j['venue'],
    tdId: j['tdId'],
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
    policy: j['policy'] ?? '',
    endDate: j['endDate'] ?? '',
    city: j['city'] ?? '',
    state: j['state'] ?? '',
    zip: j['zip'] ?? '',
    level: j['level'] ?? 'N',
  );
  String encode() => jsonEncode(toJson());
  factory Event.decode(String source) => Event.fromJson(jsonDecode(source));
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
    final detailError = playerDetailsError(p);
    require(detailError == null, detailError ?? 'Invalid player details.');
    require(
      p.rating >= 0 && p.rating <= 4000,
      'Rating must be between 0 and 4000.',
    );
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
  }
  final liveBoards = <int>{};
  final livePeople = <String>{};
  for (final s in e.sections) {
    require(
      [
            s.scoring.win,
            s.scoring.draw,
            s.scoring.loss,
            s.scoring.bye,
          ].every((p) => p >= 0 && p <= 20) &&
          s.scoring.win > s.scoring.draw &&
          s.scoring.draw >= s.scoring.loss,
      'Scoring needs win > draw >= loss, with values between 0 and 10 points.',
    );
    require(
      s.acceleration.entries.every(
        (a) =>
            ids.contains(a.key) &&
            a.value.length <= s.plannedRounds &&
            a.value.every((p) => p >= 0 && p <= 20),
      ),
      'Acceleration needs known players and 0–10 pairing-only points per scheduled round.',
    );
    require(
      s.name.trim().isNotEmpty && s.plannedRounds > 0 && s.boardStart > 0,
      'Invalid section settings.',
    );
    for (final id in s.players) {
      require(
        ids.contains(id) && assigned.add(id),
        'An entry belongs to more than one active section.',
      );
    }
    final latest = s.rounds.lastOrNull;
    if (latest != null && !latest.complete) {
      final sectionBoards = latest.games.map((g) => g.board).toSet();
      for (final board in sectionBoards) {
        require(
          liveBoards.add(board),
          'Two active sections reserve the same board.',
        );
      }
      final people = latest.games.expand((g) => [g.white, g.black]).toSet();
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
              b.points <= 20,
          'A bye conflicts with a game or another bye.',
        );
      }
    }
  }
}

/// Shared by typed registration and roster import, before any data is saved.
String? playerDetailsError(Player p) {
  if (p.fideId.isNotEmpty && !RegExp(r'^[1-9]\d{0,10}$').hasMatch(p.fideId)) {
    return 'FIDE ID must be 1–11 digits and start with a nonzero digit.';
  }
  if (p.fideRating < 0 || p.fideRating > 4000) {
    return 'FIDE rating must be 0–4000, or UNR.';
  }
  if (p.federation.isNotEmpty &&
      !RegExp(r'^[A-Z]{3}$').hasMatch(p.federation)) {
    return 'Federation must be three capital letters, such as USA.';
  }
  if (p.birthDate.isNotEmpty && !isEventDate(p.birthDate)) {
    return 'Birth date must be a valid YYYY-MM-DD date.';
  }
  return null;
}
