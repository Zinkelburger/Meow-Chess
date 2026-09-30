import 'dart:convert';

/// Scores are stored as integer half-points. IDs never depend on list order.
String scoreText(int halves) =>
    halves.isEven ? '${halves ~/ 2}' : '${halves ~/ 2}.5';
typedef Json = Map<String, dynamic>;
const _unset = Object();

enum Format { quad, swiss, roundRobin }

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
  }) : byes = Map.unmodifiable(byes),
       avoid = Set.unmodifiable(avoid);
  final String id, name, memberId, club, team, notes, source;
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
  }) : games = List.unmodifiable(games),
       byes = List.unmodifiable(byes);
  final int number, revision;
  final List<Game> games;
  final List<ByeAward> byes;
  final String? postedAt, startedAt;
  final String policy, note;
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
  }) : players = List.unmodifiable(players),
       rounds = List.unmodifiable(rounds);
  final String id, name;
  final List<String> players;
  final Format format;
  final int plannedRounds, boardStart, ratingCeiling;
  final bool doubleGames;
  final List<Round> rounds;
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
    require(
      p.memberId.isEmpty || RegExp(r'^\d{8}$').hasMatch(p.memberId),
      'US Chess IDs must contain eight digits.',
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
              b.points <= 2,
          'A bye conflicts with a game or another bye.',
        );
      }
    }
  }
}
