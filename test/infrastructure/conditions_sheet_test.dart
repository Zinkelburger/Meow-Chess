import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/infrastructure/reports.dart';

String pdfText(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  final commands =
      RegExp(r'<<(.*?)>>\s*stream\r?\n(.*?)\r?\nendstream', dotAll: true)
          .allMatches(raw)
          .map((match) {
            final data = latin1.encode(match[2]!);
            return latin1.decode(
              match[1]!.contains('/FlateDecode') ? zlib.decode(data) : data,
            );
          })
          .join('\n');
  return RegExp(r'\(([^()]*)\)')
      .allMatches(commands)
      .map((m) => m[1]!)
      .join()
      .replaceAll(RegExp(r'\s+'), '');
}

Event sample() => Event(
  id: 'e',
  name: 'Autumn Open',
  date: '2026-10-10',
  venue: 'Boylston Chess Club',
  tdId: '12345678',
  timeControl: 'G/60',
  policy: 'Byes by noon Saturday.',
  tiebreaks: const ['solkoff', 'cumulative'],
  players: [
    Player(id: 'a', name: 'Ann Able', rating: 1800, irrevocableByes: {5}),
    Player(id: 'b', name: 'Bob Baker', rating: 1700),
    Player(id: 'c', name: 'Cy Cole', rating: 1600),
    Player(id: 'd', name: 'Di Dunn', rating: 1500),
  ],
  sections: [
    Section(
      id: 's',
      name: 'Open',
      format: Format.swiss,
      plannedRounds: 5,
      players: const ['a', 'b', 'c', 'd'],
      accelerated: 'addedScore',
      variations: const {'29E5h'},
      byeRules: const {'lastHalfByeRound': 4, 'irrevocableFromRound': 4},
      prizes: const {
        'fundCents': 50000,
        'list': [
          {'label': 'First', 'kind': 'place', 'place': 1, 'cents': 30000},
          {'label': 'U1700', 'kind': 'under', 'max': 1700, 'cents': 12550},
        ],
      },
    ),
  ],
);

void main() {
  test(
    '26A/34B/25/22C4: the conditions sheet lists what was announced',
    () async {
      final text = pdfText(await reportPdf(sample(), ReportKind.conditions));
      expect(text, contains('Eventconditions'));
      expect(text, contains('BoylstonChessClub'));
      expect(text, contains('ChiefTD12345678'));
      expect(text, contains('Byesbynoon'));
      expect(text, contains('Acceleratedpairings'));
      expect(text, contains('29E5h'));
      expect(text, contains('Solkoff,Cumulative'));
      expect(text, contains('throughround4'));
      expect(text, contains('irrevocablefromround4'));
      expect(text, contains('AnnAble'));
      expect(text, contains('\$500'));
      expect(text, contains('\$125.50'));
      expect(text, contains('Under1700'));
      // Rule 5E2: no delay stated on G/60.
      expect(text, contains('d5'));
    },
  );

  test('empty tie-breaks print the US Chess default order', () async {
    final text = pdfText(
      await reportPdf(
        sample().copy(tiebreaks: const []),
        ReportKind.conditions,
      ),
    );
    expect(text, contains('ModifiedMedian,Solkoff,Cumulative'));
  });

  test('17B1: the round note prints under the round title', () async {
    final e = sample();
    var n = 0;
    final round = proposeRound(e, e.sections.single, () => 'g${n++}').copy(
      note: 'Round 1 starts at 10:30 because of the late registration line.',
      postedAt: '2026-10-10T14:00:00Z',
    );
    final posted = e.copy(
      sections: [
        e.sections.single.copy(rounds: [round]),
      ],
    );
    final text = pdfText(await reportPdf(posted, ReportKind.pairings));
    expect(text, contains('startsat10:30'));
  });
}
