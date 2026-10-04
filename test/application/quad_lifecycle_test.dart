import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';

import '../support.dart';

void main() {
  test(
    'completed R3 cannot release earlier unresolved players or boards',
    () async {
      final c = fixture(count: 8);
      addTearDown(c.dispose);
      final first = c.pairingEvent.sections.first;
      final second = c.event!.sections.last;
      for (final game in first.rounds.last.games) {
        c.recordResult(game.id, Outcome.draw);
      }
      final stored = c.event!.sections.first;
      expect(stored.rounds.last.complete, isTrue);
      expect(stored.unresolvedRounds.map((r) => r.number), [1, 2]);

      final before = c.event!.encode();
      expect(
        () => c.addSideGame(first.players.first, second.players.first),
        throwsA(isA<TournamentException>()),
      );
      expect(c.event!.encode(), before);

      c.change(
        'Use a conflicting board range',
        c.event!.copy(sections: [stored, second.copy(boardStart: 1)]),
      );
      final proposal = await c.propose(sectionId: second.id);
      expect(
        () => validateEvent(
          c.event!.copy(
            sections: [
              stored,
              c.event!.sections.last.copy(
                rounds: [proposal.rounds[second.id]!],
              ),
            ],
          ),
        ),
        throwsA(isA<TournamentException>()),
      );
      expect(() => c.post(proposal), throwsA(isA<TournamentException>()));
      expect(c.event!.sections.last.rounds, isEmpty);

      // Side games can use a section whose preferred first board is occupied;
      // their allocator must skip boards held by any unfinished round.
      c.change(
        'Use the second section for side games',
        c.event!.copy(
          sections: [stored, second.copy(sideGames: true, boardStart: 1)],
        ),
      );
      c.addSideGame(second.players[0], second.players[1], sectionId: second.id);
      expect(c.event!.sections.last.rounds.single.games.single.board, 3);
    },
  );

  test(
    'starting after an inline R1 result starts R1, not a projected round',
    () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final projected = c.pairingEvent.sections.single;
      c.recordResult(projected.rounds.first.games.first.id, Outcome.draw);

      c.startRound(projected.id);

      final saved = c.event!.sections.single;
      expect(saved.rounds, hasLength(1));
      expect(saved.rounds.single.number, 1);
      expect(saved.rounds.single.startedAt, isNotNull);
      final displayed = c.pairingEvent.sections.single;
      expect(displayed.rounds, hasLength(3));
      expect(
        displayed.rounds.skip(1).every((r) => r.startedAt == null),
        isTrue,
      );
    },
  );

  test('a finished inline quad game frees its players for a side game', () {
    final c = fixture(count: 8);
    addTearDown(c.dispose);
    final sections = c.pairingEvent.sections;
    final a = sections.first.rounds.first.games.first;
    final b = sections.last.rounds.first.games.first;
    c.recordResult(a.id, Outcome.whiteForfeit);
    c.recordResult(b.id, Outcome.draw);
    final side = c.addSideGame(a.white, b.white);
    expect(
      c.event!.sections
          .firstWhere((s) => s.id == side)
          .rounds
          .single
          .games
          .length,
      1,
    );
  });

  test('a projected correction preserves unrelated sections', () {
    final c = fixture(count: 8);
    addTearDown(c.dispose);
    final untouched = c.event!.sections.last.toJson();
    final game = c.pairingEvent.sections.first.rounds.first.games.first;
    c.correctResult(
      c.reviewResult(game.id),
      Outcome.draw,
      reason: 'Signed slip',
    );
    expect(c.event!.sections.last.toJson(), untouched);
    expect(
      c.event!.games.singleWhere((g) => g.id == game.id).outcome,
      Outcome.draw,
    );
  });

  test(
    'projected quad mutations respect byes, withdrawals and opponent requests',
    () {
      for (final restriction in ['bye', 'withdrawal', 'opponent']) {
        final c = fixture(count: 4);
        try {
          final game = c.pairingEvent.games.first;
          switch (restriction) {
            case 'bye':
              c.reserveBye(game.white, 1, 1);
            case 'withdrawal':
              c.savePlayer(c.event!.player(game.white).copy(withdrawn: true));
            case 'opponent':
              c.avoidPair(game.white, game.black, true);
          }
          final before = c.event!.encode();
          expect(c.quadScheduleIssues, isNotEmpty);
          expect(
            () => c.recordResult(game.id, Outcome.whiteWin),
            throwsA(isA<TournamentException>()),
          );
          expect(
            () => c.setPairingAssumption(
              game.id,
              Outcome.draw,
              'Pending decision',
            ),
            throwsA(isA<TournamentException>()),
          );
          expect(c.event!.encode(), before);
        } finally {
          c.dispose();
        }
      }
    },
  );
}
