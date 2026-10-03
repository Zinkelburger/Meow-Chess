import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/model.dart';
import '../domain/pairing.dart';
import '../domain/standings.dart';

enum ReportKind { packet, pairings, standings, crosstable, sections }

String crosstable(Event e, {bool asciiOnly = false, String? sectionId}) {
  final lines = <String>['${e.name} | ${e.date} | revision ${e.revision}', ''];
  for (final s in e.sections.where(
    (s) => s.players.isNotEmpty && (sectionId == null || s.id == sectionId),
  )) {
    final rows = standings(e, s);
    final numbers = {for (final (i, id) in s.players.indexed) id: i + 1};
    final nameWidth = rows.fold(
      12,
      (int n, Standing r) =>
          r.player.name.length > n ? r.player.name.length : n,
    );
    lines.add('${s.name} — ${s.rounds.length}/${s.plannedRounds} rounds');
    lines.add(
      '${'#'.padLeft(3)}  ${'Name'.padRight(nameWidth)}  ${'Rtg'.padLeft(4)}  ${'Pts'.padLeft(4)}  ${[for (final r in s.rounds) 'R${r.number}'.padRight(s.doubleGames ? 18 : 8)].join(' ')}',
    );
    for (final row in rows) {
      final id = row.player.id;
      final cells = s.rounds
          .map((r) {
            final games = r.games
                .where((g) => g.white == id || g.black == id)
                .toList();
            if (games.isEmpty) {
              final bye = r.byes.where((b) => b.player == id).firstOrNull;
              return (bye == null ? '--' : 'BYE ${scoreText(bye.points)}')
                  .padRight(s.doubleGames ? 18 : 8);
            }
            return games
                .map((g) {
                  final white = g.white == id;
                  final opponent = white ? g.black : g.white;
                  final points = white
                      ? g.outcome.whiteScore
                      : g.outcome.blackScore;
                  final code = !g.outcome.resolved
                      ? '?'
                      : !g.outcome.played
                      ? 'F${scoreText(points)}'
                      : points == 2
                      ? 'W'
                      : points == 1
                      ? 'D'
                      : 'L';
                  return '$code${numbers[opponent] ?? e.player(opponent).name}${white ? 'w' : 'b'}';
                })
                .join('/')
                .padRight(s.doubleGames ? 18 : 8);
          })
          .join(' ');
      lines.add(
        '${numbers[id].toString().padLeft(3)}  ${row.player.name.padRight(nameWidth)}  ${row.player.rating.toString().padLeft(4)}  ${scoreText(row.points).padLeft(4)}  $cells',
      );
    }
    lines.add('');
  }
  var text = lines.join('\n');
  if (asciiOnly) {
    text = text.replaceAll('—', '-');
    if (text.codeUnits.any((c) => c > 127)) {
      throw const TournamentException(
        'ASCII export requires ASCII name aliases. Use UTF-8 text or PDF to preserve these names.',
      );
    }
  }
  return text;
}

String standingsCsv(Event e, {String? sectionId}) => Csv().encode([
  [
    'Section',
    'Pairing number',
    'Name',
    'Rating',
    'Points',
    'Buchholz',
    'Sonneborn-Berger',
  ],
  for (final s in e.sections.where(
    (s) => sectionId == null || s.id == sectionId,
  ))
    for (final row in standings(e, s))
      [
        _safe(s.name),
        s.players.indexOf(row.player.id) + 1,
        _safe(row.player.name),
        row.player.rating,
        scoreText(row.points),
        scoreText(row.buchholz),
        row.sonneborn / 4,
      ],
]);
String _safe(String text) =>
    RegExp(r'^[=+@\-\t\r]').hasMatch(text) ? "'$text" : text;

/// Half-points as printed on paper: ½, 1½.
String _halves(int n) => n == 1
    ? '½'
    : n.isOdd
    ? '${n ~/ 2}½'
    : '${n ~/ 2}';

/// Quarter-points (Sonneborn–Berger) as printed: ¼, 2½, 3¾.
String _quarters(int n) {
  final whole = n ~/ 4, part = const ['', '¼', '½', '¾'][n % 4];
  return whole == 0 && part.isNotEmpty ? part : '$whole$part';
}

