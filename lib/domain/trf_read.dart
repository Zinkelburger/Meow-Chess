import 'fide.dart';
import 'model.dart';
import 'tiebreaks.dart';
import 'trf.dart';
import 'us_chess.dart';

/// Reads a Tournament Report File: TRF26 (C.02 Appendix A), and the older
/// TRF16 and TRF06 within what those formats carry, plus the TRF(x) and
/// TRF(bx) records JaVaFo and BBP Pairings write (`XXR`, `XXC`, `XXA`,
/// `XXP`, `XXS`, `BBW`…`BBU`).
///
/// Sources: `research/local/fide-trf26-spec.txt`,
/// `research/local/fide-trf16-annexure-c.txt` and BBP Pairings' README.

/// A file that cannot be read as a TRF, with the line at fault.
class TrfFormatException implements Exception {
  const TrfFormatException(this.message, {this.line});
  final String message;

  /// 1-based line number, when the problem is on one line.
  final int? line;
  @override
  String toString() => line == null ? message : 'Line $line: $message';
}

/// One player record (001): the static fields and one cell per round.
class TrfPlayerRecord {
  TrfPlayerRecord({
    required this.rank,
    required this.sex,
    required this.title,
    required this.name,
    required this.rating,
    required this.federation,
    required this.fideId,
    required this.birthDate,
    required this.points,
    required this.place,
    required this.cells,
  });

  /// The starting rank (pairing number), 1-based.
  final int rank;
  final String sex, title, name, federation, fideId, birthDate;
  final int rating;

  /// The points field in half-points, or null when it is blank.
  final int? points;

  /// The rank field: the standings place, ties allowed; 0 when blank.
  final int place;
  final List<TrfCell> cells;
}

/// A National Rating Support record: a federation's own rating and ID for
/// the player with [rank].
typedef TrfNational = ({
  int rank,
  String name,
  int rating,
  String origin,
  String id,
});

/// A parsed TRF. Fields keep the file's own values; [toEvent] turns them
/// into a Meow-Chess event.
class TrfFile {
  TrfFile._();

  String name = '', city = '', federation = '';
  String startDate = '', endDate = '';
  String chiefArbiter = '';
  final deputies = <String>[];
  String timeControl = '', encodedTimeControl = '';
  String tournamentType = '';
  String rankingMethod = '';

  /// `W` or `B` from record 152 or `XXC white1/black1`; empty when unset.
  String initialColor = '';

  /// Record 142 or `XXR`; 0 when the file does not say.
  int plannedRounds = 0;

  /// Round dates from record 132, as written (`YY/MM/DD`).
  final roundDates = <String>[];

  /// The tie-break codes of record 202 (or 212 without `PTS`), as written.
  final tiebreaks = <String>[];

  /// Points per result in half-points, from 162, `BB?` or `XXS`. Keys are
  /// TRF 162 symbols: W, D, L, A (absence), P (pairing-allocated bye).
  final scoring = <String, int>{};
  final players = <TrfPlayerRecord>[];

  /// National Rating Support records by federation code.
  final national = <String, List<TrfNational>>{};
  final accelerations = <TrfAcceleration>[];

  /// Prohibited pairings: (first round, last round, starting ranks).
  final prohibited = <(int, int, List<int>)>[];

  /// Record 240: requested byes by round, starting rank → `F`, `H` or `Z`.
  final byes = <int, Map<int, String>>{};

  /// Records the reader recognised but does not use, and other notes.
  final notes = <String>[];

  /// Rounds held: the last round in which anyone was paired (a game or the
  /// pairing-allocated bye). Later columns only announce absences.
  int get playedRounds {
    var last = 0;
    for (final p in players) {
      for (final (i, c) in p.cells.indexed) {
        if (c.opponent > 0 || c.result == 'U') {
          if (i + 1 > last) last = i + 1;
        }
      }
    }
    return last;
  }

