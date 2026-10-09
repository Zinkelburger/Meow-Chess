import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/reports.dart';

import 'pairing_sheets_test.dart' show pdfText;

void main() {
  final event = Event(
    id: 'event',
    name: 'Club',
    date: '2026-01-01',
    players: [
      Player(id: 'a', name: 'Alice', rating: 1800, memberId: '12345678'),
      Player(id: 'b', name: 'Bob'),
      Player(id: 'c', name: 'Carol', memberId: '87654321'),
      Player(id: 'd', name: 'Dee', rating: 1200, memberId: '11111111'),
    ],
    sections: [
      Section(
        id: 'section',
        name: 'Open',
        format: Format.swiss,
        players: ['a', 'b', 'c', 'd'],
        plannedRounds: 2,
        rounds: [
          Round(
            number: 1,
            games: [
              Game(
                id: 'g1',
                white: 'a',
                black: 'b',
                board: 1,
                outcome: Outcome.whiteWin,
              ),
              Game(
                id: 'g2',
                white: 'c',
                black: 'd',
                board: 2,
                outcome: Outcome.draw,
              ),
            ],
          ),
          Round(
            number: 2,
            games: [
              Game(
                id: 'g3',
                white: 'c',
                black: 'a',
                board: 1,
                outcome: Outcome.blackWin,
              ),
              Game(
                id: 'g4',
                white: 'b',
                black: 'd',
                board: 2,
                outcome: Outcome.blackForfeit,
              ),
            ],
          ),
        ],
      ),
    ],
  );

  test('rule 28O: cumulative scores, NEW and UNR on the wall chart', () async {
    expect(cumulativeScores(event.sections.single, 'a'), [2, 4]);
    expect(cumulativeScores(event.sections.single, 'd'), [1, 3]);
    expect(wallChartRating(event.player('a')), '1800');
    expect(wallChartRating(event.player('b')), 'NEW');
    expect(wallChartRating(event.player('c')), 'UNR');
    final text = crosstable(event);
    final alice = text.split('\n').firstWhere((l) => l.contains('Alice'));
    expect(alice, contains('W2w 1 '));
    expect(alice, contains('W3b 2 '));
    final dee = text.split('\n').firstWhere((l) => l.contains('Dee'));
    expect(dee, contains('D3b 0.5'));
    expect(dee, contains('X2b 1.5'));
    expect(dee, contains(' 1.5 '));
    expect(
      text.split('\n').firstWhere((l) => l.contains('Bob')),
      contains('NEW'),
    );
    expect(
      text.split('\n').firstWhere((l) => l.contains('Carol')),
      contains('UNR'),
    );
    final pdf = pdfText(await reportPdf(event, ReportKind.crosstable));
    // The PDF text helper drops spaces between words.
    expect(pdf, contains('NEW'));
    expect(pdf, contains('UNR'));
    expect(pdf, contains('W2w'));
    expect(pdf, contains('scoreafterthatround'));
  });

  test('rule 28J TIP: the pairing sheet can add a list by name', () async {
    final plain = pdfText(
      await reportPdf(event, ReportKind.pairings, roundNumber: 2),
    );
    expect(plain, isNot(contains('byname')));
    final named = pdfText(
      await reportPdf(
        event,
        ReportKind.pairings,
        roundNumber: 2,
        alphabetical: true,
      ),
    );
    expect(named, contains('Round2byname'));
    expect(named, contains('Opponent'));
    // Alphabetical: Alice is listed before Bob, Bob before Carol.
    final start = named.indexOf('Round2byname');
    final tail = named.substring(start);
    expect(
      tail,
      contains('Alice1BlackCarolBob2WhiteDeeCarol1WhiteAliceDee2BlackBob'),
    );
  });
}
