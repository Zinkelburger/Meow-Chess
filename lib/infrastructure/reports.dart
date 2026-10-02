import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/model.dart';
import '../domain/standings.dart';

enum ReportKind { packet, pairings, standings, crosstable }

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

/// Sorts a wall list by surname, as players look for themselves.
String _surnameKey(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return [parts.last, ...parts.take(parts.length - 1)].join(' ').toLowerCase();
}

Future<Uint8List> reportPdf(
  Event e,
  ReportKind kind, {
  String? sectionId,
  bool a4 = false,
  pw.Font? font,
  pw.Font? bold,
}) async {
  final doc = pw.Document();
  for (final s in e.sections.where(
    (s) => s.players.isNotEmpty && (sectionId == null || s.id == sectionId),
  )) {
    final table = standings(e, s);
    final current = s.rounds.lastOrNull;
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
    if (kind == ReportKind.pairings || kind == ReportKind.packet) {
      title('Round ${current?.number ?? 1} · ${e.timeControl}');
      if (current == null) {
        widgets.add(pw.Text('No pairings posted.'));
      } else {
        for (final b in current.byes) {
          widgets.add(
            pw.Text(
              '${e.player(b.player).name}: ${b.reason} (${_halves(b.points)})',
            ),
          );
        }
        grid(
          ['Board', 'White', 'Result', 'Black'],
          [
            for (final g in current.games)
              [
                '${g.board}${s.doubleGames ? ' / ${g.leg}' : ''}',
                e.player(g.white).name,
                g.outcome.resolved ? g.outcome.label : '________',
                e.player(g.black).name,
              ],
          ],
        );
        if (kind == ReportKind.packet) {
          title('Alphabetical pairings');
          final games = current.games;
          final entries = [
            for (final g in games)
              (
                e.player(g.white).name,
                '${g.board}',
                'White',
                e.player(g.black).name,
              ),
            for (final g in games)
              (
                e.player(g.black).name,
                '${g.board}',
                'Black',
                e.player(g.white).name,
              ),
          ]..sort((a, b) => _surnameKey(a.$1).compareTo(_surnameKey(b.$1)));
          grid(
            ['Player', 'Board', 'Color', 'Opponent'],
            [
              for (final r in entries) [r.$1, r.$2, r.$3, r.$4],
            ],
          );
        }
      }
    }
    if (kind == ReportKind.standings || kind == ReportKind.packet) {
      title('Standings');
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
              'Revision ${e.revision} · ${e.timeControl}',
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
  return doc.save();
}
