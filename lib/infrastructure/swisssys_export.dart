/// SwissSys 9 section files, for programs that read them: chiefly the ones
/// clubs use to put pairings and board numbers on a screen.
///
/// A section file is an Excel 97 workbook of four sheets. `Players` has one
/// row per player, and every other sheet names a player by that row's
/// number. `Results` has each player's opponent, color and result round by
/// round, `Tables` is the current round's board list, and `Settings` is one
/// row of section options. Scores are in half-points; White is 1 and Black
/// is -1; an opponent of -1 is no opponent.
///
/// The file is named for the section, with an extension of `S`, the round,
/// and `A` while the round awaits results or `C` once it is complete
/// (`Open.S1A`, `Open.S1C`, and `Open.S0C` before round 1).
///
/// The layout was worked out from files SwissSys 9.14 wrote before round 1
/// and after pairing round 1, and those two states are reproduced cell for
/// cell. Result letters for earlier rounds, withdrawals and a completed
/// round follow the same conventions but have not been compared with a
/// SwissSys file.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../domain/fixed_schedule.dart';
import '../domain/model.dart';
import '../domain/us_chess.dart';
import 'artifact_file.dart';
import 'reports.dart';
import 'xls_writer.dart';

/// Whether SwissSys files can describe [s]: formats where two players meet
/// at a board each round.
bool swissSysExportable(Section s) => const [
  Format.swiss,
  Format.quad,
  Format.roundRobin,
  Format.scheveningen,
].contains(s.format);

/// The round a section file shows when none is asked for: the latest one,
/// or in a quad or round robin (whose rounds may all be posted at once) the
/// first still being played. Zero before round 1.
int swissSysRound(Section s) {
  if (s.rounds.isEmpty) return 0;
  if (hasFixedSchedule(s)) {
    final playing = s.rounds.where((r) => !r.complete).firstOrNull;
    if (playing != null) return playing.number;
  }
  return s.rounds.last.number;
}

/// `Open.S1A`: the section's name and the state of [round].
String swissSysFileName(Section s, {int? round}) {
  final number = round ?? swissSysRound(s);
  final current = s.rounds.where((r) => r.number == number).firstOrNull;
  final awaiting = current != null && !current.complete;
  final stem = s.name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\.+$'), '');
  return '${stem.isEmpty ? 'Section' : stem}.S$number${awaiting ? 'A' : 'C'}';
}