/// Paper schedules never post rounds or change the tournament. Preserve edited
/// posted pairings; fill the remaining round-robin rounds from the fixed draw.
/// Swiss sheets contain only the selected (or latest posted) round.
List<Round> reportPairingRounds(
  Section section, {
  int? roundNumber,
  bool currentRoundOnly = false,
}) {
  if (currentRoundOnly ||
      pairingFormat(section) == Format.swiss ||
      section.sideGames) {
    if (roundNumber == null) {
      return [if (section.rounds.isNotEmpty) section.rounds.last];
    }
    if (roundNumber == 0) return [];
    final round = section.rounds
        .where((r) => r.number == roundNumber)
        .firstOrNull;
    if (round == null) {
      throw TournamentException('Round $roundNumber is no longer available.');
    }
    return [round];
  }
  final schedule = roundRobinSchedule(
    section.players,
    quad: section.format == Format.quad,
    colorLot: quadColorLot(section),
  );
  return [
    for (final (index, pairs) in schedule.take(section.plannedRounds).indexed)
      section.rounds.where((r) => r.number == index + 1).firstOrNull ??
          (() {
            final games = <Game>[];
            final byes = <ByeAward>[];
            var board = section.boardStart;
            for (final (white, black) in pairs) {
              if (white == null || black == null) {
                final player = white ?? black;
                if (player != null) {
                  byes.add(ByeAward(player, 0, 'Round-robin sit-out'));
                }
                continue;
              }
              games.add(
                Game(
                  id: 'paper-${section.id}-$index-$board-1',
                  white: white,
                  black: black,
                  board: board,
                ),
              );
              if (section.doubleGames) {
                games.add(
                  Game(
                    id: 'paper-${section.id}-$index-$board-2',
                    white: black,
                    black: white,
                    board: board,
                    leg: 2,
                  ),
                );
              }
              board++;
            }
            return Round(number: index + 1, games: games, byes: byes);
          })(),
  ];
}

/// An explicit historical scope never silently substitutes the latest round.
Event eventThroughRound(Event event, int? roundNumber, {String? sectionId}) {
  if (roundNumber == null) return event;
  final scoped = event.sections.where(
    (s) => sectionId == null || s.id == sectionId,
  );
  if (roundNumber < 0 ||
      (roundNumber > 0 &&
          !scoped.any((s) => s.rounds.any((r) => r.number == roundNumber)))) {
    throw TournamentException(
      'Round $roundNumber is no longer available. Close this preview and choose a posted round.',
    );
  }
  return event.copy(
    sections: [
      for (final s in event.sections)
        s.copy(rounds: s.rounds.where((r) => r.number <= roundNumber).toList()),
    ],
  );
}

/// Rank within the requested prize class using the same tie rules as the screen.
List<Standing> reportStandings(
  Event event,
  Section section, {
  int ceiling = 0,
  bool forPrizes = false,
}) {
  final rows = standings(event, section, forPrizes: forPrizes)
      .where(
        (r) =>
            ceiling == 0 || (r.player.rating > 0 && r.player.rating < ceiling),
      )
      .toList();
  var rank = 1;
  return [
    for (var i = 0; i < rows.length; i++)
      (() {
        final r = rows[i];
        if (i > 0 &&
            (r.points != rows[i - 1].points ||
                (event.useTiebreaks &&
                    (r.buchholz != rows[i - 1].buchholz ||
                        r.sonneborn != rows[i - 1].sonneborn)))) {
          rank = i + 1;
        }
        return Standing(
          r.player,
          r.points,
          r.buchholz,
          r.sonneborn,
          r.played,
          rank: rank,
        );
      })(),
  ];
}

