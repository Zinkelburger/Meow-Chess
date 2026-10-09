import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/history.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import '../support.dart';

Matcher refuses(String text) => throwsA(
  isA<TournamentException>().having(
    (e) => e.message,
    'message',
    contains(text),
  ),
);

void main() {
  test('21H–21L: rulings log newest first, undo and remove', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final s = c.event!.sections.single;
    final first = c.logRuling(
      kind: 'penalty',
      text: 'Phone rang during play; warning given.',
      round: 1,
      section: s.id,
      players: ['p1'],
      decidedBy: '12345678',
      outcome: 'Warning (20K)',
    );
    final second = c.logRuling(kind: 'appeal', text: 'Appeal denied.');
    expect(c.event!.rulings.map((r) => r['id']), [first, second]);
    expect(c.event!.rulings.first['players'], ['p1']);
    expect(c.event!.rulings.first['outcome'], 'Warning (20K)');
    expect(c.undoLabel, contains('appeal'));
    c.undo();
    expect(c.event!.rulings, hasLength(1));
    c.removeRuling(first);
    expect(c.event!.rulings, isEmpty);
    expect(() => c.logRuling(kind: 'nonsense', text: 'x'), refuses('kind'));
    expect(() => c.logRuling(kind: 'ruling', text: '  '), refuses('Describe'));
    expect(
      () => c.logRuling(kind: 'ruling', text: 'x', players: ['nobody']),
      throwsA(isA<TournamentException>()),
    );
  });

  test('28E1/28E2: assigned ratings have a floor and need a cause', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final p = c.event!.player('p1'); // rated 1950
    expect(
      () => c.savePlayer(p.copy(pairingRating: 1900, ratingNote: 'x')),
      refuses('rule 28E1'),
    );
    expect(
      () => c.savePlayer(p.copy(prizeRating: 1900, ratingNote: 'x')),
      refuses('rule 28E1'),
    );
    expect(
      () => c.savePlayer(p.copy(pairingRating: 2100)),
      refuses('rule 28E2'),
    );
    final before = c.event!;
    c.savePlayer(
      p.copy(pairingRating: 2100, ratingNote: '28E2a: dominates the class'),
    );
    expect(c.event!.player('p1').effectivePairingRating, 2100);
    expect(c.event!.player('p1').effectivePrizeRating, 1950);
    expect(
      describeChanges(before, c.event!).join('\n'),
      contains('pairing rating published → 2100'),
    );
  });

  test(
    '28E1: an unrated player with a foreign rating keeps its converted floor',
    () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.importPlayers([
        Player(
          id: 'f',
          name: 'Foreign Guest',
          foreignRating: 2400,
          foreignFederation: 'FIDE',
        ),
      ]);
      final f = c.event!.player('f');
      expect(
        () => c.savePlayer(f.copy(pairingRating: 2400)),
        refuses('converted foreign rating 2468'),
      );
      c.savePlayer(f.copy(pairingRating: 2468));
      expect(c.event!.player('f').unrated, isFalse);
    },
  );

  test(
    '28D2/28D5: an unverified under-2200 assignment needs a cause when a class prize is at stake',
    () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final s = c.event!.sections.single;
      c.change(
        'Announce a class prize',
        c.event!.copy(
          sections: [
            s.copy(
              prizes: {
                'list': [
                  {
                    'label': 'U1800',
                    'kind': 'under',
                    'max': 1800,
                    'cents': 5000,
                  },
                ],
              },
            ),
          ],
        ),
      );
      c.importPlayers([Player(id: 'u', name: 'Unknown Strength')]);
      c.movePlayers(['u'], s.id);
      final u = c.event!.player('u');
      expect(() => c.savePlayer(u.copy(prizeRating: 1500)), refuses('28D2'));
      // 2200 or above, or a documented cause, is fine.
      c.savePlayer(u.copy(prizeRating: 2200));
      c.savePlayer(
        u.copy(prizeRating: 1500, ratingNote: 'Verified CFC 1500 (28D1a)'),
      );
      expect(c.event!.player('u').effectivePrizeRating, 1500);
    },
  );

  test('28H: a revised rating above the section ceiling attaches advice', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final s = c.event!.sections.single;
    c.change(
      'Under 1900',
      c.event!.copy(sections: [s.copy(ratingCeiling: 1900)]),
    );
    final p = c.event!.player('p3'); // 1850
    c.savePlayer(p.copy(name: 'Same rating'));
    expect(c.playerNotice, isNull);
    c.savePlayer(p.copy(rating: 1950));
    expect(c.playerNotice, contains('rule 28H'));
    expect(c.playerNotice, contains('half-point byes'));
    expect(c.event!.player('p3').rating, 1950);
    c.savePlayer(c.event!.player('p3').copy(notes: 'moved'));
    expect(c.playerNotice, isNull);
  });

  test('36: the computer flag saves and shows in history', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final before = c.event!;
    c.savePlayer(c.event!.player('p0').copy(computer: true));
    expect(c.event!.player('p0').computer, isTrue);
    expect(
      describeChanges(before, c.event!).join('\n'),
      contains('computer entrant'),
    );
  });

  test(
    '18G: an adjudicated correction is marked ADJ on the crosstable',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post(await c.propose());
      final s = c.event!.sections.single;
      final game = s.rounds.single.games.first;
      c.correctResult(
        c.reviewResult(game.id),
        Outcome.whiteWin,
        reason: 'Player left the board for 20 minutes in a lost position.',
        adjudicated: true,
      );
      final saved = c.event!.games.firstWhere((g) => g.id == game.id);
      expect(saved.adjudicated, isTrue);
      final round = c.event!.sections.single.rounds.single;
      final numbers = {for (final (i, id) in s.players.indexed) id: i + 1};
      expect(
        crosstableCell(c.event!, round, game.white, numbers),
        endsWith(' ADJ'),
      );
      // Unmarking keeps the result.
      c.correctResult(
        c.reviewResult(game.id),
        Outcome.blackWin,
        adjudicated: false,
      );
      expect(
        c.event!.games.firstWhere((g) => g.id == game.id).adjudicated,
        isFalse,
      );
    },
  );
}