/// The section file for [s] as of [round] (default [swissSysRound]); later
/// rounds are left out.
Uint8List swissSysSection(Event e, Section s, {int? round}) {
  if (!swissSysExportable(s)) {
    throw TournamentException(
      'SwissSys files cannot describe a ${s.format.label.toLowerCase()} section.',
    );
  }
  final number = round ?? swissSysRound(s);
  final rounds = {
    for (final r in s.rounds)
      if (r.number <= number) r.number: r,
  };
  final current = rounds[number];
  final played = [
    for (var n = 1; n <= number; n++)
      if (rounds[n]?.complete ?? true) n,
  ].length;

  // Anyone who played here and has since left the section still needs a
  // row, because their opponents' results point at it.
  final ids = [...s.players];
  for (final r in rounds.values) {
    for (final id in [
      for (final g in r.games) ...[g.white, g.black],
      for (final b in r.byes) b.player,
    ]) {
      if (!ids.contains(id)) ids.add(id);
    }
  }
  final numbers = {for (final (i, id) in ids.indexed) id: i + 1};
  final fullBye = s.doubleGames ? 4 : 2;

  final results = <String, List<_Result>>{
    for (final id in ids)
      id: [
        for (var n = 1; n <= number; n++)
          _result(rounds[n], id, numbers, fullBye),
      ],
  };

  final settings = _settings(
    e,
    s,
    ids.length,
    played,
    number,
    [
      if (current != null)
        for (final b in current.byes) numbers[b.player]!,
    ]..sort(),
  );

  final players = <List<Object?>>[
    _playerColumns,
    for (final id in ids)
      _player(
        e.player(id),
        results[id]!,
        requestedByePoints: [
          for (final r in rounds.values)
            for (final b in r.byes)
              if (b.player == id && !b.allocated) b.points,
        ].fold(0, (a, b) => a + b),
        posted: number > 0,
        fullBye: fullBye,
      ),
  ];

  final resultRows = <List<Object?>>[
    if (number > 0) ...[
      [
        'PLAYER',
        for (var n = 1; n <= number; n++) ...[
          'OP$n',
          'CLR$n',
          'RES$n',
          'RES_CH$n',
          'GM_WINS$n',
        ],
      ],
      for (final id in ids)
        [
          numbers[id]!,
          for (final r in results[id]!) ...[
            r.opponent,
            r.color,
            r.points,
            r.letter,
            r.gameWins,
          ],
        ],
    ],
  ];

  // SwissSys keeps three copies of the board list: as it stands, as first
  // paired, and as first paired with acceleration. They are the same here.
  List<Object?> thrice(List<Object?> row) => [...row, ...row, ...row];
  final tables = <List<Object?>>[
    [
      if (current == null) ...[
        null,
        null,
        null,
      ] else ...[
        'WHITE',
        'BLACK',
        'BD',
      ],
      'NAT_WH',
      'NAT_BL',
      'NAT_BD',
      'A_NAT_WH',
      'A_NAT_BL',
      'A_NAT_BD',
    ],
    if (current != null) ...[
      for (final g in [
        ...current.games.where((g) => g.leg == 1),
      ]..sort((a, b) => a.board.compareTo(b.board)))
        thrice([numbers[g.white]!, numbers[g.black]!, g.board]),
      // The bye the pairing gave comes first, then the requested ones.
      for (final b
          in [...current.byes]..sort(
            (a, b) => a.allocated != b.allocated
                ? (a.allocated ? -1 : 1)
                : numbers[a.player]!.compareTo(numbers[b.player]!),
          ))
        thrice([numbers[b.player]!, -1, 0]),
    ],
  ];

  return xlsWorkbook([
    XlsSheet('Settings', settings),
    XlsSheet('Players', players),
    XlsSheet('Results', resultRows),
    XlsSheet('Tables', tables),
  ]);
}

/// A section file for every section of [e] that can have one, by file name.
/// [sections] limits it to those section IDs. [rounds] asks for a round by
/// section ID; a section not named there, or without that round, shows
/// [swissSysRound].
Map<String, Uint8List> swissSysFiles(
  Event e, {
  Iterable<String>? sections,
  Map<String, int> rounds = const {},
}) {
  final only = sections?.toSet();
  final files = <String, Uint8List>{};
  for (final s in e.sections) {
    if (only != null && !only.contains(s.id)) continue;
    if (!swissSysExportable(s)) continue;
    final asked = rounds[s.id];
    final round = s.rounds.any((r) => r.number == asked) ? asked : null;
    // Two sections with one name must not overwrite each other.
    final base = swissSysFileName(s, round: round);
    final dot = base.lastIndexOf('.');
    var name = base;
    for (
      var copy = 2;
      files.keys.any((k) => k.toLowerCase() == name.toLowerCase());
      copy++
    ) {
      name = '${base.substring(0, dot)} ($copy)${base.substring(dot)}';
    }
    files[name] = swissSysSection(e, s, round: round);
  }
  return files;
}

/// Writes [files] straight into [folder], replacing files of the same name:
/// a screen that watches the folder picks each round up under the name it
/// expects.
List<String> writeSwissSysFiles(Map<String, Uint8List> files, String folder) {
  if (!Directory(folder).existsSync()) {
    throw const TournamentException('Choose an existing folder.');
  }
  final written = <String>[];
  for (final entry in files.entries) {
    final path = p.join(folder, entry.key);
    writeArtifact(path, entry.value);
    written.add(path);
  }
  return written;
}