Future<Uint8List> reportPdf(
  Event e,
  ReportKind kind, {
  String? sectionId,
  bool a4 = false,
  int? roundNumber,
  Map<String, int>? roundNumbers,
  bool currentRoundOnly = false,
  int ceiling = 0,
  bool forPrizes = false,
  pw.Font? font,
  pw.Font? bold,
}) async {
  final source = e;
  if (roundNumbers != null &&
      roundNumbers.keys.any((id) => !source.sections.any((s) => s.id == id))) {
    throw const TournamentException(
      'A selected section is no longer available. Close this preview and select sections again.',
    );
  }
  if (roundNumbers == null && roundNumber != null) {
    eventThroughRound(source, roundNumber, sectionId: sectionId);
  }
  final doc = pw.Document();
  var sectionCount = 0;
  for (final scope in source.sections.where(
    (s) =>
        s.players.isNotEmpty &&
        (sectionId == null || s.id == sectionId) &&
        (roundNumbers == null || roundNumbers.containsKey(s.id)) &&
        (roundNumbers != null ||
            roundNumber == null ||
            roundNumber == 0 ||
            s.rounds.any((r) => r.number == roundNumber)),
  )) {
    sectionCount++;
    final number = roundNumbers?[scope.id] ?? roundNumber;
    e = eventThroughRound(source, number, sectionId: scope.id);
    final s = e.sections.firstWhere((s) => s.id == scope.id);
    final table = reportStandings(e, s, ceiling: ceiling, forPrizes: forPrizes);
    final widgets = <pw.Widget>[];
    void title(String text) => widgets.add(
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 12),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
      ),
    );
    void grid(List<String> headers, List<List<String>> rows) => widgets.add(
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        // Read from a step away on the wall.
        cellStyle: const pw.TextStyle(fontSize: 12),
        headerStyle: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        cellPadding: const pw.EdgeInsets.all(6),
      ),
    );
    if (kind == ReportKind.sections ||
        kind == ReportKind.pairings ||
        kind == ReportKind.packet) {
      // Use the full section for fixed schedules, even when printing from the
      // round-one screen. Swiss still honors the frozen selected round.
      final rounds = reportPairingRounds(
        scope,
        roundNumber: number,
        currentRoundOnly: currentRoundOnly,
      );
      if (rounds.isEmpty) {
        title('Pairings');
        widgets.add(pw.Text('Pairings have not been created yet.'));
      }
      for (final round in rounds) {
        widgets.add(pw.NewPage(freeSpace: 100));
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12, bottom: 5),
            child: pw.Text(
              'Round ${round.number}',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
        );
        widgets.add(
          pw.TableHelper.fromTextArray(
            headers: ['Board', 'Result', 'White', 'Black', 'Result'],
            data: [
              for (final g in round.games)
                [
                  '${g.board}${scope.doubleGames ? ' / ${g.leg}' : ''}',
                  '',
                  source.player(g.white).name,
                  source.player(g.black).name,
                  '',
                ],
            ],
            tableWidth: pw.TableWidth.max,
            columnWidths: {
              0: const pw.FixedColumnWidth(38),
              1: const pw.FixedColumnWidth(42),
              2: const pw.FlexColumnWidth(),
              3: const pw.FlexColumnWidth(),
              4: const pw.FixedColumnWidth(42),
            },
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.center,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.center,
            },
            headerAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.center,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.center,
            },
            border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
            cellStyle: const pw.TextStyle(fontSize: 11),
            headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 7,
            ),
            headerPadding: const pw.EdgeInsets.all(5),
            cellHeight: 30,
          ),
        );
        for (final bye in round.byes) {
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 5),
              child: pw.Text(
                '${source.player(bye.player).name}: ${bye.allocated ? 'Bye' : bye.reason} (${_halves(bye.points)})',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          );
        }
      }
    }
    if (kind == ReportKind.standings) {
      title(
        'Standings${ceiling == 0 ? '' : ' · Under $ceiling'}${forPrizes ? ' · Excluding early round-robin withdrawals' : ''}',
      );
      grid(
        ['Rank', 'Player', 'Rating', 'Points', 'BH', 'SB'],
        [
          for (final r in table)
            [
              table.where((x) => x.rank == r.rank).length > 1
                  ? 'T-${r.rank}'
                  : '${r.rank}',
              r.player.name,
              r.player.rating == 0 ? 'UNR' : '${r.player.rating}',
              _halves(r.points),
              _halves(r.buchholz),
              _quarters(r.sonneborn),
            ],
        ],
      );
      widgets.add(
        pw.Text(
          'Tie breaks: played-opponent Buchholz, then Sonneborn–Berger. Equal values remain tied.',
          style: const pw.TextStyle(fontSize: 9),
        ),
      );
    }
    if (kind == ReportKind.crosstable) {
      title('Crosstable');
      grid(
        ['Player', 'Pts', for (final r in s.rounds) 'R${r.number}'],
        [
          for (final row in table)
            [
              row.player.name,
              _halves(row.points),
              for (final r in s.rounds)
                r.games
                    .where(
                      (g) =>
                          g.white == row.player.id || g.black == row.player.id,
                    )
                    .map(
                      (g) =>
                          '${g.white == row.player.id ? 'W' : 'B'} ${g.outcome.label}',
                    )
                    .join(' / '),
            ],
        ],
      );
    }
    doc.addPage(
      pw.MultiPage(
        pageFormat: a4 ? PdfPageFormat.a4 : PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        theme: font == null
            ? null
            : pw.ThemeData.withFont(base: font, bold: bold ?? font),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              e.name,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '${s.name} · ${e.date}${e.practice ? ' · PRACTICE COPY' : ''}',
            ),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Revision ${e.revision} · ${s.effectiveTimeControl(e)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
        build: (_) => widgets,
      ),
    );
  }
  if (sectionCount == 0) {
    throw const TournamentException(
      'There are no players in the selected sections to print.',
    );
  }
  return doc.save();
}
