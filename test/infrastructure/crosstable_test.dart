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
      Player(id: 'a', name: 'Alice'),
      Player(id: 'b', name: 'Bob'),
      Player(id: 'c', name: 'Carol'),
    ],
    sections: [
      Section(
        id: 'section',
        name: 'Open',
        format: Format.swiss,
        players: ['a', 'b', 'c'],
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
            byes: [ByeAward('c', 1, 'Requested')],
          ),
        ],
      ),
    ],
  );
  const numbers = {'a': 1, 'b': 2, 'c': 3};
  test(
    'text and PDF retain reciprocal opponent results and bye points',
    () async {
      final text = crosstable(event);
      final pdf = pdfText(await reportPdf(event, ReportKind.crosstable));
      for (final cell in ['W2w', 'L1b', 'H---']) {
        expect(text, contains(cell));
        expect(pdf, contains(cell.replaceAll(' ', '')));
      }
    },
  );
  test(
    'cells distinguish unresolved games, forfeits, absences and double legs',
    () {
      final round = event.sections.single.rounds.single;
      final game = round.games.single;
      expect(
        crosstableCell(
          event,
          round.copy(games: [game.copy(outcome: Outcome.unreported)]),
          'a',
          numbers,
        ),
        '?2w',
      );
      expect(
        crosstableCell(
          event,
          round.copy(games: [game.copy(outcome: Outcome.blackForfeit)]),
          'b',
          numbers,
        ),
        'X1b',
      );
      expect(crosstableCell(event, round.copy(byes: []), 'c', numbers), '--');
      final doubles = round.copy(
        games: [
          Game(
            id: 'second',
            white: 'b',
            black: 'a',
            board: 1,
            leg: 2,
            outcome: Outcome.draw,
          ),
          game,
        ],
      );
      expect(crosstableCell(event, doubles, 'a', numbers), 'W2w/D2b');
      expect(crosstableCell(event, doubles, 'b', numbers), 'L1b/D1w');
    },
  );
}
