import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/bye_policy.dart';
import 'package:meow_chess/domain/model.dart';

void main() {
  // Player a declared an irrevocable half-point bye for round 2 and then
  // cancelled it (22C5): the declaration stays, the reserved bye is gone.
  final event = Event(
    id: 'e',
    name: 'Club',
    date: '2026-10-09',
    players: [
      Player(id: 'a', name: 'A', irrevocableByes: {2}),
      Player(id: 'b', name: 'B'),
    ],
  );
  Game game(Outcome outcome) =>
      Game(id: 'g', white: 'a', black: 'b', board: 1, outcome: outcome);

  test('22C5: a win over the board counts as a draw for prizes', () {
    final ruled = applyIrrevocableByeRule(event, game(Outcome.whiteWin), 2);
    expect(ruled.outcome, Outcome.whiteWin);
    expect(ruled.prizeOutcome, Outcome.draw);
    expect(ruled.note, contains(irrevocableByeNote));
    // Another round, or a loss, is untouched.
    expect(
      applyIrrevocableByeRule(event, game(Outcome.whiteWin), 3).prizeOutcome,
      isNull,
    );
    expect(
      applyIrrevocableByeRule(event, game(Outcome.blackWin), 2).prizeOutcome,
      isNull,
    );
  });

  test('22C5: a corrected result lifts the reduction again', () {
    final ruled = applyIrrevocableByeRule(event, game(Outcome.whiteWin), 2);
    final corrected = applyIrrevocableByeRule(
      event,
      ruled.copy(outcome: Outcome.draw),
      2,
    );
    expect(corrected.prizeOutcome, isNull);
    expect(corrected.note, isNot(contains(irrevocableByeNote)));
  });

  test('22C5: a forfeit win is left for the director (no prize outcome '
      'can score it ½–0 unplayed)', () {
    final ruled = applyIrrevocableByeRule(event, game(Outcome.whiteForfeit), 2);
    expect(ruled.prizeOutcome, isNull);
    expect(ruled.note, isEmpty);
  });
}