  /// The PAB's value in half-points: as declared, or inferred from the
  /// points of the players who received it (VCL.11), or a win.
  int get pabHalves {
    if (scoring['P'] case final declared?) return declared;
    final inferred = <int>{};
    for (final p in players) {
      final total = p.points;
      if (total == null) continue;
      final pabs = p.cells.where((c) => c.result == 'U').length;
      if (pabs != 1) continue;
      final others = p.cells
          .where((c) => c.result != 'U')
          .fold(0, (n, c) => n + trfCellHalves(c));
      inferred.add(total - others);
    }
    return inferred.length == 1 && const {0, 1, 2}.contains(inferred.single)
        ? inferred.single
        : (scoring['W'] ?? 2);
  }

  static TrfFile parse(String text) {
    final f = TrfFile._();
    final lines = text.replaceAll('﻿', '').split(RegExp(r'\r\n|\r|\n'));
    final ranks = <int>{};
    for (final (index, raw) in lines.indexed) {
      final n = index + 1;
      final line = raw.replaceAll('\t', ' ');
      if (line.trim().isEmpty || line.startsWith('###')) continue;
      if (line.length < 3) {
        throw TrfFormatException('Unknown record "$line".', line: n);
      }
      final code = line.substring(0, 3);
      String rest() => line.length > 4 ? line.substring(4).trim() : '';
      String col(int from, int to) => from > line.length
          ? ''
          : line.substring(from - 1, to > line.length ? line.length : to);
      int number(int from, int to, String what) {
        final v = col(from, to).trim();
        if (v.isEmpty) return 0;
        return int.tryParse(v) ??
            (throw TrfFormatException('$what "$v" is not a number.', line: n));
      }

      switch (code) {
        case '001':
          final rank = number(5, 8, 'Starting rank');
          if (rank < 1) {
            throw TrfFormatException('A player has no starting rank.', line: n);
          }
          if (!ranks.add(rank)) {
            throw TrfFormatException(
              'Starting rank $rank appears twice.',
              line: n,
            );
          }
          final cells = <TrfCell>[];
          for (var at = 92; at <= line.length; at += 10) {
            final id = col(at, at + 3).trim();
            final color = col(at + 5, at + 5).trim().toLowerCase();
            final result = col(at + 7, at + 7).trim().toUpperCase();
            final opponent = id.isEmpty ? 0 : int.tryParse(id);
            if (opponent == null) {
              throw TrfFormatException(
                'Round ${cells.length + 1} of player $rank has opponent "$id".',
                line: n,
              );
            }
            if (!const {'', 'W', 'B', '-'}.contains(color.toUpperCase())) {
              throw TrfFormatException(
                'Round ${cells.length + 1} of player $rank has colour "$color".',
                line: n,
              );
            }
            const codes = {
              '', '-', '+', 'W', 'D', 'L', '1', '=', '0', 'H', 'F', 'U', 'Z', //
            };
            if (!codes.contains(result)) {
              throw TrfFormatException(
                'Round ${cells.length + 1} of player $rank has result "$result".',
                line: n,
              );
            }
            cells.add((
              opponent: opponent,
              color: color.isEmpty ? '-' : color,
              result: result.isEmpty ? 'Z' : result,
            ));
          }
          final pointsText = col(81, 84).trim();
          final points = pointsText.isEmpty
              ? null
              : double.tryParse(pointsText.replaceAll(',', '.'));
          if (pointsText.isNotEmpty && points == null) {
            throw TrfFormatException(
              'Player $rank has points "$pointsText".',
              line: n,
            );
          }
          f.players.add(
            TrfPlayerRecord(
              rank: rank,
              sex: col(10, 10).trim().toLowerCase(),
              title: col(11, 13).trim(),
              name: col(15, 47).trim(),
              rating: number(49, 52, 'Rating'),
              federation: col(54, 56).trim(),
              fideId: col(58, 68).trim(),
              birthDate: col(70, 79).trim(),
              points: points == null ? null : (points * 2).round(),
              place: number(86, 89, 'Rank'),
              cells: cells,
            ),
          );
        case '012':
          f.name = rest();
        case '022':
          f.city = rest();
        case '032':
          f.federation = rest();
        case '042':
          f.startDate = rest();
        case '052':
          f.endDate = rest();
        case '102':
          f.chiefArbiter = rest();
        case '112':
          if (rest().isNotEmpty) f.deputies.add(rest());
        case '122':
          f.timeControl = rest();
        case '222':
          f.encodedTimeControl = rest();
        case '132':
          for (var at = 92; at <= line.length; at += 10) {
            f.roundDates.add(col(at, at + 7).trim());
          }
        case '142' || 'XXR':
          f.plannedRounds = number(5, 12, 'Number of rounds');
        case '152':
          f.initialColor = rest().toUpperCase();
        case 'XXC':
          for (final word in rest().toLowerCase().split(RegExp(r'\s+'))) {
            if (word == 'white1') f.initialColor = 'W';
            if (word == 'black1') f.initialColor = 'B';
          }
        case '162':
          for (var at = 6; at <= line.length; at += 9) {
            final symbol = col(at, at).trim().toUpperCase();
            if (symbol.isEmpty) continue;
            f.scoring[symbol == 'Z' ? 'A' : symbol] = _halves(
              col(at + 1, at + 4),
              n,
            );
          }
        case 'BBW' || 'BBD' || 'BBL' || 'BBZ' || 'BBF' || 'BBU':
          final symbol = const {
            'BBW': 'W',
            'BBD': 'D',
            'BBL': 'L',
            'BBZ': 'A',
            'BBF': 'A',
            'BBU': 'P',
          }[code]!;
          f.scoring[symbol] = _halves(rest(), n);
        case 'XXS':
          for (final pair in rest().split(RegExp(r'\s+'))) {
            final kv = pair.split('=');
            if (kv.length != 2) continue;
            final symbol = switch (kv[0].toUpperCase()) {
              'W' || 'WW' || 'BW' || 'FW' || 'FPB' => 'W',
              'D' || 'WD' || 'BD' || 'HPB' => 'D',
              'WL' || 'BL' => 'L',
              'ZPB' || 'FL' => 'A',
              'PAB' => 'P',
              _ => null,
            };
            if (symbol != null) f.scoring[symbol] = _halves(kv[1], n);
          }
        case '172':
          f.rankingMethod = col(9, 13).trim().toUpperCase();
        case '182':
          f.notes.add('Paired by ${rest()}.');
        case '192':
          f.tournamentType = rest().toUpperCase();
        case '202':
          f.tiebreaks.addAll(_codes(rest()));
        case '212':
          f.tiebreaks.addAll(
            _codes(rest()).skipWhile((c) => c.toUpperCase() == 'PTS'),
          );
        case '240':
          final type = col(5, 5).trim().toUpperCase();
          final round = number(7, 9, 'Round');
          for (var at = 11; at <= line.length; at += 5) {
            final id = number(at, at + 3, 'Player');
            if (id > 0) (f.byes[round] ??= {})[id] = type;
          }
        case '250':
          f.accelerations.add((
            halves: _halves(col(10, 13), n),
            firstRound: number(15, 17, 'Round'),
            lastRound: number(19, 21, 'Round'),
            firstPlayer: number(23, 26, 'Player'),
            lastPlayer: number(28, 31, 'Player'),
          ));
        case 'XXA':
          final id = number(5, 8, 'Player');
          for (var at = 10, r = 1; at <= line.length; at += 5, r++) {
            final v = col(at, at + 3).trim();
            if (v.isEmpty) continue;
            final halves = _halves(v, n);
            if (halves > 0) {
              f.accelerations.add((
                halves: halves,
                firstRound: r,
                lastRound: r,
                firstPlayer: id,
                lastPlayer: id,
              ));
            }
          }
        case '260':
          final ids = <int>[];
          for (var at = 13; at <= line.length; at += 5) {
            final id = number(at, at + 3, 'Player');
            if (id > 0) ids.add(id);
          }
          f.prohibited.add((
            number(5, 7, 'Round'),
            number(9, 11, 'Round'),
            ids,
          ));
        case 'XXP':
          f.prohibited.add((
            1,
            0,
            [
              for (final w in rest().split(RegExp(r'\s+')))
                if (int.tryParse(w) case final id? when id > 0) id,
            ],
          ));
        case '013' || '310' || '320' || '330' || '300' || '352' || '362':
          throw TrfFormatException(
            'This is a team tournament (record $code). Meow-Chess reads individual tournaments.',
            line: n,
          );
        case '299':
          throw TrfFormatException(
            'The file awards abnormal points (record 299), which Meow-Chess does not support.',
            line: n,
          );
        case '062' || '072' || '082' || '092' || '801' || '802':
          break;
        default:
          final national =
              RegExp(r'^[A-Z]{3}$').hasMatch(code) &&
              !code.startsWith('XX') &&
              !code.startsWith('BB');
          if (!national) {
            f.notes.add('Line $n: record $code is not used.');
            break;
          }
          (f.national[code] ??= []).add((
            rank: number(5, 8, 'Starting rank'),
            name: col(15, 47).trim(),
            rating: number(49, 52, 'National rating'),
            origin: col(54, 56).trim(),
            id: col(58, 68).trim(),
          ));
      }
    }
    if (f.players.isEmpty) {
      throw const TrfFormatException('The file lists no players (record 001).');
    }
    f.players.sort((a, b) => a.rank.compareTo(b.rank));
    return f;
  }

