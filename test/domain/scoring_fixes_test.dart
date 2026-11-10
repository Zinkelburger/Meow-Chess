import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/holland.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/standings.dart';

Game _g(String id, String white, String black, Outcome outcome) =>
    Game(id: id, white: white, black: black, board: 1, outcome: outcome);

void main() {
  test('30I: a plus score is more than half the scheduled games, forfeit '
      'wins included', () {
    // a 3/3. b and c 1½/3: an even score, though c's includes a forfeit
    // win and so only two games played.
    final e = Event(
      id: 'e',
      name: 'Holland',
      date: '2026-10-10',
      players: [
        for (final id in ['a', 'b', 'c', 'd'])
          Player(id: id, name: id, rating: 1500),
      ],
      sections: [
        Section(
          id: 's',
          name: 'Prelim 1',
          players: const ['a', 'b', 'c', 'd'],
          format: Format.roundRobin,
          plannedRounds: 3,
          holland: const {
            'group': 'g',
            'role': 'prelim',
            'qualifiers': 1,
            'unbalanced': true,
          },
          rounds: [
            Round(
              number: 1,
              games: [
                _g('1', 'a', 'b', Outcome.whiteWin),
                _g('2', 'c', 'd', Outcome.whiteForfeit),
              ],
            ),
            Round(
              number: 2,
              games: [
                _g('3', 'a', 'c', Outcome.whiteWin),
                _g('4', 'b', 'd', Outcome.whiteWin),
              ],
            ),
            Round(
              number: 3,
              games: [
                _g('5', 'a', 'd', Outcome.whiteWin),
                _g('6', 'b', 'c', Outcome.draw),
              ],
            ),
          ],
        ),
      ],
    );
    expect(hollandQualifiersOf(e, e.sections.single, 0).map((p) => p.id), [
      'a',
    ]);
  });

  test("34E10: opponents' performances are averaged, then rounded once", () {
    // X's opponents: O1 performed (1500+400 + 1101−400)/2 = 1300½ and O2
    // (1500 + 1100)/2 = 1300, so X's average is 1300¼.
    final e = Event(
      id: 'e',
      name: 'Performance',
      date: '2026-10-10',
      players: [
        Player(id: 'x', name: 'X', rating: 1500),
        Player(id: 'o1', name: 'O1', rating: 1400),
        Player(id: 'o2', name: 'O2', rating: 1600),
        Player(id: 'p', name: 'P', rating: 1101),
        Player(id: 'q', name: 'Q', rating: 1100),
      ],
      sections: [
        Section(
          id: 's',
          name: 'Open',
          players: const ['x', 'o1', 'o2', 'p', 'q'],
          plannedRounds: 2,
          rounds: [
            Round(
              number: 1,
              games: [
                _g('1', 'o1', 'x', Outcome.whiteWin),
                _g('2', 'o2', 'q', Outcome.draw),
              ],
            ),
            Round(
              number: 2,
              games: [
                _g('3', 'x', 'o2', Outcome.draw),
                _g('4', 'p', 'o1', Outcome.whiteWin),
              ],
            ),
          ],
        ),
      ],
    );
    final row = standings(
      e,
      e.sections.single,
      tiebreaks: const [TiebreakMethod.opponentsPerformance],
    ).firstWhere((r) => r.player.id == 'x');
    expect(row.tiebreaks.single.value, 1300);
  });
}
