import 'dart:math';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/model.dart';
import '../domain/pairing.dart';
import '../domain/standings.dart';

enum ReportKind { packet, pairings, standings, crosstable, sections }

/// A player's result, stable opponent number, and color. Both print and text
/// reports use this representation; a bye is distinct from an unplayed cell.
String crosstableCell(
  Event event,
  Round round,
  String playerId,
  Map<String, int> numbers,
) {
  final games =
      round.games
          .where((g) => g.white == playerId || g.black == playerId)
          .toList()
        ..sort((a, b) => a.leg.compareTo(b.leg));
  if (games.isEmpty) {
    final bye = round.byes.where((b) => b.player == playerId).firstOrNull;
    if (bye == null) return '--';
    return switch (bye.points) {
      2 => 'B---',
      1 => 'H---',
      _ => 'U---',
    };
  }
  return games
      .map((game) {
        final white = game.white == playerId;
        final opponent = white ? game.black : game.white;
        final points = white
            ? game.outcome.whiteScore
            : game.outcome.blackScore;
        final code = !game.outcome.resolved
            ? '?'
            : !game.outcome.played
            ? (points == 2 ? 'X' : 'F')
            : points == 2
            ? 'W'
            : points == 1
            ? 'D'
            : 'L';
        return '$code${numbers[opponent] ?? event.player(opponent).name}${white ? 'w' : 'b'}';
      })
      .join('/');
}

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
          .map(
            (r) => crosstableCell(
              e,
              r,
              id,
              numbers,
            ).padRight(s.doubleGames ? 18 : 8),
          )
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
  final count = min(section.plannedRounds, sectionSchedule(section).length);
  return [
    for (var n = 1; n <= count; n++)
      section.rounds.where((r) => r.number == n).firstOrNull ??
          paperRound(section, n),
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

/// Fixed player numbers stay readable even after the standings order changes.
/// Only the round cells are bisected; the player's name spans both halves.
List<pw.Widget> _roundRobinPairingGrid(
  Event event,
  Section section,
  List<Round> rounds,
) {
  final numbers = {
    for (final (index, id) in section.players.indexed) id: index + 1,
  };
  const line = pw.BorderSide(width: 0.6);
  pw.Widget label(String text, {bool header = false, bool left = false}) =>
      pw.Container(
        height: header ? 28 : 60,
        alignment: left ? pw.Alignment.centerLeft : pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 7),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: header ? 11 : 12,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
  // A posted opponent who has since left the roster has no number.
  String opponentLabel(String id) =>
      numbers[id]?.toString() ??
      ' ${event.players.where((p) => p.id == id).firstOrNull?.name ?? '?'}';
  pw.Widget roundCell(String player, Round round) {
    final games =
        round.games
            .where((g) => g.white == player || g.black == player)
            .toList()
          ..sort((a, b) => a.leg.compareTo(b.leg));
    final bye = round.byes.where((b) => b.player == player).firstOrNull;
    final labels = games.isEmpty
        ? [bye == null ? '-' : 'Bye']
        : [
            for (final game in games)
              (game.white == player ? 'W' : 'B') +
                  opponentLabel(game.white == player ? game.black : game.white),
          ];
    return pw.Row(
      children: [
        for (final (index, text) in labels.indexed)
          pw.Expanded(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border(left: index == 0 ? pw.BorderSide.none : line),
              ),
              child: pw.Column(
                children: [
                  pw.Container(
                    height: 27,
                    alignment: pw.Alignment.center,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: line),
                    ),
                    child: pw.Text(
                      text,
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ),
                  pw.SizedBox(height: 33),
                ],
              ),
            ),
          ),
      ],
    );
  }

  return [
    pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 8),
      child: pw.Text(
        'Round-robin pairing sheet',
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      ),
    ),
    // Keep larger round robins legible instead of squeezing every round across.
    for (var offset = 0; offset < rounds.length; offset += 5) ...[
      pw.Table(
        border: pw.TableBorder.all(width: 0.6),
        columnWidths: {
          0: const pw.FixedColumnWidth(28),
          1: const pw.FlexColumnWidth(2.5),
          for (var i = 0; i < rounds.skip(offset).take(5).length; i++)
            i + 2: const pw.FlexColumnWidth(),
        },
        children: [
          pw.TableRow(
            repeat: true,
            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
            children: [
              label('#', header: true),
              label('Player', header: true, left: true),
              for (final round in rounds.skip(offset).take(5))
                label('Round ${round.number}', header: true),
            ],
          ),
          for (final player in section.players)
            pw.TableRow(
              children: [
                label('${numbers[player]}'),
                label(event.player(player).name, left: true),
                for (final round in rounds.skip(offset).take(5))
                  roundCell(player, round),
              ],
            ),
        ],
      ),
      pw.SizedBox(height: 8),
    ],
    pw.Text(
      'W = White, B = Black; number = opponent. Write your result below.'
      '${section.doubleGames ? ' Paired boxes are games 1 and 2, left to right.' : ''}',
      style: const pw.TextStyle(fontSize: 10),
    ),
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
            hasFixedQuadSchedule(s) ||
            s.rounds.any((r) => r.number == roundNumber)),
  )) {
    sectionCount++;
    final requested = roundNumbers?[scope.id] ?? roundNumber;
    // A quad's later rounds may be unposted yet still shown and printed.
    // Rounds post in order, so "through round n" is then all of its rounds.
    // An explicit per-section round stays strict.
    final number =
        roundNumbers == null &&
            hasFixedQuadSchedule(scope) &&
            requested != null &&
            requested > scope.rounds.length
        ? null
        : requested;
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
    if (kind == ReportKind.sections) {
      // The section's players by pairing number. Pairings print from the
      // Pairings view, so this sheet never depends on a round existing.
      title('Players');
      widgets.add(
        pw.TableHelper.fromTextArray(
          headers: ['#', 'Player', 'Rating', 'US Chess ID'],
          data: [
            for (final (i, id) in s.players.indexed)
              [
                '${i + 1}',
                '${source.player(id).name}'
                    '${source.player(id).withdrawn ? ' (withdrawn)' : ''}',
                source.player(id).rating == 0
                    ? 'UNR'
                    : '${source.player(id).rating}',
                source.player(id).memberId,
              ],
          ],
          columnWidths: {
            0: const pw.FixedColumnWidth(32),
            1: const pw.FlexColumnWidth(),
            2: const pw.FixedColumnWidth(64),
            3: const pw.FixedColumnWidth(96),
          },
          cellAlignments: {
            0: pw.Alignment.centerRight,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerLeft,
          },
          headerAlignments: {
            0: pw.Alignment.centerRight,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerLeft,
          },
          cellStyle: const pw.TextStyle(fontSize: 12),
          headerStyle: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
          cellPadding: const pw.EdgeInsets.all(6),
        ),
      );
    }
    if (kind == ReportKind.pairings || kind == ReportKind.packet) {
      // A quad prints its complete reusable grid from every print entry. Larger
      // round robins and Swiss keep board tables, which players need to find
      // their seats, and honor the selected round.
      final quadGrid = hasFixedQuadSchedule(scope);
      final rounds = reportPairingRounds(
        scope,
        roundNumber: number,
        currentRoundOnly: currentRoundOnly && !quadGrid,
      );
      if (rounds.isEmpty) {
        title('Pairings');
        widgets.add(pw.Text('Pairings have not been created yet.'));
      }
      if (quadGrid && rounds.isNotEmpty) {
        widgets.addAll(_roundRobinPairingGrid(source, scope, rounds));
      }
      for (final round in quadGrid ? <Round>[] : rounds) {
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
      final numbers = {for (final (i, id) in s.players.indexed) id: i + 1};
      grid(
        ['#', 'Player', 'Pts', for (final r in s.rounds) 'R${r.number}'],
        [
          for (final row in table)
            [
              '${numbers[row.player.id]}',
              row.player.name,
              _halves(row.points),
              for (final r in s.rounds)
                crosstableCell(e, r, row.player.id, numbers),
            ],
        ],
      );
      widgets.add(
        pw.Text(
          'W/D/L = win/draw/loss; number = opponent; w/b = color. '
          'F = forfeit points; ? = unresolved; BYE = awarded points.',
          style: const pw.TextStyle(fontSize: 9),
        ),
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