/// The files as one .zip, for the browser version, which downloads files
/// instead of writing folders.
List<int> swissSysZip(Map<String, Uint8List> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

/// One player's line of the `Results` sheet for one round.
typedef _Result = ({
  int opponent,
  int color,
  int points,
  String letter,
  int gameWins,
  int board,
  bool seated,
  bool decided,
});

const _unplayed = (
  opponent: -1,
  color: 0,
  points: 0,
  letter: 'U',
  gameWins: 0,
  board: 0,
  seated: false,
  decided: true,
);

_Result _result(
  Round? round,
  String id,
  Map<String, int> numbers,
  int fullBye,
) {
  if (round == null) return _unplayed;
  final seats = roundSeats(round, id);
  if (seats.isEmpty) {
    final bye = round.byes.where((b) => b.player == id).firstOrNull;
    if (bye == null) return _unplayed;
    return (
      opponent: -1,
      color: 0,
      points: bye.points,
      letter: bye.allocated || bye.points >= fullBye
          ? 'B'
          : bye.points > 0
          ? 'H'
          : 'U',
      gameWins: 0,
      board: 0,
      seated: false,
      decided: true,
    );
  }
  final first = seats.first;
  final points = seats.fold<int>(0, (sum, seat) => sum + seat.points);
  final decided = seats.every((seat) => seat.game.outcome.resolved);
  final forfeit =
      seats.length == 1 &&
      const [
        Outcome.whiteForfeit,
        Outcome.blackForfeit,
        Outcome.doubleForfeit,
      ].contains(first.game.outcome);
  final String letter;
  if (!decided) {
    letter = ' ';
  } else if (forfeit) {
    letter = points > 0 ? 'X' : 'F';
  } else {
    letter = points > seats.length
        ? 'W'
        : points == seats.length
        ? 'D'
        : 'L';
  }
  return (
    opponent: numbers[first.opponent] ?? -1,
    color: first.white ? 1 : -1,
    points: decided ? points : 0,
    letter: letter,
    gameWins: seats.length > 1
        ? seats.where((seat) => seat.points == 2).length
        : 0,
    board: first.game.board,
    seated: true,
    decided: decided,
  );
}

List<List<Object?>> _settings(
  Event e,
  Section s,
  int playerCount,
  int played,
  int paired,
  List<int> byes,
) {
  final posted = paired > 0;
  final values = <String, Object?>{
    'FILE_TYPE': 'SWISSSYS',
    'VERSION': '9.14',
    'PLR_CNT': playerCount,
    'RDS_PLD': played,
    'RDS_PRD': paired,
    'BYES': byes.firstOrNull,
    'TM_BYES': null,
    'QUICK': -1,
    '1ST_BD': s.boardStart,
    'LOW': s.ratingFloor,
    'HIGH': s.ratingCeiling > 0 ? s.ratingCeiling - 1 : 9999,
    'LAST_RD': 0,
    'COIN': posted ? 1 : 10,
    'TM_CUT': 999,
    'ALL_IN': posted,
    '1ST_TIME': true,
    'SORTED': true,
    'ACCEL': s.accelerated != Acceleration.none,
    'USE_TMS': false,
    'BLITZ': false,
    'TM_PAIRS': true,
    'FR_TM': false,
    'R_ROBIN': hasFixedSchedule(s),
    'TBL_SET': false,
    'BERGER': false,
    'FR_TBL': false,
    'LOGIC': posted,
    'GOT_TMS': true,
    'SEC_TITLE': s.name,
    'SEC_TIME': s.timeControl,
    'TNMT_TITLE': e.name,
    'TNMT_TIME': e.timeControl,
    'LADDER': false,
    'DIVIDED': false,
    'LOW GRD': 0,
    'HIGH GRD': 99,
    // SwissSys leaves two columns headed "-1"; this one is the round count.
    '-1': s.plannedRounds,
    'DBL_ACCEL': false,
    'TEAMS_ONLY': false,
    '-1 ': false,
    'RATING_TO_USE': 0,
    'EXCLUDE_BATCH': false,
    'EXCLUDE_RATINGS': false,
    'EXCLUDE_KRAUSE': false,
  };
  final byeColumn = values.keys.toList().indexOf('BYES');
  return [
    [for (final key in values.keys) key.trim()],
    values.values.toList(),
    // The other byes of the round run down the BYES column.
    for (final bye in byes.skip(1))
      [for (var c = 0; c < values.length; c++) c == byeColumn ? bye : null],
  ];
}

const _playerColumns = [
  'NAME',
  'ID',
  'ID2',
  'RATING',
  'RATING2',
  'EXP1',
  'EXP2',
  'CLUB',
  'TEAM',
  'TITLE',
  'COMPUTER',
  'AGE',
  'SEX',
  'CLASS',
  'FEES1',
  'FEES2',
  'FEES3',
  'ADDRESS',
  'CITY',
  'STATE',
  'ZIP',
  'NO_BYE',
  'DOB',
  'PHONE',
  'MEMO',
  'BD_ORD',
  'ADV_BYES',
  'PRE_PAIRED',
  'SCORE',
  'RES_CH',
  'WITHDREW',
  'PAIRED',
  'FLAGGED',
  'NO_PRIZE',
  'FIDE_RATE',
  'OLD_ID',
  'RES_BRD',
  'ESTIMATED',
  'SECTION_NUM',
  'BOARDS',
  'ADJ_SCORES',
  'NON_FIDE_RDS',
];

List<Object?> _player(
  Player player,
  List<_Result> results, {
  required int requestedByePoints,
  required bool posted,
  required int fullBye,
}) {
  final now = results.lastOrNull;
  final score = results.fold<int>(0, (sum, r) => sum + r.points);
  // The latest result as the wall chart prints it. A game still being
  // played, and a round sat out for nothing, are blank.
  final shown = now == null || !now.decided
      ? ' '
      : now.seated
      ? switch (now.letter) {
          'W' || 'X' => '1',
          'D' => '½',
          _ => '0',
        }
      : now.points >= fullBye
      ? '1'
      : now.points > 0
      ? '½'
      : ' ';
  final values = <String, Object?>{
    'NAME': _name(player),
    'ID': player.memberId,
    'RATING': player.effectivePairingRating,
    'RATING2': 0,
    'EXP1': _expiry(player),
    'CLUB': player.club,
    'TEAM': player.team,
    'TITLE': player.title,
    'CLASS': ' ',
    'STATE': player.state,
    'ADV_BYES': [
      for (final round in player.byes.keys.toList()..sort()) '$round ',
    ].join(),
    'SCORE': '$score',
    'RES_CH': shown,
    // SwissSys keeps a withdrawn flag on the player and pairs them no
    // more. Blank for everyone else, as in the files compared.
    'WITHDREW': player.withdrawn ? true : '',
    'PAIRED': now?.seated ?? false,
    'SECTION_NUM': 0,
    'BOARDS': posted ? '${now!.board}' : '',
    'ADJ_SCORES': posted ? '$requestedByePoints' : '',
  };
  return [for (final column in _playerColumns) values[column] ?? ''];
}

/// `LAST,FIRST` in capitals, as rosters taken from US Chess lists read.
String _name(Player player) =>
    playerReportName(player)?.replaceAll(', ', ',') ?? player.name.trim();

/// The US Chess expiration date as `MM/DD/YYYY`; empty when unknown.
String _expiry(Player player) {
  final date = player.membershipEvidence['expiration'];
  final match = date is String
      ? RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(date)
      : null;
  return match == null ? '' : '${match[2]}/${match[3]}/${match[1]}';
}
