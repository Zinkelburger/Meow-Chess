// The sheets a TD posts, written for scripts/print_checks.py to render and
// compare against test/goldens/print (MEOW_PRINT_SAMPLES=1). Each is also
// checked here for what it must say, so this runs without the renderer too.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:pdf/widgets.dart' as pw;

import '../pdf_geometry.dart';
import '../print_fixtures.dart';

void main() {
  pw.Font ttf(String name) => pw.Font.ttf(
    ByteData.sublistView(File('assets/fonts/$name.ttf').readAsBytesSync()),
  );
  final font = ttf('Inter-Regular'), bold = ttf('Inter-SemiBold');

  Future<Uint8List> sheet(
    String name,
    Event event,
    ReportKind kind, {
    int? round,
    bool a4 = false,
  }) async {
    final bytes = await reportPdf(
      event,
      kind,
      roundNumber: round,
      a4: a4,
      font: font,
      bold: bold,
    );
    expect(layoutProblems(pdfPages(bytes)), isEmpty, reason: name);
    if (Platform.environment['MEOW_PRINT_SAMPLES'] == '1') {
      Directory('artifacts/print-sheets').createSync(recursive: true);
      File('artifacts/print-sheets/golden-$name.pdf').writeAsBytesSync(bytes);
    }
    return bytes;
  }

  String words(Uint8List bytes, int page) =>
      [for (final run in pdfPages(bytes)[page].runs) run.text].join(' ');

  test('a quad is one posted grid with every round', () async {
    final bytes = await sheet('quad', printQuad(), ReportKind.pairings);
    expect(pdfPages(bytes), hasLength(1));
    final text = words(bytes, 0);
    expect(text, contains('Round 3'));
    expect(text, isNot(contains('Board')));
  });

  test(
    'a round robin posts its grid alone, then the board tables to find seats',
    () async {
      final bytes = await sheet('rr8', printRoundRobin(), ReportKind.pairings);
      final grid = words(bytes, 0);
      expect(grid, contains('Round-robin pairing sheet'));
      expect(grid, contains('R7'));
      expect(grid, isNot(contains('Board')));
      expect(words(bytes, 1), contains('Board'));
      expect(words(bytes, 1), contains('Round 1'));
      // Eight players and seven rounds fit one table on one page.
      expect(
        grid,
        contains('Montgomery'),
        reason: 'the grid lists players by name',
      );
      expect(grid.split('R1').length, 2, reason: 'one table, one header');
    },
  );

  test('a round robin grid splits only when it cannot fit across', () async {
    final bytes = await reportPdf(
      printRoundRobin(count: 12, played: 0),
      ReportKind.pairings,
      font: font,
      bold: bold,
    );
    final all = [
      for (final p in pdfPages(bytes))
        for (final r in p.runs) r.text,
    ];
    expect(all, containsAll(['R1', 'R7', 'R8', 'R11']));
    expect(layoutProblems(pdfPages(bytes)), isEmpty);
  });

  test('a current-round print stays one round, without the grid', () async {
    final bytes = await reportPdf(
      printRoundRobin(),
      ReportKind.pairings,
      roundNumber: 2,
      currentRoundOnly: true,
      font: font,
      bold: bold,
    );
    expect(pdfPages(bytes), hasLength(1));
    final text = words(bytes, 0);
    expect(text, isNot(contains('Round-robin pairing sheet')));
    expect(text, contains('Round 2'));
    expect(text, isNot(contains('Round 3')));
  });

  test(
    'a round robin wall chart shows coming pairings with no score yet',
    () async {
      final event = printRoundRobin();
      final bytes = await sheet('rr8-wall', event, ReportKind.wallChart);
      final runs = [
        for (final p in pdfPages(bytes))
          for (final r in p.runs) r,
      ];
      final section = event.sections.single;
      final scheduled = wallChartScheduledRounds(event, section);
      expect(scheduled.keys, [3, 4, 5, 6, 7]);
      // The marks of round 7 for player 1 are on the chart, no "?" among them.
      final marks = wallChartMarks(event, scheduled[7]!, 'p0', {
        for (final (i, id) in section.players.indexed) id: i + 1,
      }, scheduled: true);
      expect(marks.opponent, isNot(contains('?')));
      expect(runs.map((r) => r.text), contains(marks.opponent));
      final legend = [for (final r in runs) r.text].join(' ');
      expect(legend, contains('still to play'));
    },
  );

  test('a Swiss wall chart still leaves unpaired rounds blank', () async {
    final event = printSwiss(count: 8);
    expect(wallChartScheduledRounds(event, event.sections.single), isEmpty);
    final bytes = await sheet('swiss-wall', event, ReportKind.wallChart);
    final legend = [
      for (final p in pdfPages(bytes))
        for (final r in p.runs) r.text,
    ].join(' ');
    expect(legend, contains('not yet paired'));
  });

  test(
    'a Swiss prints the selected round on as many pages as it needs',
    () async {
      final event = printSwiss();
      final latest = await sheet(
        'swiss-round3',
        event,
        ReportKind.pairings,
        round: 3,
      );
      expect(words(latest, 0), contains('Round 3'));
      expect(words(latest, 0), isNot(contains('Round 2')));
      expect(pdfPages(latest), isNotEmpty);
      final earlier = await reportPdf(
        event,
        ReportKind.pairings,
        roundNumber: 2,
        font: font,
        bold: bold,
      );
      expect(words(earlier, 0), contains('Round 2'));
    },
  );

  test('A4 is really A4', () async {
    final bytes = await sheet(
      'quad-a4',
      printQuad(),
      ReportKind.pairings,
      a4: true,
    );
    expect(pdfPages(bytes).single.height.round(), 842);
    expect(pdfPages(bytes).single.width.round(), 595);
  });

  test('the remaining posted sheets are laid out cleanly', () async {
    await sheet('players', printSwiss(count: 20), ReportKind.sections);
    await sheet('standings', printRoundRobin(), ReportKind.standings);
  });
}
