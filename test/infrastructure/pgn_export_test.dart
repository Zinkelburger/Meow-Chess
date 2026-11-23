import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/pgn_export.dart';

Event event({String timeControl = 'G/90;+30', bool doubleGames = false}) =>
    Event(
      id: 'e',
      name: 'Fall "Classic" Open',
      date: '2026-11-21',
      venue: 'Boylston Chess Club',
      city: 'Cambridge',
      state: 'MA',
      timeControl: timeControl,
      players: [
        Player(
          id: 'a',
          name: 'Smith, Ann',
          rating: 2105,
          title: 'FM',
          fideId: '2000001',
        ),
        Player(id: 'b', name: 'Jones, Bob', rating: 1880),
        Player(id: 'c', name: 'Unrated, Cal'),
        Player(id: 'd', name: 'Dee'),
        Player(id: 'x', name: 'Ladder One'),
        Player(id: 'y', name: 'Ladder Two'),
      ],
      sections: [
        Section(
          id: 's',
          name: 'Open',
          players: const ['a', 'b', 'c', 'd'],
          doubleGames: doubleGames,
          rounds: [
            Round(
              number: 1,
              games: const [
                Game(
                  id: 'g2',
                  white: 'c',
                  black: 'd',
                  board: 2,
                  outcome: Outcome.whiteForfeit,
                ),
                Game(
                  id: 'g1',
                  white: 'a',
                  black: 'b',
                  board: 1,
                  outcome: Outcome.draw,
                ),
              ],
            ),
            Round(
              number: 2,
              games: const [
                Game(id: 'g3', white: 'd', black: 'a', board: 1),
                Game(
                  id: 'g4',
                  white: 'b',
                  black: 'c',
                  board: 2,
                  outcome: Outcome.blackWin,
                ),
              ],
            ),
          ],
        ),
        Section(
          id: 'l',
          name: 'Ladder',
          format: Format.ladder,
          players: const ['x', 'y'],
          boardStart: 30,
          unrated: true,
          rounds: [
            Round(
              number: 1,
              games: const [
                Game(
                  id: 'l1',
                  white: 'x',
                  black: 'y',
                  board: 30,
                  outcome: Outcome.whiteWin,
                ),
              ],
            ),
          ],
        ),
      ],
    );

void main() {
  test('one headed game per board, in round and board order', () {
    final pgn = pgnHeaders(event());
    final games = pgn.split('\n\n[Event ');
    // Round 1 board 1, then round 2 boards 1 and 2. The forfeit was never
    // played and the ladder has no rounds to record.
    expect(games, hasLength(3));
    expect(pgn.split('\n').takeWhile((line) => line.isNotEmpty).toList(), [
      r'[Event "Fall \"Classic\" Open"]',
      '[Site "Boylston Chess Club, Cambridge, MA"]',
      '[Date "2026.11.21"]',
      '[Round "1"]',
      '[White "Smith, Ann"]',
      '[Black "Jones, Bob"]',
      '[Result "1/2-1/2"]',
      '[Section "Open"]',
      '[Board "1"]',
      '[WhiteElo "2105"]',
      '[BlackElo "1880"]',
      '[WhiteTitle "FM"]',
      '[WhiteFideId "2000001"]',
      '[TimeControl "5400+30"]',
    ]);
    // The movetext of a game with no moves is its result.
    expect(pgn, contains('[TimeControl "5400+30"]\n\n1/2-1/2\n'));
    // A game still to be played is in the file, without a result or a
    // rating for the unrated player.
    expect(games[1], contains('[White "Dee"]'));
    expect(games[1], contains('[Result "*"]'));
    expect(games[1], isNot(contains('WhiteElo')));
    expect(games[1], contains('[BlackElo "2105"]'));
    expect(games[2], contains('[Result "0-1"]'));
    expect(pgn, isNot(contains('Ladder')));
    expect(pgn.endsWith('\n'), isTrue);
  });

  test('a chosen round, and time controls in PGN\'s own notation', () {
    final one = pgnHeaders(
      event(timeControl: '40/90, SD/30 d5'),
      rounds: {'s': 2},
    );
    expect('[Round '.allMatches(one), hasLength(2));
    expect(one, isNot(contains('[Round "1"]')));
    // PGN has no word for a delay.
    expect(one, contains('[TimeControl "40/5400:1800"]'));
    expect(
      pgnHeaders(event(timeControl: 'G/60')),
      contains('[TimeControl "3600"]'),
    );
    expect(
      pgnHeaders(event(timeControl: 'one hour each')),
      isNot(contains('TimeControl')),
    );
  });

  test('nothing to write is refused in words', () {
    expect(
      () => pgnHeaders(event(), sections: ['l']),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('no games to write'),
        ),
      ),
    );
    expect(
      () => pgnHeaders(event(), rounds: {'s': 3}),
      throwsA(isA<TournamentException>()),
    );
  });
}