  static int _halves(String text, int line) {
    final v = double.tryParse(text.trim().replaceAll(',', '.'));
    if (v == null) {
      throw TrfFormatException(
        '"${text.trim()}" is not a number of points.',
        line: line,
      );
    }
    return (v * 2).round();
  }

  static List<String> _codes(String text) => [
    for (final c in text.split(RegExp(r'[,\s]+')))
      if (c.trim().isNotEmpty) c.trim(),
  ];
}

/// The event made from a TRF, with what could not be carried over.
typedef TrfImport = ({Event event, List<String> warnings});

/// A tie-break code as Meow-Chess stores it: MTB26 spelling, upper case,
/// with the 2024 name `GE` read as `REP`. Null when it is not one this
/// program computes.
String? fideTiebreakCode(String code) {
  // `BH-C1` is how C.07 itself spells `BH/C1`; `KS/L-1` keeps its sign.
  var c = code.trim().toUpperCase().replaceAll(RegExp(r'-(?=[A-Z])'), '/');
  if (c == 'GE') c = 'REP';
  final m = tiebreakMethod(c);
  return m != null && m.fide ? c : null;
}

/// TRF record 222 (`5400+30`, `40/6000+30:900+30`) as a time control
/// Meow-Chess reads, or null when it has none (a period not in whole
/// minutes, different increments, or a coloured control).
String? timeControlFromTrf(String encoded) {
  final periods = encoded.trim().split(':');
  if (encoded.trim().isEmpty || encoded.contains('-')) return null;
  final parts = <String>[];
  int? bonus;
  for (final (i, p) in periods.indexed) {
    final m = RegExp(r'^(?:(\d+)/)?(\d+)(?:\+(\d+))?$').firstMatch(p.trim());
    if (m == null) return null;
    final seconds = int.parse(m[2]!), inc = int.tryParse(m[3] ?? '') ?? 0;
    if (seconds % 60 != 0 || (bonus != null && bonus != inc)) return null;
    bonus = inc;
    final last = i == periods.length - 1;
    if (last != (m[1] == null)) return null;
    parts.add(
      m[1] == null
          ? '${periods.length == 1 ? 'G' : 'SD'}/${seconds ~/ 60}'
          : '${m[1]}/${seconds ~/ 60}',
    );
  }
  final text = '${parts.join(', ')}${(bonus ?? 0) > 0 ? ' inc/$bonus' : ''}';
  try {
    TimeControl.parse(text);
    return text;
  } on TournamentException {
    return null;
  }
}

