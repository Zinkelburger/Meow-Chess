import 'dart:math';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/bye_policy.dart';
import '../domain/model.dart';
import '../domain/pairing.dart';
import '../domain/prizes.dart';
import '../domain/knockout.dart';
import '../domain/ladder.dart';
import '../domain/scheveningen.dart';
import '../domain/standings.dart';
import '../domain/us_chess.dart';

enum ReportKind {
  packet,
  pairings,
  standings,
  crosstable,
  sections,
  prizes,
  conditions,
}

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
        // Rule 18G: an adjudicated result is marked on the chart.
        return '$code${numbers[opponent] ?? reportName(event.player(opponent).name)}${white ? 'w' : 'b'}${game.adjudicated ? ' ADJ' : ''}';
      })
      .join('/');
}

/// A name on one line: a line break or tab pasted into a name would split a
/// printed row or misalign a text column.
String reportName(String name) => name.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Rule 28O: the wall chart shows a player's cumulative score after each
/// round, in half-points per posted round of [section], in order.
List<int> cumulativeScores(Section section, String playerId) {
  final totals = <int>[];
  var total = 0;
  for (final round in section.rounds) {
    for (final bye in round.byes.where((b) => b.player == playerId)) {
      total += bye.points;
    }
    for (final g in round.games) {
      if (g.white == playerId) total += g.outcome.whiteScore;
      if (g.black == playerId) total += g.outcome.blackScore;
    }
    totals.add(total);
  }
  return totals;
}

/// Rule 28O: `NEW` for a player with no rating and no US Chess ID, `UNR`
/// for any other unrated player.
String wallChartRating(Player player) => player.rating != 0
    ? '${player.rating}'
    : player.memberId.trim().isEmpty
    ? 'NEW'
    : 'UNR';

