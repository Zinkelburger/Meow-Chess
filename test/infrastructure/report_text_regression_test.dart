import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/reports.dart';

import 'pairing_sheets_test.dart' show pdfText;

Event event({String first = 'Alice'}) => Event(
  id: 'event',
  name: 'Club',
  date: '2026-01-01',
  players: [
    Player(id: 'a', name: first),
    Player(id: 'b', name: 'Bob'),
    Player(id: 'c', name: 'Carol'),
    Player(id: 'd', name: 'Dee'),
    Player(id: 'e', name: 'Eve'),
  ],
  sections: [
    Section(
      id: 'section',
      name: 'Open',
      format: Format.swiss,
      players: ['a', 'b', 'c', 'd', 'e'],
      plannedRounds: 1,
      rounds: [
        Round(
          number: 1,
          games: [
            Game(
              id: 'game',
              white: 'a',
              black: 'b',
              board: 1,
              outcome: Outcome.whiteWin,
            ),
          ],
          byes: [
            ByeAward('c', 2, 'Odd player'),
            ByeAward('d', 1, 'Requested'),
            ByeAward('e', 0, 'Requested'),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  test('standings CSV starts with a UTF-8 byte-order mark for Excel', () {
    final csv = standingsCsv(event(first: 'José'));
    expect(csv, startsWith('﻿Section,'));
    expect(utf8.encode(csv).take(3), [0xEF, 0xBB, 0xBF]);
    final rows = Csv(
      autoDetect: false,
    ).decode(csv.substring(1)).map((r) => r.map((v) => '$v').toList());
    expect(rows.first.first, 'Section');
    expect(rows.any((r) => r.contains('José')), true);
  });

  test('a name with line breaks prints on one aligned line', () async {
    final e = event(first: 'Ada\nLovelace\t Byron');
    final text = crosstable(e);
    expect(text, isNot(contains('Ada\n')));
    final lines = text.split('\n').where((l) => l.contains('W2w')).toList();
    expect(lines.single, contains('Ada Lovelace Byron'));
    // Every player row's rating sits under the Rtg heading; rule 28O prints
    // NEW for an unrated player with no US Chess ID.
    final all = text.split('\n');
    final rating = all.firstWhere((l) => l.contains('Rtg')).indexOf('Rtg');
    final rows = all.where((l) => RegExp(r'^\s+\d  ').hasMatch(l)).toList();
    expect(rows, hasLength(5));
    for (final row in rows) {
      expect(row.substring(rating - 1, rating + 3).trim(), 'NEW', reason: row);
    }
    expect(standingsCsv(e), contains('Ada Lovelace Byron'));
    expect(standingsCsv(e), isNot(contains('Ada\n')));
    final pdf = pdfText(await reportPdf(e, ReportKind.standings));
    // The PDF text helper drops spaces between words.
    expect(pdf, contains('AdaLovelaceByron'));
    expect(pdf, isNot(contains('\t')));
  });

  test('the crosstable legend explains exactly the codes it prints', () async {
    final e = event();
    final round = e.sections.single.rounds.single;
    const numbers = {'a': 1, 'b': 2, 'c': 3, 'd': 4, 'e': 5};
    expect(
      [
        for (final id in ['c', 'd', 'e']) crosstableCell(e, round, id, numbers),
      ],
      ['B---', 'H---', 'U---'],
    );
    expect(crosstableCell(e, Round(number: 2, games: []), 'a', numbers), '--');
    final pdf = pdfText(await reportPdf(e, ReportKind.crosstable));
    for (final legend in [
      'B--- = full-point bye',
      'H--- = half-point bye',
      'U--- = zero-point bye',
      '-- = not paired',
      'X/F = forfeit win/loss',
    ]) {
      // The PDF text helper drops spaces between words.
      expect(pdf, contains(legend.replaceAll(' ', '')));
    }
    expect(pdf, isNot(contains('BYE=awardedpoints')));
  });
}
