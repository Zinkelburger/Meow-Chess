// Printed reports keep every word on the paper, inside its column and clear
// of its neighbours, for rosters built to break layouts: long and
// unbreakable names, long section and event names, many rounds, many
// players, Letter and A4. See test/pdf_geometry.dart.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../pdf_geometry.dart';

/// A Swiss of [players] played through [rounds], every result in.
Future<Event> tournament({
  required int players,
  required int rounds,
  required String Function(int) name,
  String section = 'Open',
  String event = 'Saturday Swiss',
  int Function(int)? rating,
}) async {
  final c = TournamentController(SqliteEventRepository(':memory:'));
  try {
    c.create(event);
    c.importPlayers([
      for (var i = 0; i < players; i++)
        Player(
          id: 'p$i',
          name: name(i),
          rating: rating?.call(i) ?? 2400 - i * 7,
          memberId: '${12000000 + i}',
          club: i.isEven ? 'Boylston Chess Club of Greater Boston' : '',
          team: i % 3 == 0 ? 'Brookline High School Varsity' : '',
        ),
    ]);
    c.addSection(section, Format.swiss, rounds);
    const outcomes = [
      Outcome.whiteWin,
      Outcome.draw,
      Outcome.blackWin,
      Outcome.whiteForfeit,
    ];
    for (var r = 0; r < rounds; r++) {
      c.post(await c.propose());
      for (final (i, g) in c.event!.sections.single.rounds.last.games.indexed) {
        c.recordResult(g.id, outcomes[(i + r) % outcomes.length]);
      }
    }
    return c.event!;
  } finally {
    c.dispose();
  }
}

/// Words of [names] that some report split across runs, such as a long
/// name broken mid-word to fit its column.
Future<List<String>> splitWords(Event e, Iterable<String> names) async {
  final out = <String>{};
  for (final kind in [
    ReportKind.standings,
    ReportKind.wallChart,
    ReportKind.pairings,
  ]) {
    for (final a4 in [false, true]) {
      final (font, bold) = fonts['Inter']!;
      final runs = {
        for (final p in pdfPages(
          await reportPdf(e, kind, a4: a4, font: font, bold: bold),
        ))
          for (final r in p.runs) r.text,
      };
      for (final word in names.expand((n) => n.split(' '))) {
        if (word.length > 3 && !runs.any((r) => r.contains(word))) {
          out.add('${kind.name}${a4 ? ' A4' : ''}: "$word"');
        }
      }
    }
  }
  return out.toList();
}

pw.Font _ttf(String name) => pw.Font.ttf(
  ByteData.sublistView(File('assets/fonts/$name.ttf').readAsBytesSync()),
);

/// The fonts reports are printed in: Inter, as the app prints them, and the
/// PDF's built-in Helvetica, which reports fall back to.
final fonts = <String, (pw.Font?, pw.Font?)>{
  'Inter': (_ttf('Inter-Regular'), _ttf('Inter-SemiBold')),
  'Helvetica': (null, null),
};

Future<List<String>> problems(Event e) async {
  final out = <String>[];
  for (final MapEntry(key: face, value: (font, bold)) in fonts.entries) {
    for (final kind in ReportKind.values) {
      for (final a4 in [false, true]) {
        final Uint8List bytes;
        try {
          bytes = await reportPdf(e, kind, a4: a4, font: font, bold: bold);
        } on TournamentException {
          continue; // Not offered for this event, as in the app.
        }
        final pages = pdfPages(bytes);
        // A reader that found nothing would find nothing wrong.
        if (pages.every((p) => p.runs.isEmpty)) {
          out.add('$face ${kind.name}${a4 ? ' A4' : ''}: no text read');
        }
        for (final p in layoutProblems(pages)) {
          out.add('$face ${kind.name}${a4 ? ' A4' : ''}: $p');
        }
      }
    }
  }
  return out;
}

void main() {
  group('the checker', () {
    test(
      'finds a word cut off by its cell and words printed over each other',
      () async {
        final doc = pw.Document()
          ..addPage(
            pw.Page(
              pageFormat: PdfPageFormat.letter,
              build: (_) => pw.Column(
                children: [
                  // A word wider than its clipped box: cut off on paper.
                  pw.SizedBox(
                    width: 20,
                    child: pw.ClipRect(
                      child: pw.Text('Unbreakablename', softWrap: false),
                    ),
                  ),
                  pw.Stack(children: [pw.Text('Overlap'), pw.Text('Overlap')]),
                ],
              ),
            ),
          );
        final found = layoutProblems(pdfPages(await doc.save()));
        expect(
          found,
          contains(startsWith('cut off by its cell: "Unbreakablename"')),
        );
        expect(found, contains(startsWith('overlapping: "Overlap"')));
      },
    );

    test('passes an ordinary event', () async {
      final e = await tournament(
        players: 12,
        rounds: 4,
        name: (i) => 'Player $i',
      );
      expect(await problems(e), isEmpty);
    });
  });

  test('long names wrap inside their columns', () async {
    final e = await tournament(
      players: 24,
      rounds: 5,
      name: (i) => i.isEven
          ? 'Maximilian-Alexander Montgomery-Worthington III'
          : 'Ñúñez Zoë Ångström-Øverli de la Torre',
      section: 'Under 1600 Scholastic Reserve (Grades K–12)',
      event: 'Greater Boston Scholastic Championship and Open Weekend Swiss',
    );
    expect(await problems(e), isEmpty);
    expect(
      await splitWords(e, [for (final p in e.players) p.name]),
      isEmpty,
      reason: 'names wrap between words, not inside them',
    );
  });

  test('a name with no break point fits or is shortened, never cut', () async {
    final e = await tournament(
      players: 10,
      rounds: 3,
      name: (i) => 'Supercalifragilisticexpialidocious$i',
    );
    expect(await problems(e), isEmpty);
    expect(
      await splitWords(e, [for (final p in e.players) p.name]),
      isEmpty,
      reason: 'names print whole, not broken mid-word',
    );
  });

  test('nine rounds and unrated players fit a wall chart', () async {
    final e = await tournament(
      players: 40,
      rounds: 9,
      name: (i) => 'Player Number $i',
      rating: (i) => i % 5 == 0 ? 0 : 2899 - i,
    );
    expect(await problems(e), isEmpty);
  });

  test('a large section breaks across pages cleanly', () async {
    final e = await tournament(
      players: 180,
      rounds: 4,
      name: (i) => 'Entrant ${i.toString().padLeft(3, '0')} Lastname',
    );
    expect(await problems(e), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