String crosstable(Event e, {bool asciiOnly = false, String? sectionId}) {
  final lines = <String>['${e.name} | ${e.date} | revision ${e.revision}', ''];
  for (final s in e.sections.where(
    (s) => s.players.isNotEmpty && (sectionId == null || s.id == sectionId),
  )) {
    final numbers = {for (final (i, id) in s.players.indexed) id: i + 1};
    // A ladder reads top down: # is the place, not a pairing number.
    final rows = s.format == Format.ladder
        ? (standings(e, s)..sort(
            (a, b) => numbers[a.player.id]!.compareTo(numbers[b.player.id]!),
          ))
        : standings(e, s);
    final nameWidth = rows.fold(
      12,
      (int n, Standing r) => reportName(r.player.name).length > n
          ? reportName(r.player.name).length
          : n,
    );
    // Rule 28O: each cell is the result, then the score so far.
    final cellWidth = s.doubleGames ? 22 : 12;
    lines.add(
      s.format == Format.ladder
          ? '${s.name} — ladder, ${s.rounds.length} ${s.rounds.length == 1 ? 'batch' : 'batches'} of challenge games'
          : '${s.name} — ${s.rounds.length}/${s.plannedRounds} rounds',
    );
    lines.add(
      '${'#'.padLeft(3)}  ${'Name'.padRight(nameWidth)}  ${'Rtg'.padLeft(4)}  ${'Pts'.padLeft(4)}  ${[for (final r in s.rounds) 'R${r.number}'.padRight(cellWidth)].join(' ')}',
    );
    for (final row in rows) {
      final id = row.player.id;
      final totals = cumulativeScores(s, id);
      final cells = s.rounds.indexed
          .map(
            (entry) =>
                '${crosstableCell(e, entry.$2, id, numbers)} ${scoreText(totals[entry.$1])}'
                    .padRight(cellWidth),
          )
          .join(' ');
      lines.add(
        '${numbers[id].toString().padLeft(3)}  ${reportName(row.player.name).padRight(nameWidth)}  ${wallChartRating(row.player).padLeft(4)}  ${scoreText(row.points).padLeft(4)}  $cells',
      );
    }
    // A knockout places by the bracket, not by points.
    if (s.format == Format.knockout) {
      lines.addAll(['', ...knockoutBracketLines(e, s)]);
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

/// Rules 32–33 on screen: the prize table, who takes what, and the
/// pooling arithmetic behind it, per section.
String prizeReport(Event e, {String? sectionId}) {
  final lines = <String>['${e.name} | ${e.date} | revision ${e.revision}', ''];
  for (final s in e.sections.where(
    (s) => s.players.isNotEmpty && (sectionId == null || s.id == sectionId),
  )) {
    final a = allocatePrizes(e, s);
    lines.add(
      '${s.name} — ${a.entries} entries'
      '${a.table.basedOn > 0 ? ', based on ${a.table.basedOn}' : ''}'
      '${a.payoutPercent == 100 ? '' : ', paying ${a.payoutPercent}%'}',
    );
    if (a.table.isEmpty) {
      lines
        ..add('No prizes announced.')
        ..add('');
      continue;
    }
    for (final line in a.lines) {
      lines.add(
        '${line.prize.title.padRight(24)} ${_prizeAmount(line).padLeft(16)}  ${_prizeOutcome(e, line)}',
      );
    }
    lines.add('');
    for (final w in a.awards) {
      lines.add(
        '${reportName(w.player.name).padRight(28)} ${scoreText(w.points).padLeft(4)}  '
        '${w.cents > 0 ? dollars(w.cents).padLeft(9) : ''.padLeft(9)}'
        '${w.trophies.isEmpty ? '' : '  ${w.trophies.map((t) => '${t.title} trophy').join(', ')}'}',
      );
    }
    lines.add('Total paid: ${dollars(a.paidCents)}');
    lines.add('');
    for (final x in a.explanations) {
      lines.add('• $x');
    }
    lines.add('');
  }
  return lines.join('\n');
}

String _prizeAmount(PrizeLine line) => [
  if (line.prize.cents > 0)
    line.paidCents == line.prize.cents
        ? dollars(line.prize.cents)
        : '${dollars(line.paidCents)} of ${dollars(line.prize.cents)}',
  if (line.prize.trophy) 'trophy',
].join(' + ');

String _prizeOutcome(Event e, PrizeLine line) {
  String name(String id) =>
      reportName(e.players.where((p) => p.id == id).firstOrNull?.name ?? id);
  final cash = line.cash.entries.toList();
  final parts = <String>[
    if (cash.length == 1 && line.pooledWith.isEmpty)
      name(cash.single.key)
    else if (cash.isNotEmpty)
      '${line.pooledWith.isEmpty ? 'shared' : 'pooled'}: '
          '${cash.map((c) => '${name(c.key)} ${dollars(c.value)}').join(', ')}',
    if (line.trophyWinner != null) 'trophy: ${name(line.trophyWinner!)}',
    if (line.note.isNotEmpty) line.note,
  ];
  return parts.join(' · ');
}

/// Starts with a byte-order mark: without one, Excel on Windows reads UTF-8
/// as the system code page and garbles names such as José.
///
/// Rule 34B: the tie-break columns are headed by the posted method names.
/// Every selected section shares one header, so the columns are the first
/// section's methods; a section ranked by other methods leaves them blank.
String standingsCsv(Event e, {String? sectionId}) {
  final sections = e.sections
      .where((s) => sectionId == null || s.id == sectionId)
      .toList();
  final methods = sections.isEmpty
      ? const <TiebreakMethod>[]
      : standingsTiebreaks(e, sections.first);
  return Csv(addBom: true).encode([
    [
      'Section',
      'Pairing number',
      'Name',
      'Rating',
      'Points',
      for (final m in methods) '${m.label} (${m.rule})',
    ],
    for (final s in sections)
      for (final row in standings(e, s))
        [
          _safe(s.name),
          s.players.indexOf(row.player.id) + 1,
          _safe(reportName(row.player.name)),
          row.player.rating,
          scoreText(row.points),
          for (final m in methods) row.tiebreak(m)?.number ?? '',
        ],
  ]);
}

String _safe(String text) =>
    RegExp(r'^[=+@\-\t\r]').hasMatch(text) ? "'$text" : text;

/// Half-points as printed on paper: ½, 1½.
String _halves(int n) => n == 1
    ? '½'
    : n.isOdd
    ? '${n ~/ 2}½'
    : '${n ~/ 2}';

/// Paper schedules never post rounds or change the tournament. Preserve edited
/// posted pairings; fill the remaining round-robin rounds from the fixed draw.
/// Swiss sheets contain only the selected (or latest posted) round.
List<Round> reportPairingRounds(
  Section section, {
  int? roundNumber,
  bool currentRoundOnly = false,
  Event? event,
}) {
  // A Scheveningen is a fixed table too; with the event's team labels its
  // sheet lists every round like a round robin's.
  final scheveningen =
      event != null &&
      section.format == Format.scheveningen &&
      scheveningenProblem(event, section) == null;
  if (currentRoundOnly ||
      !(hasFixedSchedule(section) || scheveningen) ||
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
  final count = min(
    section.plannedRounds,
    scheveningen
        ? scheveningenSchedule(event, section).length
        : sectionSchedule(section).length,
  );
  return [
    for (var n = 1; n <= count; n++)
      section.rounds.where((r) => r.number == n).firstOrNull ??
          (scheveningen
              ? scheveningenPaperRound(event, section, n)
              : paperRound(section, n)),
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
  return rankStandings(rows, tiebreaks: event.useTiebreaks);
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
      ' ${reportName(event.players.where((p) => p.id == id).firstOrNull?.name ?? '?')}';
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
                label(reportName(event.player(player).name), left: true),
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
  bool alphabetical = false,
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
  if (kind == ReportKind.conditions) {
    return conditionsPdf(source, a4: a4, font: font, bold: bold);
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
                '${reportName(source.player(id).name)}'
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
        event: source,
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
        // Rule 17B1: a changed start time or other notice travels with the
        // pairings.
        if (round.note.trim().isNotEmpty) {
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Text(
                round.note.trim(),
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          );
        }
        widgets.add(
          pw.TableHelper.fromTextArray(
            headers: ['Board', 'Result', 'White', 'Black', 'Result'],
            data: [
              for (final g in round.games)
                [
                  '${g.board}${scope.doubleGames ? ' / ${g.leg}' : ''}',
                  '',
                  // A bughouse side is both partners.
                  [
                    g.white,
                    if (g.whitePartner.isNotEmpty) g.whitePartner,
                  ].map((id) => reportName(source.player(id).name)).join(' / '),
                  [
                    g.black,
                    if (g.blackPartner.isNotEmpty) g.blackPartner,
                  ].map((id) => reportName(source.player(id).name)).join(' / '),
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
                '${reportName(source.player(bye.player).name)}: ${bye.allocated ? 'Bye' : bye.reason} (${_halves(bye.points)})',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          );
        }
        if (alphabetical) {
          widgets.addAll(_alphabeticalPairings(source, scope, round));
        }
      }
    }
    if (kind == ReportKind.standings && s.format == Format.ladder) {
      title('Ladder');
      String name(String id) => reportName(e.player(id).name);
      grid(
        ['#', 'Player', 'Rating', 'Games', 'Last result'],
        [
          for (final (i, id) in s.players.indexed)
            [
              '${i + 1}',
              name(id),
              wallChartRating(e.player(id)),
              '${ladderGames(s, id).length}',
              ladderLastResult(s, id, name),
            ],
        ],
      );
      widgets.add(
        pw.Text(
          'Challenge up to $ladderChallengeRange places above you. A win takes the loser\'s place; '
          'a draw or a loss changes nothing.',
          style: const pw.TextStyle(fontSize: 9),
        ),
      );
    } else if (kind == ReportKind.standings) {
      title(
        'Standings${ceiling == 0 ? '' : ' · Under $ceiling'}${forPrizes ? ' · Excluding early round-robin withdrawals' : ''}',
      );
      // Rule 34B: the posted order, named in full under the grid.
      final methods = standingsTiebreaks(e, s);
      grid(
        [
          'Rank',
          'Player',
          'Rating',
          'Points',
          for (final m in methods) m.short,
        ],
        [
          for (final r in table)
            [
              table.where((x) => x.rank == r.rank).length > 1
                  ? 'T-${r.rank}'
                  : '${r.rank}',
              reportName(r.player.name),
              r.player.rating == 0 ? 'UNR' : '${r.player.rating}',
              _halves(r.points),
              for (final m in methods) r.tiebreak(m)?.text ?? '',
            ],
        ],
      );
      widgets.add(
        pw.Text(
          'Tie-breaks (rule 34B): ${[for (final (i, m) in methods.indexed) '${i + 1}. ${m.label} (${m.rule})'].join(', ')}. '
          '${e.useTiebreaks ? 'Equal values on every method remain tied.' : 'Places are shared on points; the values are shown for reference.'}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      );
      // A knockout places by the bracket, not by points.
      if (s.format == Format.knockout) {
        widgets.add(pw.SizedBox(height: 8));
        widgets.add(
          pw.Text(
            knockoutBracketLines(e, s).join('\n'),
            style: const pw.TextStyle(fontSize: 9),
          ),
        );
      }
    }
    if (kind == ReportKind.crosstable) {
      title('Crosstable');
      final numbers = {for (final (i, id) in s.players.indexed) id: i + 1};
      // Rule 28O: result on the first line, score so far on the second.
      final totals = {
        for (final row in table)
          row.player.id: cumulativeScores(s, row.player.id),
      };
      grid(
        ['#', 'Player', 'Rtg', 'Pts', for (final r in s.rounds) 'R${r.number}'],
        [
          for (final row in table)
            [
              '${numbers[row.player.id]}',
              reportName(row.player.name),
              wallChartRating(row.player),
              _halves(row.points),
              for (final (i, r) in s.rounds.indexed)
                '${crosstableCell(e, r, row.player.id, numbers)}\n'
                    '${_halves(totals[row.player.id]![i])}',
            ],
        ],
      );
      widgets.add(
        pw.Text(
          'W/D/L = win/draw/loss; number = opponent; w/b = color; the second '
          'line is the score after that round. '
          'X/F = forfeit win/loss; ? = unresolved. B--- = full-point bye; '
          'H--- = half-point bye; U--- = zero-point bye (unpaired); '
          '-- = not paired. NEW = unrated with no US Chess ID; UNR = unrated.',
          style: const pw.TextStyle(fontSize: 9),
        ),
      );
    }
    if (kind == ReportKind.prizes) {
      final a = allocatePrizes(e, s);
      title(
        'Prizes · ${a.entries} entries'
        '${a.table.basedOn > 0 ? ' · based on ${a.table.basedOn}' : ''}'
        '${a.payoutPercent == 100 ? '' : ' · paying ${a.payoutPercent}%'}',
      );
      if (a.table.isEmpty) {
        widgets.add(pw.Text('No prizes are announced for this section.'));
      } else {
        grid(
          ['Prize', 'Amount', 'Awarded to'],
          [
            for (final line in a.lines)
              [line.prize.title, _prizeAmount(line), _prizeOutcome(e, line)],
          ],
        );
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
            child: pw.Text(
              'Awards',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
        );
        grid(
          ['Player', 'Points', 'Cash', 'Trophy'],
          [
            for (final w in a.awards)
              [
                reportName(w.player.name),
                _halves(w.points),
                w.cents > 0 ? dollars(w.cents) : '',
                w.trophies.map((t) => t.title).join(', '),
              ],
            ['Total', '', dollars(a.paidCents), ''],
          ],
        );
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
            child: pw.Text(
              'How the prizes were allocated',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
        );
        for (final x in a.explanations) {
          widgets.add(
            pw.Bullet(text: x, style: const pw.TextStyle(fontSize: 10)),
          );
        }
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              'Tied cash prizes are pooled and split equally (32B, 34C); '
              'trophies follow the standings order (32F1, 33D2).',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        );
      }
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

/// Rule 34B: the announced tie-break order, or the US Chess default for
/// the section's format (34E for Swiss, 34F for round robins).
String _conditionsTiebreaks(Event e, Section s) => e.tiebreaks.isNotEmpty
    ? e.tiebreaks.map(tiebreakLabel).join(', ')
    : 'US Chess default: ${defaultTiebreaks(s.format).map((m) => m.label).join(', ')}';

String _conditionsDollars(Object? cents) {
  final n = cents is num ? cents.toInt() : 0;
  final whole = n ~/ 100, part = n % 100;
  final digits = whole.toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return '\$$grouped${part == 0 ? '' : '.${part.toString().padLeft(2, '0')}'}';
}

/// Rules 26A, 34B, 25, 22C4 and 17B1: the announced conditions of the event,
/// to post before round 1. One page per event, not per section.
Future<Uint8List> conditionsPdf(
  Event e, {
  bool a4 = false,
  pw.Font? font,
  pw.Font? bold,
}) async {
  final doc = pw.Document();
  final widgets = <pw.Widget>[];
  final small = const pw.TextStyle(fontSize: 10);
  void heading(String text) => widgets.add(
    pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
    ),
  );
  void line(String text) => widgets.add(pw.Text(text, style: small));
  void table(List<String> headers, List<List<String>> rows) => widgets.add(
    pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      cellStyle: small,
      headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      cellPadding: const pw.EdgeInsets.all(4),
    ),
  );
  final tds = [
    if (e.tdId.isNotEmpty) 'Chief TD ${e.tdId}',
    if (e.assistantTdId.isNotEmpty) 'Assistant chief TD ${e.assistantTdId}',
    if (e.otherTdIds.isNotEmpty) 'Other TDs ${e.otherTdIds}',
  ];
  line(
    [
      e.endDate.isEmpty ? e.date : '${e.date} – ${e.endDate}',
      if (e.venue.isNotEmpty) e.venue,
      if (e.online) 'Online event (Chapter 10)',
    ].join(' · '),
  );
  if (tds.isNotEmpty) line(tds.join(' · '));
  if (e.policy.trim().isNotEmpty) {
    heading('Announced conditions');
    line(e.policy.trim());
  }

  heading('Sections and pairing rules (rule 26A)');
  table(
    ['Section', 'Format', 'Rounds', 'Time control', 'Pairing settings'],
    [
      for (final s in e.sections)
        [
          s.name,
          s.format.label,
          '${s.plannedRounds}',
          [
            s.effectiveTimeControl(e),
            ?delayHint(s.effectiveTimeControl(e)),
          ].join(' · '),
          [
            if (s.accelerated.isNotEmpty)
              'Accelerated pairings: ${s.accelerated == 'addedScore'
                  ? 'added score (28R1)'
                  : s.accelerated == 'adjustedRating'
                  ? 'adjusted rating (28R2)'
                  : s.accelerated}',
            if (s.avoidTeammates) 'Team-mates not paired (28N)',
            if (s.variations.isNotEmpty)
              'Variations: ${(s.variations.toList()..sort()).join(', ')}',
            if (hasFixedSchedule(s) && s.rrTable.isNotEmpty)
              'Table: ${s.rrTable}',
            if (s.doubleCycle) 'Double round robin, second cycle (30F)',
            if (s.doubleGames) 'Both colors each round',
            if (s.ratingCeiling > 0) 'Under ${s.ratingCeiling}',
          ].join('; '),
        ],
    ],
  );

  heading('Tie-breaks (rule 34B)');
  for (final s in e.sections) {
    line('${s.name}: ${_conditionsTiebreaks(e, s)}');
  }
  if (e.sections.isEmpty) {
    line(_conditionsTiebreaks(e, Section(id: '', name: '', players: const [])));
  }

  heading('Half-point byes (rule 22C)');
  for (final s in e.sections) {
    line('${s.name}: ${ByePolicy.fromJson(s.byeRules).describe()}');
  }
  final irrevocable = [
    for (final p in e.players)
      if (p.irrevocableByes.isNotEmpty)
        (p, (p.irrevocableByes.toList()..sort())),
  ];
  heading('Irrevocable byes (rule 22C4)');
  if (irrevocable.isEmpty) {
    line('None declared.');
  } else {
    table(
      ['Player', 'Section', 'Rounds'],
      [
        for (final (p, rounds) in irrevocable)
          [
            reportName(p.name),
            e.sectionOf(p.id)?.name ?? '',
            rounds
                .map(
                  (r) => p.byes[r] == null
                      ? '$r (cancelled: a win counts as a draw for prizes, 22C5)'
                      : '$r',
                )
                .join(', '),
          ],
      ],
    );
  }

  heading('Prizes (rule 25)');
  var anyPrizes = false;
  for (final s in e.sections) {
    final list = s.prizes['list'];
    if (list is! List || list.isEmpty) continue;
    anyPrizes = true;
    final basedOn = s.prizes['basedOn'];
    final fund = s.prizes['fundCents'];
    line(
      [
        s.name,
        if (fund is num && fund > 0) 'fund ${_conditionsDollars(fund)}',
        if (basedOn is num && basedOn > 0) 'based on $basedOn entries',
        if (s.prizes['withdrawnEligible'] == true)
          'withdrawn players stay eligible',
      ].join(' · '),
    );
    table(
      ['Prize', 'Eligibility', 'Amount'],
      [
        for (final entry in list)
          if (entry is Map)
            [
              '${entry['label'] ?? ''}'.trim().isEmpty
                  ? '${entry['kind'] ?? ''} ${entry['place'] ?? ''}'.trim()
                  : '${entry['label']}',
              switch ('${entry['kind'] ?? ''}') {
                'class' => '${entry['min'] ?? 0}–${entry['max'] ?? 0}',
                'under' => 'Under ${entry['max'] ?? 0}',
                'points' => '${entry['points'] ?? 0} half-points',
                final kind => kind,
              },
              [
                if ((entry['cents'] as num? ?? 0) > 0)
                  _conditionsDollars(entry['cents']),
                if (entry['trophy'] == true) 'trophy',
              ].join(' + '),
            ],
      ],
    );
  }
  if (!anyPrizes) line('No prize table announced.');

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
          pw.Text('Event conditions${e.practice ? ' · PRACTICE COPY' : ''}'),
        ],
      ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Revision ${e.revision}',
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
  return doc.save();
}

/// Rule 28J TD TIP: the same round's pairings by player name, so a player
/// who cannot find a board number can find their own name.
List<pw.Widget> _alphabeticalPairings(
  Event source,
  Section scope,
  Round round,
) {
  final rows = <(String key, List<String> cells)>[];
  for (final g in round.games) {
    for (final (id, color, opponent) in [
      (g.white, 'White', g.black),
      (g.black, 'Black', g.white),
    ]) {
      final name = reportName(source.player(id).name);
      rows.add((
        nameKey(name),
        [
          name,
          '${g.board}${scope.doubleGames ? ' / ${g.leg}' : ''}',
          color,
          reportName(source.player(opponent).name),
        ],
      ));
    }
  }
  for (final bye in round.byes) {
    final name = reportName(source.player(bye.player).name);
    rows.add((
      nameKey(name),
      [
        name,
        '',
        '',
        '${bye.allocated ? 'Bye' : bye.reason} (${_halves(bye.points)})',
      ],
    ));
  }
  rows.sort((a, b) => a.$1.compareTo(b.$1));
  return [
    pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12, bottom: 5),
      child: pw.Text(
        'Round ${round.number} by name',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
    ),
    pw.TableHelper.fromTextArray(
      headers: ['Player', 'Board', 'Color', 'Opponent'],
      data: [for (final row in rows) row.$2],
      tableWidth: pw.TableWidth.max,
      columnWidths: {
        0: const pw.FlexColumnWidth(),
        1: const pw.FixedColumnWidth(48),
        2: const pw.FixedColumnWidth(48),
        3: const pw.FlexColumnWidth(),
      },
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.centerLeft,
      },
      headerAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.centerLeft,
      },
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
      cellStyle: const pw.TextStyle(fontSize: 10),
      headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    ),
  ];
}
