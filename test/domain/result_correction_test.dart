import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/result_correction.dart';

/// A round of one game, [white] against [black], decided unless [open].
Round round(
  String section,
  int n,
  String white,
  String black, {
  bool open = false,
}) => Round(
  number: n,
  games: [
    Game(
      id: '$section$n',
      white: white,
      black: black,
      board: 1,
      outcome: open ? Outcome.unreported : Outcome.whiteWin,
    ),
  ],
);

/// Section A plays [aRounds] decided rounds and then an unplayed one; B
/// plays [bRounds]. With [transfer], a1 then moves from A to B, whose next
/// round is paired with a1 and left unplayed, and A's next round is only
/// a2's zero-point bye.
Event twoSections({
  required int aRounds,
  required int bRounds,
  bool transfer = true,
}) {
  final players = [
    for (final id in ['a1', 'a2', 'b1', 'b2']) Player(id: id, name: id),
  ];
  return Event(
    id: 'e',
    name: 'Transfers',
    date: '2026-10-09',
    players: players,
    sections: [
      Section(
        id: 'A',
        name: 'A',
        players: transfer ? const ['a2'] : const ['a1', 'a2'],
        rounds: [
          for (var n = 1; n <= aRounds; n++) round('A', n, 'a1', 'a2'),
          if (transfer)
            Round(
              number: aRounds + 1,
              games: const [],
              byes: const [ByeAward('a2', 0, 'Unpaired')],
            )
          else
            round('A', aRounds + 1, 'a1', 'a2', open: true),
        ],
      ),
      Section(
        id: 'B',
        name: 'B',
        players: transfer ? const ['b1', 'b2', 'a1'] : const ['b1', 'b2'],
        rounds: [
          for (var n = 1; n <= bRounds; n++) round('B', n, 'b1', 'b2'),
          if (transfer) round('B', bRounds + 1, 'a1', 'b1', open: true),
        ],
      ),
    ],
    transitions: [
      if (transfer)
        {
          'players': ['a1'],
          'target': 'B',
          'effectiveRound': bRounds + 1,
          'reason': 'Combine sections',
          'revision': 1,
        },
    ],
  );
}

void main() {
  test('a transfer after the game links the target round and refuses '
      'reopening', () {
    final e = twoSections(aRounds: 1, bRounds: 1);
    final review = ResultCorrection(e, 'A1');
    expect(review.hasTransfers, true);
    expect(review.hasDependencies, true);
    expect(review.connectedSections, {'A', 'B'});
    expect(
      [for (final (s, r) in review.relatedRounds) '${s.id}${r.number}'],
      ['B2'],
    );
    // A's round 2 is unplayed, but the related round B2 would not be
    // removed with it, so reopening must be refused.
    expect(review.later.single.hasPlay, false);
    expect(review.canReopenFrom(2), false);
    expect(
      () => review.apply(Outcome.draw, reopenFrom: 2, confirmedUnstarted: true),
      throwsA(isA<TournamentException>()),
    );
    final corrected = review.apply(Outcome.draw);
    expect(corrected.sections.last.toJson(), e.sections.last.toJson());
    expect(
      corrected.sections.first.rounds.first.games.single.outcome,
      Outcome.draw,
    );
    expect(corrected.sections.first.rounds.length, 2);
  });

  test('a transfer into a section that has played fewer rounds still '
      'depends on the later rounds it left', () {
    // A has played three rounds and B one when a1 moves: the transfer is
    // effective in B's round 2, yet it carried A's round 3 result.
    final e = twoSections(aRounds: 3, bRounds: 1);
    for (final game in ['A1', 'A2', 'A3']) {
      final review = ResultCorrection(e, game);
      expect(review.hasTransfers, true, reason: game);
      expect(
        [for (final (s, r) in review.relatedRounds) '${s.id}${r.number}'],
        ['B2'],
        reason: game,
      );
    }
    // B's own game in round 1 was before the transfer arrived.
    final own = ResultCorrection(e, 'B1');
    expect(own.hasTransfers, true);
    expect(own.relatedRounds, isEmpty);
    expect(own.canReopenFrom(2), false);
  });

  test('without transfers a later unplayed round reopens and nothing else '
      'is related', () {
    final e = twoSections(aRounds: 2, bRounds: 2, transfer: false);
    final review = ResultCorrection(e, 'A1');
    expect(review.hasTransfers, false);
    expect(review.relatedRounds, isEmpty);
    expect(review.canReopenFrom(3), true);
    expect(review.canReopenFrom(2), false, reason: 'round 2 has play');
    final reopened = review.apply(
      Outcome.draw,
      reopenFrom: 3,
      confirmedUnstarted: true,
    );
    expect([for (final r in reopened.sections.first.rounds) r.number], [1, 2]);
    expect(reopened.sections.last.toJson(), e.sections.last.toJson());
  });

  test('related rounds exist only when reopening is refused', () {
    for (final (a, b) in [(1, 1), (2, 1), (3, 1), (1, 3), (2, 2)]) {
      for (final transfer in [true, false]) {
        final e = twoSections(aRounds: a, bRounds: b, transfer: transfer);
        for (final game in e.games) {
          final review = ResultCorrection(e, game.id);
          if (review.relatedRounds.isEmpty) continue;
          expect(review.hasTransfers, true);
          for (var n = 1; n <= 5; n++) {
            expect(review.canReopenFrom(n), false);
          }
        }
      }
    }
  });
}