/// `YYYY/MM/DD` (or `YY/MM/DD`) as an ISO date, or '' when unreadable.
String _isoDate(String text) {
  final m = RegExp(
    r'^(\d{2}|\d{4})[/.-](\d{1,2})[/.-](\d{1,2})$',
  ).firstMatch(text.trim());
  if (m == null) return '';
  final year = m[1]!.length == 2 ? '20${m[1]}' : m[1]!;
  final iso = '$year-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')}';
  final parsed = DateTime.tryParse(iso);
  return parsed != null && parsed.toIso8601String().startsWith(iso) ? iso : '';
}

/// A TRF birth date (`YYYY/MM/DD`, `YYYY/00/00`, `YYYY`) as Meow-Chess
/// stores it, or ''.
String _birthDate(String text) {
  final t = text.trim();
  final year = RegExp(r'^(\d{4})(?:[/.-]00[/.-]00)?$').firstMatch(t);
  if (year != null) return year[1]!;
  return _isoDate(t);
}

/// `Lastname, Firstname` as `Firstname Lastname`.
String _displayName(String trf) {
  final i = trf.indexOf(',');
  if (i < 0) return trf.trim();
  final last = trf.substring(0, i).trim(), first = trf.substring(i + 1).trim();
  return first.isEmpty ? last : '$first $last';
}

