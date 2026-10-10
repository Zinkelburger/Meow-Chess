import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/ladder.dart';
import 'package:meow_chess/domain/model.dart';

void main() {
  const names = {
    'a': 'Alex Chen',
    'b': 'Bo Li',
    'c': 'Cy Dee',
    'd': 'Di Fox',
    'e': 'Ed Gray',
  };
  String name(String id) => names[id]!;
  Section ladder([List<String> order = const ['a', 'b', 'c', 'd', 'e']]) =>
      Section(
        id: 's',
        name: 'Club Ladder',
        players: order,
        format: Format.ladder,
        plannedRounds: ladderDefaultBatches,
      );
  Game game(
    String challenger,
    String defender,
    ChallengeResult result, {
    bool challengerWhite = false,
  }) => ladderGame(
    id: 'g',
    challenger: challenger,
    defender: defender,
    board: 1,
    outcome: result.outcome(challengerWhite: challengerWhite),
    challengerWhite: challengerWhite,
  );

  test('positions are the order of the section players, 1 = top', () {
    final s = ladder();
    expect(ladderPositions(s), ['a', 'b', 'c', 'd', 'e']);
    expect(ladderPosition(s, 'a'), 1);
    expect(ladderPosition(s, 'e'), 5);
    expect(ladderPosition(s, 'zz'), isNull);
  });

  test('a challenge reaches up to two places above, never downward', () {
    final s = ladder();
    expect(ladderChallengeAllowed(s, 'e', 'd'), isNull);
    expect(ladderChallengeAllowed(s, 'e', 'c'), isNull);
    expect(
      ladderChallengeAllowed(s, 'e', 'b', name: name),
      'Bo Li is 3 places above Ed Gray; a challenge reaches at most 2 places up.',
    );
    expect(
      ladderChallengeAllowed(s, 'b', 'c', name: name),
      contains('Cy Dee is below Bo Li'),
    );
    expect(
      ladderChallengeAllowed(s, 'a', 'a'),
      'Choose two different players.',
    );
    expect(ladderChallengeAllowed(s, 'a', 'b'), contains('below'));
    expect(ladderChallengeAllowed(s, 'zz', 'a'), 'zz is not on this ladder.');
    expect(ladderDefenders(s, 'e'), ['d', 'c']);
    expect(ladderDefenders(s, 'b'), ['a']);
    expect(ladderDefenders(s, 'a'), isEmpty);
  });

  test('the challenger has Black unless asked for White', () {
    final black = game('e', 'c', ChallengeResult.win);
    expect((black.white, black.black), ('c', 'e'));
    expect(black.outcome, Outcome.blackWin);
    final white = game('e', 'c', ChallengeResult.win, challengerWhite: true);
    expect((white.white, white.black), ('e', 'c'));
    expect(white.outcome, Outcome.whiteWin);
    expect(ladderChallenger(ladder(), black), 'e');
    expect(ladderChallenger(ladder(), white), 'e');
  });

  test('a win takes the place and everyone between moves down one', () {
    final s = ladder();
    expect(ladderAfterResult(s, game('e', 'c', ChallengeResult.win)), [
      'a',
      'b',
      'e',
      'c',
      'd',
    ]);
    expect(
      ladderAfterResult(
        s,
        game('d', 'c', ChallengeResult.win, challengerWhite: true),
      ),
      ['a', 'b', 'd', 'c', 'e'],
    );
    expect(ladderAfterResult(s, game('b', 'a', ChallengeResult.forfeitWin)), [
      'b',
      'a',
      'c',
      'd',
      'e',
    ]);
  });

  test('a draw, a loss or a double forfeit changes nothing', () {
    final s = ladder();
    for (final result in [
      ChallengeResult.draw,
      ChallengeResult.loss,
      ChallengeResult.forfeitLoss,
      ChallengeResult.doubleForfeit,
    ]) {
      expect(ladderAfterResult(s, game('e', 'c', result)), s.players);
      expect(ladderChallengerWon(s, game('e', 'c', result)), isFalse);
    }
    expect(
      ladderAfterResult(
        s,
        ladderGame(id: 'g', challenger: 'e', defender: 'c', board: 1),
      ),
      s.players,
      reason: 'an unreported game moves nobody',
    );
  });

  test('history names every move', () {
    expect(
      ladderMoves(['a', 'b', 'c', 'd', 'e'], ['a', 'b', 'e', 'c', 'd'], name),
      'Ed Gray up to #3, Cy Dee down to #4, Di Fox down to #5',
    );
    expect(
      ladderMoves(['a', 'b'], ['a', 'b'], name),
      'no change on the ladder',
    );
  });

  test('games played and last result read from the batches', () {
    final s = ladder().copy(
      rounds: [
        Round(
          number: 1,
          games: [
            game('e', 'c', ChallengeResult.win).copy(id: 'g1'),
            game('b', 'a', ChallengeResult.draw).copy(id: 'g2'),
          ],
        ),
        Round(
          number: 2,
          games: [game('d', 'e', ChallengeResult.forfeitLoss).copy(id: 'g3')],
        ),
      ],
    );
    expect(ladderGames(s, 'e').length, 2);
    expect(ladderGames(s, 'a').length, 1);
    expect(ladderGames(s, 'd').length, 1);
    expect(ladderLastResult(s, 'e', name), '1–0 (forfeit) v. Di Fox');
    expect(ladderLastResult(s, 'd', name), '0–1 (forfeit) v. Ed Gray');
    expect(ladderLastResult(s, 'c', name), '0–1 v. Ed Gray');
    expect(ladderLastResult(s, 'a', name), '½–½ v. Bo Li');
    expect(ladderLastResult(s, 'zz', name), '');
  });

  test('a reordering must list every player exactly once', () {
    final s = ladder();
    expect(ladderOrderProblem(s, ['e', 'd', 'c', 'b', 'a']), isNull);
    expect(ladderOrderProblem(s, ['a', 'a', 'c', 'd', 'e']), contains('twice'));
    expect(
      ladderOrderProblem(s, ['a', 'b', 'c', 'd']),
      contains('exactly once'),
    );
    expect(
      ladderOrderProblem(s, ['a', 'b', 'c', 'd', 'zz']),
      contains('exactly once'),
    );
  });

  test('tool results parse by name and refuse the rest', () {
    expect(ChallengeResult.parse('win'), ChallengeResult.win);
    expect(
      () => ChallengeResult.parse('victory'),
      throwsA(isA<TournamentException>()),
    );
    expect(ladderScoreLabel(Outcome.blackWin, fromWhite: false), '1–0');
    expect(
      ladderScoreLabel(Outcome.whiteForfeit, fromWhite: false),
      '0–1 (forfeit)',
    );
  });
}
