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

  test('a double round\'s full-point bye is four half-points', () {
    final round = Round(
      number: 1,
      games: const [],
      byes: [
        ByeAward('a', 4, 'Odd player', allocated: true),
        ByeAward('b', 2, 'Requested'),
        ByeAward('c', 0, 'Unpaired'),
      ],
    );
    final doubles = event.copy(
      sections: [
        event.sections.single.copy(doubleGames: true, rounds: [round]),
      ],
    );
    // Four half-points used to print as U, the zero-point bye.
    expect(crosstableCell(doubles, round, 'a', numbers), 'B---');
    // Two of a double round's four half-points are a part bye.
    expect(crosstableCell(doubles, round, 'b', numbers), 'H---');
    expect(crosstableCell(doubles, round, 'c', numbers), 'U---');
    expect(wallChartMarks(doubles, round, 'a', numbers).opponent, 'bye');
    expect(wallChartMarks(doubles, round, 'b', numbers).opponent, '½ bye');
    // The screen shows the same marks.
    expect(byeMark(4, doubleGames: true), 'B---');
    expect(byeMark(2, doubleGames: true), 'H---');
    expect(byeMark(2), 'B---');
  });

  group('bughouse partners', () {
    // Ann and Bo against Cy and Di: Ann and Cy on board 1, their partners
    // on board 2 with the colors swapped (bughouse.dart).
    final players = [
      for (final (id, name) in [
        ('a', 'Ann'),
        ('b', 'Bo'),
        ('c', 'Cy'),
        ('d', 'Di'),
      ])
        Player(id: id, name: name),
    ];
    final round = Round(
      number: 1,
      games: [
        Game(
          id: 'm1',
          white: 'a',
          black: 'c',
          board: 1,
          whitePartner: 'b',
          blackPartner: 'd',
          outcome: Outcome.whiteWin,
        ),
      ],
    );
    final bughouse = Event(
      id: 'bug',
      name: 'Bughouse',
      date: '2026-01-01',
      players: players,
      sections: [
        Section(
          id: 's',
          name: 'Bughouse',
          format: Format.bughouse,
          unrated: true,
          players: const ['a', 'b', 'c', 'd'],
          partners: const [
            ['a', 'b'],
            ['c', 'd'],
          ],
          plannedRounds: 1,
          rounds: [round],
        ),
      ],
    );
    const numbers = {'a': 1, 'b': 2, 'c': 3, 'd': 4};

    test('each partner has the match result at their own board', () {
      // Partners used to print as unpaired (--) with no score so far.
      expect(crosstableCell(bughouse, round, 'a', numbers), 'W3w');
      expect(crosstableCell(bughouse, round, 'b', numbers), 'W4b');
      expect(crosstableCell(bughouse, round, 'c', numbers), 'L1b');
      expect(crosstableCell(bughouse, round, 'd', numbers), 'L2w');
      final section = bughouse.sections.single;
      expect(cumulativeScores(bughouse, section, 'b'), [2]);
      expect(cumulativeScores(bughouse, section, 'd'), [0]);
      expect(crosstable(bughouse), contains('W4b 1'));
    });

    test('the by-name pairings list every partner', () async {
      final text = pdfText(
        await reportPdf(bughouse, ReportKind.pairings, alphabetical: true),
      );
      final byName = text.substring(text.indexOf('Round1byname'));
      // Bo plays Black against Di on the second board of match 1.
      expect(byName, contains('Bo1BlackDi'));
      expect(byName, contains('Di1WhiteBo'));
    });
  });

  test('an ASCII crosstable prints a knockout bracket in ASCII', () {
    final knockout = event.copy(
      sections: [
        Section(
          id: 'k',
          name: 'Knockout',
          format: Format.knockout,
          players: const ['a', 'b'],
          plannedRounds: 1,
        ),
      ],
    );
    // The bracket's dashes and separators used to refuse the export as if
    // a name needed an ASCII alias.
    final text = crosstable(knockout, asciiOnly: true);
    expect(text, contains('Bracket: 2-game matches - director decides ties'));
    expect(text.codeUnits.every((c) => c < 128), isTrue);
  });
}