/// `Name (12345)` or `Name 12345` as an official.
FideOfficial _official(String text) {
  final m = RegExp(r'^(.*?)[\s(]*(\d{3,11})\)?\s*$').firstMatch(text.trim());
  if (m == null) return FideOfficial(name: text.trim());
  return FideOfficial(name: m[1]!.trim(), id: m[2]!);
}

/// [file] as a Meow-Chess event with one FIDE-rated section.
///
/// Players keep the file's starting ranks as their FIDE pairing numbers;
/// rounds keep their games, forfeits and byes; absences announced for the
/// rounds still to play become requested byes. A section with National
/// Rating Support records for `USA` is dual rated (unless it has results
/// US Chess cannot report); otherwise it is FIDE only. [newId] names
/// players, sections and games; [today] dates an event whose file has no
/// date.
TrfImport trfToEvent(
  TrfFile file, {
  required String Function() newId,
  required String today,
}) {
  final warnings = <String>[...file.notes.where((n) => !n.startsWith('Line'))];
  // Scoring: Meow-Chess scores 1, ½ and 0; only the PAB's value may vary.
  const standard = {'W': 2, 'D': 1, 'L': 0, 'A': 0};
  for (final MapEntry(:key, :value) in file.scoring.entries) {
    if (standard.containsKey(key) && standard[key] != value) {
      throw const TrfFormatException(
        'The file uses a scoring system other than 1, ½ and 0. Meow-Chess scores games 1, ½ and 0, with the pairing-allocated bye worth a win, a draw or nothing.',
      );
    }
  }
  if (file.scoring['X'] != null) {
    warnings.add('Adjourned-game scoring (record 162 X) was ignored.');
  }
  final pab = file.pabHalves;
  final played = file.playedRounds;
  final planned = [
    file.plannedRounds,
    played,
    for (final p in file.players) p.cells.length,
  ].reduce((a, b) => a > b ? a : b);
  final roundRobin = file.tournamentType.contains('ROUNDROBIN');
  final controlText =
      timeControlFromTrf(file.encodedTimeControl) ??
      (() {
        try {
          TimeControl.parse(file.timeControl);
          return file.timeControl;
        } on TournamentException {
          return null;
        }
      })();
  if (controlText == null &&
      (file.timeControl.isNotEmpty || file.encodedTimeControl.isNotEmpty)) {
    warnings.add(
      'The time control "${file.encodedTimeControl.isNotEmpty ? file.encodedTimeControl : file.timeControl}" was not recognised; set it in the event details.',
    );
  }
  final category = controlText == null
      ? FideCategory.standard
      : fideCategory(TimeControl.parse(controlText)) ?? FideCategory.standard;

  // Players, by starting rank.
  final usa = {for (final r in file.national['USA'] ?? const []) r.rank: r};
  for (final fed in file.national.keys.where((k) => k != 'USA')) {
    warnings.add('National ratings for $fed were not imported.');
  }
  final idOf = <int, String>{};
  final players = <Player>[];
  for (final r in file.players) {
    final id = newId();
    idOf[r.rank] = id;
    final nat = usa[r.rank];
    final fideId = r.fideId.replaceFirst(RegExp(r'^0+'), '');
    final federation = r.federation.toUpperCase();
    players.add(
      Player(
        id: id,
        name: _displayName(r.name.isEmpty ? 'Player ${r.rank}' : r.name),
        fideId: isFideId(fideId) ? fideId : '',
        fideStandard: category == FideCategory.standard ? r.rating : 0,
        fideRapid: category == FideCategory.rapid ? r.rating : 0,
        fideBlitz: category == FideCategory.blitz ? r.rating : 0,
        title: fideTitleFromCode(r.title),
        federation: isFederationCode(federation) ? federation : '',
        birthDate: _birthDate(r.birthDate),
        sex: const {'m', 'w'}.contains(r.sex) ? r.sex : '',
        memberId: nat?.id ?? '',
        rating: nat?.rating ?? 0,
        state: nat?.origin ?? '',
      ),
    );
  }

  // Rounds held.
  final rounds = <Round>[];
  var unusual = false;
  final scores = {for (final r in file.players) r.rank: 0};
  for (var n = 1; n <= played; n++) {
    TrfCell cellOf(TrfPlayerRecord p) => n <= p.cells.length
        ? p.cells[n - 1]
        : (opponent: 0, color: '-', result: 'Z');
    final byRank = {for (final p in file.players) p.rank: p};
    final pairs = <(int, int, Outcome, bool)>[];
    final byes = <ByeAward>[];
    final seen = <int>{};
    for (final p in file.players) {
      final c = cellOf(p);
      if (c.opponent == 0) {
        final points = switch (c.result) {
          'U' => pab,
          'F' || '+' || 'W' || '1' => 2,
          'H' || 'D' || '=' => 1,
          _ => 0,
        };
        // Only a real bye is recorded: a player absent (or not yet
        // entered) with nothing scored has a zero-point bye.
        byes.add(
          ByeAward(idOf[p.rank]!, points, switch (c.result) {
            'U' => 'Pairing-allocated bye',
            'F' => 'Full-point bye',
            'H' => 'Half-point bye',
            _ => 'Zero-point bye',
          }, allocated: c.result == 'U'),
        );
        continue;
      }
      if (!seen.add(p.rank)) continue;
      final o = byRank[c.opponent];
      if (o == null) {
        throw TrfFormatException(
          'Round $n: player ${p.rank} meets ${c.opponent}, who is not in the file.',
        );
      }
      final oc = cellOf(o);
      if (oc.opponent != p.rank) {
        throw TrfFormatException(
          'Round $n: player ${p.rank} meets ${o.rank}, but ${o.rank} meets ${oc.opponent == 0 ? 'nobody' : oc.opponent}.',
        );
      }
      seen.add(o.rank);
      final pWhite = c.color == 'w' || (c.color == '-' && oc.color == 'b');
      if ((c.color == 'w' && oc.color != 'b') ||
          (c.color == 'b' && oc.color != 'w')) {
        throw TrfFormatException(
          'Round $n: players ${p.rank} and ${o.rank} do not have opposite colours.',
        );
      }
      final (white, black) = pWhite ? (p, o) : (o, p);
      final wr = pWhite ? c.result : oc.result;
      final br = pWhite ? oc.result : c.result;
      final short =
          {'W', 'D', 'L'}.contains(wr) || {'W', 'D', 'L'}.contains(br);
      String norm(String r) => switch (r) {
        'W' => '1',
        'D' => '=',
        'L' => '0',
        _ => r,
      };
      final outcome = switch ((norm(wr), norm(br))) {
        ('1', '0') => Outcome.whiteWin,
        ('=', '=') => Outcome.draw,
        ('0', '1') => Outcome.blackWin,
        ('+', '-') => Outcome.whiteForfeit,
        ('-', '+') => Outcome.blackForfeit,
        ('-', '-') => Outcome.doubleForfeit,
        ('=', '0') => Outcome.whiteHalf,
        ('0', '=') => Outcome.blackHalf,
        ('0', '0') => Outcome.bothLose,
        _ => throw TrfFormatException(
          'Round $n: players ${white.rank} and ${black.rank} have inconsistent results $wr and $br.',
        ),
      };
      if (outcome.unusual) unusual = true;
      pairs.add((white.rank, black.rank, outcome, short && outcome.played));
    }
    // C.04.2 3.6: boards by the higher score of the pair, the sum of both
    // scores, then the higher-ranked player's pairing number.
    int top((int, int, Outcome, bool) x) =>
        [scores[x.$1]!, scores[x.$2]!].reduce((a, b) => a > b ? a : b);
    pairs.sort((a, b) {
      final t = top(b).compareTo(top(a));
      if (t != 0) return t;
      final sum = (scores[b.$1]! + scores[b.$2]!).compareTo(
        scores[a.$1]! + scores[a.$2]!,
      );
      if (sum != 0) return sum;
      return [a.$1, a.$2]
          .reduce((x, y) => x < y ? x : y)
          .compareTo([b.$1, b.$2].reduce((x, y) => x < y ? x : y));
    });
    final games = [
      for (final (i, (w, b, outcome, short)) in pairs.indexed)
        Game(
          id: newId(),
          white: idOf[w]!,
          black: idOf[b]!,
          board: i + 1,
          outcome: outcome,
          shortGame: short,
        ),
    ];
    for (final g in pairs) {
      scores[g.$1] = scores[g.$1]! + g.$3.whiteScore;
      scores[g.$2] = scores[g.$2]! + g.$3.blackScore;
    }
    for (final b in byes) {
      final rank = idOf.entries.firstWhere((e) => e.value == b.player).key;
      scores[rank] = scores[rank]! + b.points;
    }
    final date = n <= file.roundDates.length
        ? _isoDate(file.roundDates[n - 1])
        : '';
    rounds.add(
      Round(
        number: n,
        games: games,
        byes: byes,
        postedAt: date.isEmpty ? null : '${date}T12:00:00.000Z',
        policy: 'trf-import',
      ),
    );
  }

  // Absences announced for rounds still to play: the extra ITDX column and
  // record 240.
  final requested = <String, Map<int, int>>{};
  for (final p in file.players) {
    for (var n = played + 1; n <= p.cells.length; n++) {
      final c = p.cells[n - 1];
      if (c.opponent == 0 && const {'H', 'F', 'Z'}.contains(c.result)) {
        (requested[idOf[p.rank]!] ??= {})[n] = switch (c.result) {
          'F' => 2,
          'H' => 1,
          _ => 0,
        };
      }
    }
  }
  for (final MapEntry(key: n, value: entries) in file.byes.entries) {
    if (n <= played) continue;
    for (final MapEntry(key: rank, value: type) in entries.entries) {
      final id = idOf[rank];
      if (id == null) continue;
      (requested[id] ??= {})[n] = switch (type) {
        'F' => 2,
        'H' => 1,
        _ => 0,
      };
    }
  }

  // Prohibited pairings that hold for the whole tournament become
  // do-not-pair requests; shorter ones cannot be kept.
  final avoid = <String, Set<String>>{};
  for (final (first, last, ids) in file.prohibited) {
    if (first > 1 || (last != 0 && last < planned)) {
      warnings.add(
        'Prohibited pairings for rounds $first–$last were not imported: Meow-Chess keeps do-not-pair requests for every round.',
      );
      continue;
    }
    for (final a in ids) {
      for (final b in ids) {
        if (a != b && idOf[a] != null && idOf[b] != null) {
          (avoid[idOf[a]!] ??= {}).add(idOf[b]!);
        }
      }
    }
  }
  final withRequests = [
    for (final p in players)
      p.copy(byes: requested[p.id] ?? const {}, avoid: avoid[p.id] ?? const {}),
  ];

  // Tie-breaks.
  final tiebreaks = <String>[];
  for (final c in file.tiebreaks) {
    final code = fideTiebreakCode(c);
    if (code == null) {
      warnings.add(
        'Tie-break "$c" is not one Meow-Chess computes; it was left out.',
      );
    } else if (!tiebreaks.contains(code)) {
      tiebreaks.add(code);
    }
  }

  final dual = usa.isNotEmpty && !unusual;
  if (usa.isNotEmpty && unusual) {
    warnings.add(
      'The file has ½–0, 0–½ or played 0–0 results, which US Chess cannot report, so the section is rated by FIDE only.',
    );
  }
  var section = Section(
    id: newId(),
    name: 'Open',
    players: [for (final p in players) p.id],
    format: roundRobin ? Format.roundRobin : Format.swiss,
    plannedRounds: planned < 1 ? 1 : planned,
    rounds: rounds,
    fideRated: true,
    unrated: !dual,
    fideRanking: dual && fideRankingMethods.containsKey(file.rankingMethod)
        ? file.rankingMethod
        : '',
    fideOrder: [for (final r in file.players) idOf[r.rank]!],
    pabPoints: roundRobin ? 2 : pab,
  );
  if (roundRobin && pab != 2) {
    warnings.add(
      'The pairing-allocated bye value applies to Swiss sections only.',
    );
  }

  final initial = file.initialColor.isNotEmpty
      ? file.initialColor
      : _inferredInitialColor(file);
  final start = _isoDate(file.startDate).ifEmpty(
    () => rounds
        .map((r) => r.postedAt?.substring(0, 10) ?? '')
        .firstWhere((d) => d.isNotEmpty, orElse: () => today),
  );
  var event = Event(
    id: newId(),
    name: file.name.isEmpty ? 'Imported tournament' : file.name,
    date: start,
    endDate: _isoDate(file.endDate),
    city: file.city,
    timeControl: controlText ?? 'G/90 inc/30',
    colorToss: switch (initial) {
      'W' => 'higherWhite',
      'B' => 'higherBlack',
      _ => '',
    },
    fide: FideRegistration(
      federation: isFederationCode(file.federation.toUpperCase())
          ? file.federation.toUpperCase()
          : '',
      chiefArbiter: _official(file.chiefArbiter),
      deputies: [for (final d in file.deputies) _official(d)],
    ),
    fideTiebreaks: tiebreaks,
    players: withRequests,
    sections: [section],
  );

  // Acceleration: the Baku method, as C.04.7 defines it, is kept; any
  // other acceleration cannot be.
  final baku = file.tournamentType.endsWith('_BAKU');
  if (!roundRobin && (baku || file.accelerations.isNotEmpty)) {
    // Group A ends with the last player the file accelerates (C.04.7
    // 1.3.2: after late entries it is no longer 2 × ⌈n/4⌉ players).
    final lastRank = file.accelerations.isEmpty
        ? 0
        : file.accelerations
              .map((a) => a.lastPlayer)
              .reduce((a, b) => a > b ? a : b);
    section = section.copy(
      accelerated: 'baku',
      bakuLast: played == 0 ? '' : idOf[lastRank] ?? '',
    );
    event = event.copy(sections: [section]);
    if (file.accelerations.isNotEmpty) {
      final ours = _expand(bakuAccelerations(trfTournament(event, section)));
      if (!_sameAcceleration(_expand(file.accelerations), ours)) {
        section = section.copy(accelerated: '');
        event = event.copy(sections: [section]);
        warnings.add(
          'The file’s accelerated rounds (records 250/XXA) are not the Baku method, so they were not imported; later rounds pair without acceleration.',
        );
      }
    }
  }
  validateEvent(event);
  return (event: event, warnings: warnings);
}

extension on String {
  String ifEmpty(String Function() other) => isEmpty ? other() : this;
}

/// The round-1 colour of the highest-ranked player paired in round 1, as
/// BBP Pairings infers it: a higher-ranked player who took part without a
/// colour (the pairing-allocated bye) reverses it.
String _inferredInitialColor(TrfFile file) {
  var flip = false;
  for (final p in file.players) {
    if (p.cells.isEmpty) continue;
    final c = p.cells.first;
    if (c.result == 'U') {
      flip = !flip;
    } else if (c.opponent > 0 && (c.color == 'w' || c.color == 'b')) {
      return (c.color == 'w') != flip ? 'W' : 'B';
    }
  }
  return '';
}

/// Fictitious points per (round, starting rank).
Map<(int, int), int> _expand(Iterable<TrfAcceleration> list) => {
  for (final a in list)
    for (var r = a.firstRound; r <= a.lastRound; r++)
      for (var p = a.firstPlayer; p <= a.lastPlayer; p++) (r, p): a.halves,
};

bool _sameAcceleration(Map<(int, int), int> a, Map<(int, int), int> b) {
  final keys = {...a.keys, ...b.keys};
  return keys.every((k) => (a[k] ?? 0) == (b[k] ?? 0));
}
