import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/upsets.dart';

Game game(String id, String white, String black, Outcome outcome, int board) =>
    Game(id: id, white: white, black: black, board: board, outcome: outcome);

void main() {
  final players = [
    Player(id: 'a', name: 'Ann', rating: 2000),
    Player(id: 'b', name: 'Bob', rating: 1700),
    Player(id: 'c', name: 'Cal', rating: 1400),
    Player(id: 'd', name: 'Dee'),
    // Paired on an assigned rating, not the published one.
    Player(id: 'e', name: 'Eve', rating: 1200, pairingRating: 1900),
    Player(id: 'f', name: 'Fay', rating: 1600),
  ];
  Event event(List<Round> rounds) => Event(
    id: 'e',
    name: 'Open',
    date: '2026-11-21',
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'Open',
        players: [for (final p in players) p.id],
        plannedRounds: 4,
        rounds: rounds,
      ),
    ],
  );

  test('only played wins by the lower-rated of two rated players count', () {
    final e = event([
      Round(
        number: 1,
        games: [
          // The favorite wins: no upset.
          game('1', 'a', 'c', Outcome.whiteWin, 1),
          // An unrated player has no rating to upset.
          game('2', 'd', 'b', Outcome.whiteWin, 2),
          // A draw is not a win.
          game('3', 'f', 'e', Outcome.draw, 3),
        ],
      ),
      Round(
        number: 2,
        games: [
          // 300 points, with Black.
          game('4', 'a', 'b', Outcome.blackWin, 1),
          // 300 points by the rating Eve was paired on.
          game('6', 'f', 'e', Outcome.whiteWin, 2),
        ],
      ),
      Round(
        number: 3,
        games: [
          game('7', 'c', 'b', Outcome.whiteWin, 1),
          // A forfeit win over a higher-rated player is not a game.
          game('8', 'e', 'a', Outcome.whiteForfeit, 2),
        ],
      ),
    ]);
    final upsets = sectionUpsets(e, e.sections.single);
    expect(upsets.map((u) => (u.winner.id, u.loser.id, u.gap, u.round)), [
      ('b', 'a', 300, 2),
      ('f', 'e', 300, 2),
      ('c', 'b', 300, 3),
    ]);
    expect(
      upsets.first.text,
      'Bob (1700) beat Ann (2000) in round 2, 300 points',
    );
    // The biggest, with everything tied for it.
    expect(biggestUpsets(e, e.sections.single), hasLength(3));
  });

  test('a section without an upset has none', () {
    expect(
      biggestUpsets(event(const []), event(const []).sections.single),
      isEmpty,
    );
    final e = event([
      Round(number: 1, games: [game('1', 'a', 'b', Outcome.whiteWin, 1)]),
    ]);
    expect(biggestUpsets(e, e.sections.single), isEmpty);
  });
}
