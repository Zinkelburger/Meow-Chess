import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/results_view_model.dart';

Player player(String id, {bool withdrawn = false}) =>
    Player(id: id, name: 'Name ${id.toUpperCase()}', withdrawn: withdrawn);

Game game(
  String id,
  String white,
  String black,
  int board, {
  Outcome outcome = Outcome.unreported,
  int leg = 1,
  Outcome? assume,
}) => Game(
  id: id,
  white: white,
  black: black,
  board: board,
  leg: leg,
  outcome: outcome,
  pairingAssumption: assume,
);

Event event(List<Section> sections, {Set<String> withdrawn = const {}}) =>
    Event(
      id: 'e',
      name: 'Club',
      date: '2026-11-11',
      players: [
        for (final id in {for (final s in sections) ...s.players})
          player(id, withdrawn: withdrawn.contains(id)),
      ],
      sections: sections,
    );

/// A Swiss of eight players: round 1 complete (a, c, e, g won), round 2
/// paired with boards 1 and 3 decided.
Section swiss({String id = 'open', String name = 'Open'}) => Section(
  id: id,
  name: name,
  players: [for (final p in 'abcdefgh'.split('')) '$id-$p'],
  plannedRounds: 4,
  rounds: [
    Round(
      number: 1,
      games: [
        game('$id-1-1', '$id-a', '$id-b', 1, outcome: Outcome.whiteWin),
        game('$id-1-2', '$id-c', '$id-d', 2, outcome: Outcome.whiteWin),
        game('$id-1-3', '$id-e', '$id-f', 3, outcome: Outcome.whiteWin),
        game('$id-1-4', '$id-g', '$id-h', 4, outcome: Outcome.whiteWin),
      ],
    ),
    Round(
      number: 2,
      games: [
        game('$id-2-1', '$id-a', '$id-c', 1, outcome: Outcome.draw),
        game('$id-2-2', '$id-e', '$id-g', 2),
        game('$id-2-3', '$id-b', '$id-d', 3, outcome: Outcome.blackWin),
        game('$id-2-4', '$id-f', '$id-h', 4),
      ],
    ),
  ],
);

/// A quad whose fixed schedule shows every round at once.
Section quad() => Section(
  id: 'q',
  name: 'Quad',
  format: Format.quad,
  players: const ['q-a', 'q-b', 'q-c', 'q-d'],
  rounds: [
    for (var r = 1; r <= 3; r++)
      Round(
        number: r,
        games: [
          game('q-$r-1', 'q-a', 'q-b', 1),
          game('q-$r-2', 'q-c', 'q-d', 2),
        ],
      ),
  ],
);

List<String> ids(Iterable<BoardRow> rows) => [for (final r in rows) r.game.id];

void main() {
  group('round selection', () {
    test('shows the current round, or the round picked', () {
      final s = swiss(), selection = RoundSelection();
      expect(selection.shownRound(s)!.number, 2);
      selection.pick(1, 2);
      expect(selection.selectedRound, 1);
      expect(selection.shownRound(s)!.number, 1);
      // Picking the latest round goes back to following the current one.
      selection.pick(2, 2);
      expect(selection.selectedRound, isNull);
      selection.selectedRound = 9;
      expect(selection.shownRound(s), isNull);
      expect(selection.shownRounds(s), isEmpty);
    });

    test(
      'a fixed quad schedule shows every round; a Swiss beside it does not',
      () {
        final selection = RoundSelection();
        expect(selection.allRoundsOf(quad()), isTrue);
        expect(selection.shownRounds(quad()).map((r) => r.number), [1, 2, 3]);
        expect(selection.allRoundsOf(swiss()), isFalse);
        // Picking a round leaves the schedule view.
        selection.pick(1, 3);
        expect(selection.allRoundsOf(quad()), isFalse);
        selection.showAll();
        expect(selection.allRoundsOf(swiss()), isTrue);
        expect(selection.selectedRound, isNull);
      },
    );

    test('an earlier Swiss round is locked until correcting', () {
      final s = swiss();
      final selection = RoundSelection();
      final earlier = BoardRow(s, s.rounds.first, s.rounds.first.games.first);
      final current = BoardRow(s, s.rounds.last, s.rounds.last.games.first);
      expect(isEarlierRound(s, s.rounds.first), isTrue);
      expect(selection.locked(earlier), isTrue);
      expect(selection.locked(current), isFalse);
      selection.startCorrecting();
      expect(selection.locked(earlier), isFalse);
      selection.nudged = true;
      selection.stopCorrecting();
      expect(selection.correcting, isFalse);
      expect(selection.nudged, isFalse);
      expect(selection.locked(earlier), isTrue);
      // A quad's earlier rounds are never locked.
      final q = quad();
      expect(isEarlierRound(q, q.rounds.first), isFalse);
    });

    test('a new round resets the view, and a vanished round is forgotten', () {
      final selection = RoundSelection()
        ..selectedRound = 1
        ..scheduleRounds = false
        ..correcting = true
        ..nudged = true;
      selection.keepWithin([1, 2]);
      expect(selection.selectedRound, 1);
      selection.keepWithin([2]);
      expect(selection.selectedRound, isNull);
      selection
        ..selectedRound = 1
        ..reset(allQuads: true);
      expect(selection.selectedRound, isNull);
      expect(selection.showAllRounds, isTrue);
      expect(selection.scheduleRounds, isTrue);
      expect(selection.correcting || selection.nudged, isFalse);
    });
  });

  group('rows', () {
    test('are ordered by round, board and game', () {
      final s = Section(
        id: 'd',
        name: 'Double',
        doubleGames: true,
        players: const ['a', 'b', 'c', 'd'],
        rounds: [
          Round(
            number: 1,
            games: [
              game('2b', 'd', 'c', 2, leg: 2),
              game('1a', 'a', 'b', 1),
              game('2a', 'c', 'd', 2),
              game('1b', 'b', 'a', 1, leg: 2),
            ],
          ),
        ],
      );
      expect(ids(boardRows([s], RoundSelection())), ['1a', '1b', '2a', '2b']);
      final rows = boardRows([quad(), swiss()], RoundSelection()..showAll());
      expect(
        [for (final r in rows) (r.round.number, r.game.board)],
        [
          (1, 1), (1, 1), (1, 2), (1, 2), (1, 3), (1, 4), //
          (2, 1), (2, 1), (2, 2), (2, 2), (2, 3), (2, 4), //
          (3, 1), (3, 2),
        ],
      );
    });

    test('are filtered by Missing only, board number and name', () {
      final s = swiss(), e = event([s]);
      final rows = boardRows([s], RoundSelection());
      expect(ids(filterBoardRows(rows, e, query: '', missingOnly: true)), [
        'open-2-2',
        'open-2-4',
      ]);
      expect(ids(filterBoardRows(rows, e, query: ' 3 ', missingOnly: false)), [
        'open-2-3',
      ]);
      // A name match is case-blind and on either side.
      expect(
        ids(filterBoardRows(rows, e, query: 'name open-g', missingOnly: false)),
        ['open-2-2'],
      );
      expect(
        ids(filterBoardRows(rows, e, query: 'OPEN-D', missingOnly: true)),
        isEmpty,
      );
      expect(
        filterBoardRows(rows, e, query: '', missingOnly: false),
        hasLength(4),
      );
      expect(nameMatches(player('x'), '   '), isTrue);
    });
  });

  group('sheet layout', () {
    test('groups Swiss boards by score and records where each sits', () {
      final s = swiss(), e = event([s]);
      final selection = RoundSelection();
      final rows = boardRows([s], selection);
      final layout = layoutSheet(
        event: e,
        shown: [(s, s.rounds.last)],
        visible: rows,
        selection: selection,
        everySection: false,
        missingOnly: false,
        query: '',
      );
      String describe(SheetItem item) => switch (item) {
        SheetHeading(:final section, :final round) =>
          'heading ${section.id} ${round.number}',
        SheetScoreGroup(:final points) => 'group $points',
        SheetBoard(:final row) => row.game.id,
        SheetBye(:final bye) => 'bye ${bye.player}',
      };
      expect(layout.items.map(describe), [
        'group 2',
        'open-2-1',
        'open-2-2',
        'group 0',
        'open-2-3',
        'open-2-4',
      ]);
      expect(layout.itemOf, {
        'open-2-1': 1,
        'open-2-2': 2,
        'open-2-3': 4,
        'open-2-4': 5,
      });
      final board = layout.items[1] as SheetBoard;
      expect(board.before, containsPair('open-a', 2));
    });

    test('names sections when every one is shown, and lists matching byes', () {
      final s = Section(
        id: 's',
        name: 'Reserve',
        players: const ['a', 'b', 'c'],
        rounds: [
          Round(
            number: 1,
            games: [game('g', 'a', 'b', 1)],
            byes: const [ByeAward('c', 2, 'Full-point bye', allocated: true)],
          ),
        ],
      );
      final e = event([s]);
      final selection = RoundSelection();
      SheetLayout lay({String query = '', bool missingOnly = false}) =>
          layoutSheet(
            event: e,
            shown: [(s, s.rounds.single)],
            visible: filterBoardRows(
              boardRows([s], selection),
              e,
              query: query,
              missingOnly: missingOnly,
            ),
            selection: selection,
            everySection: true,
            missingOnly: missingOnly,
            query: query,
          );
      final all = lay();
      expect(all.items.first, isA<SheetHeading>());
      expect(all.items.last, isA<SheetBye>());
      expect((all.items.last as SheetBye).every, isFalse);
      expect(all.itemOf, {'g': 1});
      // A search for the player with the bye lists only the bye.
      final bye = lay(query: 'name c');
      expect(bye.items.whereType<SheetBye>(), hasLength(1));
      expect(bye.items.whereType<SheetBoard>(), isEmpty);
      // Missing only hides byes; a round with nothing listed is left out.
      expect(lay(missingOnly: true).items.whereType<SheetBye>(), isEmpty);
      expect(lay(query: 'nobody').items, isEmpty);
      expect(SheetLayout.empty.items, isEmpty);
    });
  });

  group('focus order', () {
    final s = swiss(), selection = RoundSelection();
    final rows = boardRows([s], selection);

    test(
      'the grid is entered at the active box, or the first board missing a result',
      () {
        expect(firstOpenRow(rows)!.game.id, 'open-2-2');
        expect(entryBoxFor(rows, null), 'open-2-2-w');
        expect(entryBoxFor(rows, 'open-2-3-b'), 'open-2-3-b');
        // A box no longer listed is not where Tab enters.
        expect(entryBoxFor(rows, 'open-1-1-w'), 'open-2-2-w');
        final done = [rows.first];
        expect(firstOpenRow(done)!.game.id, 'open-2-1');
        expect(entryBoxFor(const [], 'open-2-1-w'), isNull);
        expect(boxKey('g', false), 'g-b');
      },
    );

    test('moving stops at either end', () {
      expect(stepFrom(rows, 'open-2-1', 1), 'open-2-2');
      expect(stepFrom(rows, 'open-2-1', -1), 'open-2-1');
      expect(stepFrom(rows, 'open-2-4', 1), 'open-2-4');
      // A board no longer listed counts from before the first.
      expect(stepFrom(rows, 'gone', 1), 'open-2-1');
      expect(stepFrom(const [], 'open-2-1', 1), isNull);
    });

    test(
      'after a result the next open board follows, wrapping to a skipped one',
      () {
        final order = ids(rows);
        expect(nextOpenGame(order, rows, 'open-2-1'), 'open-2-2');
        expect(nextOpenGame(order, rows, 'open-2-2'), 'open-2-4');
        expect(nextOpenGame(order, rows, 'open-2-4'), 'open-2-2');
        // The board just entered is skipped even while still open.
        expect(nextOpenGame(['open-2-2'], rows, 'open-2-2'), isNull);
        // A board missing from the order starts the search at the top.
        expect(nextOpenGame(order, rows, 'gone'), 'open-2-2');
        final finished = [
          for (final r in rows)
            BoardRow(r.section, r.round, r.game.copy(outcome: Outcome.draw)),
        ];
        expect(nextOpenGame(order, finished, 'open-2-1'), isNull);
      },
    );
  });

  group('keys on a score box', () {
    GridKeyAction act(
      GridKeyPress press, {
      bool busy = false,
      bool locked = false,
      Outcome current = Outcome.unreported,
    }) => gridKeyAction(press, busy: busy, locked: locked, current: current);

    test('move up, down, across and with Enter', () {
      expect(
        act(const GridKeyPress(GridKey.down)),
        isA<GridMoveBoard>().having((a) => a.by, 'by', 1),
      );
      expect(
        act(const GridKeyPress(GridKey.enter)),
        isA<GridMoveBoard>().having((a) => a.by, 'by', 1),
      );
      expect(
        act(const GridKeyPress(GridKey.enter, shift: true)),
        isA<GridMoveBoard>().having((a) => a.by, 'by', -1),
      );
      expect(
        act(const GridKeyPress(GridKey.down, shift: true)),
        isA<GridMoveBoard>().having((a) => a.by, 'by', -1),
      );
      expect(
        act(const GridKeyPress(GridKey.up, shift: true)),
        isA<GridMoveBoard>().having((a) => a.by, 'by', -1),
      );
      expect(
        act(const GridKeyPress(GridKey.left)),
        isA<GridMoveSide>().having((a) => a.white, 'white', isTrue),
      );
      expect(
        act(const GridKeyPress(GridKey.right)),
        isA<GridMoveSide>().having((a) => a.white, 'white', isFalse),
      );
      // Holding an arrow keeps moving, also on a locked round.
      expect(
        act(const GridKeyPress(GridKey.up, repeat: true), locked: true),
        isA<GridMoveBoard>(),
      );
    });

    test('released, held, modified and busy keys', () {
      expect(
        act(const GridKeyPress(GridKey.down, release: true)),
        isA<GridKeyIgnored>(),
      );
      // Holding a result key never enters it twice.
      expect(
        act(
          const GridKeyPress(
            GridKey.other,
            repeat: true,
            outcome: Outcome.whiteWin,
          ),
        ),
        isA<GridKeySwallowed>(),
      );
      expect(
        act(const GridKeyPress(GridKey.enter, repeat: true)),
        isA<GridKeySwallowed>(),
      );
      expect(
        act(
          const GridKeyPress(
            GridKey.other,
            modified: true,
            outcome: Outcome.whiteWin,
          ),
        ),
        isA<GridKeyIgnored>(),
      );
      expect(
        act(const GridKeyPress(GridKey.down), busy: true),
        isA<GridKeySwallowed>(),
      );
      expect(
        act(
          const GridKeyPress(GridKey.other, outcome: Outcome.draw),
          busy: true,
        ),
        isA<GridKeySwallowed>(),
      );
    });

    test('A, Space, F2 and Delete', () {
      expect(act(const GridKeyPress(GridKey.assume)), isA<GridAssume>());
      expect(
        act(const GridKeyPress(GridKey.assume), locked: true),
        isA<GridKeySwallowed>(),
      );
      expect(
        act(const GridKeyPress(GridKey.assume), current: Outcome.whiteWin),
        isA<GridKeySwallowed>(),
      );
      // A game still playing has no result yet, so it can be assumed.
      expect(
        act(const GridKeyPress(GridKey.assume), current: Outcome.unfinished),
        isA<GridAssume>(),
      );
      expect(
        act(const GridKeyPress(GridKey.details), locked: true),
        isA<GridShowPlayer>(),
      );
      expect(act(const GridKeyPress(GridKey.correct)), isA<GridKeySwallowed>());
      expect(
        act(
          const GridKeyPress(GridKey.correct),
          locked: true,
          current: Outcome.draw,
        ),
        isA<GridCorrect>(),
      );
      expect(
        act(const GridKeyPress(GridKey.clear, outcome: Outcome.unreported)),
        isA<GridEnter>()
            .having((a) => a.outcome, 'outcome', Outcome.unreported)
            .having((a) => a.clearsHint, 'clearsHint', isFalse),
      );
    });

    test('a result key enters it; other printable keys say which keys are', () {
      expect(
        act(
          const GridKeyPress(GridKey.other, outcome: Outcome.blackWin),
          locked: true,
        ),
        isA<GridEnter>()
            .having((a) => a.outcome, 'outcome', Outcome.blackWin)
            .having((a) => a.clearsHint, 'clearsHint', isTrue),
      );
      expect(
        act(const GridKeyPress(GridKey.other, printable: true)),
        isA<GridRefuse>()
            .having((a) => a.draw, 'draw', isFalse)
            .having((a) => a.forfeit, 'forfeit', isFalse),
      );
      // The numpad decimal may type nothing, yet still asks for a draw.
      expect(
        act(const GridKeyPress(GridKey.other, drawAttempt: true)),
        isA<GridRefuse>().having((a) => a.draw, 'draw', isTrue),
      );
      expect(
        act(
          const GridKeyPress(
            GridKey.other,
            printable: true,
            refusedOnForfeit: true,
          ),
        ),
        isA<GridRefuse>().having((a) => a.forfeit, 'forfeit', isTrue),
      );
      expect(act(const GridKeyPress(GridKey.other)), isA<GridKeyIgnored>());
    });
  });

  group('words', () {
    test('the overwrite notice names the section and round where needed', () {
      final s = swiss();
      final current = BoardRow(s, s.rounds.last, s.rounds.last.games.first);
      final earlier = BoardRow(s, s.rounds.first, s.rounds.first.games.first);
      expect(
        overwriteNoticeText(
          current,
          Outcome.whiteWin,
          Outcome.draw,
          everySection: false,
          allRounds: false,
        ),
        'Board 1 was 1–0, now ½–½',
      );
      expect(
        overwriteNoticeText(
          earlier,
          Outcome.whiteWin,
          Outcome.draw,
          everySection: true,
          allRounds: false,
        ),
        'Open · Round 1 · Board 1 was 1–0, now ½–½',
      );
      expect(
        overwriteNoticeText(
          current,
          Outcome.draw,
          Outcome.unreported,
          everySection: false,
          allRounds: true,
        ),
        'Round 2 · Board 1 was ½–½, now no result',
      );
    });

    test('read-only names what is locked', () {
      final a = swiss(), b = swiss(id: 'u', name: 'U1600');
      expect(
        readOnlyText(
          [(a, a.rounds.first)],
          everySection: false,
          showAllRounds: false,
        ),
        'Read-only',
      );
      expect(
        readOnlyText(
          [(a, a.rounds.first), (b, b.rounds.last)],
          everySection: true,
          showAllRounds: false,
        ),
        'Open round 1 is read-only',
      );
      expect(
        readOnlyText(
          [(a, a.rounds.first), (a, a.rounds.last)],
          everySection: false,
          showAllRounds: true,
        ),
        'Round 1 is read-only',
      );
      final q = quad();
      expect(
        readOnlyText(
          [(a, a.rounds.first), (b, b.rounds.first), (q, q.rounds.first)],
          everySection: true,
          showAllRounds: false,
        ),
        '2 sections are read-only',
      );
      expect(
        readOnlyText(
          [(a, a.rounds.first), (b, b.rounds.first), (q, q.rounds.first)],
          everySection: true,
          showAllRounds: true,
        ),
        'Earlier rounds are read-only',
      );
    });

    test('the round heading counts results', () {
      final s = swiss();
      final rows = boardRows([s], RoundSelection());
      final current = roundHeading(
        [(s, s.rounds.last)],
        [s],
        rows,
        showAllRounds: false,
      );
      expect(current.title, 'Round 2 of 4');
      expect(current.facts, ['2 of 4 results in']);
      expect(current.numbers, [2]);
      final all = boardRows([s], RoundSelection()..showAll());
      final every = roundHeading(
        [for (final r in s.rounds) (s, r)],
        [s],
        all,
        showAllRounds: true,
      );
      expect(every.title, 'All rounds');
      expect(every.facts, ['2 rounds', '6 of 8 results in']);
      final first = roundHeading(
        [(s, s.rounds.first)],
        [s],
        boardRows([s], RoundSelection()..pick(1, 2)),
        showAllRounds: false,
      );
      expect(first.facts, ['All 4 results in']);
      final some = roundHeading(
        [for (final r in s.rounds) (s, r)],
        [s],
        all,
        showAllRounds: false,
      );
      expect(some.title, 'Rounds 1–2');
      final unpaired = Section(
        id: 'n',
        name: 'New',
        players: const ['a', 'b'],
        plannedRounds: 5,
      );
      final none = roundHeading(
        const [],
        [unpaired],
        const [],
        showAllRounds: false,
      );
      expect(none.title, 'Round 1 of 5');
      expect(none.facts, ['Not paired yet']);
      expect(none.numbers, isEmpty);
      final unplanned = Section(
        id: 'n',
        name: 'New',
        players: const [],
        plannedRounds: 0,
      );
      expect(
        roundHeading(
          const [],
          [unplanned],
          const [],
          showAllRounds: false,
        ).title,
        'Round 1',
      );
    });

    test('the status line says whose result a key enters', () {
      final s = swiss(), e = event([s]);
      final row = BoardRow(s, s.rounds.last, s.rounds.last.games[1]);
      expect(
        entryContext(row, e, everySection: true, locked: false, white: false),
        "Open · Round 2 · Board 2 · Name OPEN-E vs Name OPEN-G · entering Black's result",
      );
      expect(
        entryContext(row, e, everySection: false, locked: true, white: true),
        'Round 2 · Board 2 · Name OPEN-E vs Name OPEN-G · read-only',
      );
      final double = Section(
        id: 'd',
        name: 'Double',
        doubleGames: true,
        players: const ['a', 'b'],
        rounds: [
          Round(number: 1, games: [game('d', 'b', 'a', 1, leg: 2)]),
        ],
      );
      expect(
        entryContext(
          BoardRow(
            double,
            double.rounds.single,
            double.rounds.single.games.single,
          ),
          event([double]),
          everySection: false,
          locked: false,
          white: true,
        ),
        "Round 1 · Board 1 · Game 2 · Name B vs Name A · entering White's result",
      );
    });
  });

  group('re-pairing boards not started', () {
    final s = swiss();
    final round = s.rounds.last;

    test('applies to one US Chess Swiss section, in its latest round', () {
      final repair = repairableRound([(s, round)], singleSection: true)!;
      expect(repair.section, s);
      expect(repair.boards, [2, 4]);
      expect(repairableRound([(s, round)], singleSection: false), isNull);
      expect(
        repairableRound([(s, s.rounds.first)], singleSection: true),
        isNull,
      );
      expect(
        repairableRound([(s, round), (s, s.rounds.first)], singleSection: true),
        isNull,
      );
      final q = quad();
      expect(
        repairableRound([(q, q.rounds.last)], singleSection: true),
        isNull,
      );
      final fide = s.copy(fideRated: true);
      expect(
        repairableRound([(fide, fide.rounds.last)], singleSection: true),
        isNull,
      );
    });

    test(
      'a board with a result or an assumption, on either game, has started',
      () {
        final r = Round(
          number: 1,
          games: [
            game('1a', 'a', 'b', 1),
            game('1b', 'b', 'a', 1, leg: 2, outcome: Outcome.draw),
            game('2', 'c', 'd', 2, assume: Outcome.draw),
            game('3', 'e', 'f', 3),
          ],
        );
        expect(unstartedBoards(r), [3]);
      },
    );

    test('withdrawn players waiting at those boards are named', () {
      final e = event([s], withdrawn: {'open-e', 'open-h', 'open-a'});
      expect(withdrawnOnUnstarted(round, e), [
        ('Name OPEN-E', 2),
        ('Name OPEN-H', 4),
      ]);
      expect(
        suggestedRepairReason(round, e),
        'Name OPEN-E, Name OPEN-H withdrew',
      );
      expect(suggestedRepairReason(round, event([s])), isNull);
      expect(withdrawnOnUnstarted(round, event([s])), isEmpty);
    });
  });

  group('editing pairings', () {
    test(
      'the first click picks, a second click on it cancels, another swaps',
      () {
        expect(pickForSwap(null, 'a'), (pick: 'a', swapWith: null));
        expect(pickForSwap('a', 'a'), (pick: null, swapWith: null));
        expect(pickForSwap('a', 'b'), (pick: null, swapWith: 'a'));
      },
    );

    test('a swap exchanges places, and colours on one board', () {
      final r = Round(
        number: 1,
        games: [game('1', 'a', 'b', 1), game('2', 'c', 'd', 2)],
      );
      final across = swapInRound(r, 'a', 'd');
      expect(
        [for (final g in across) (g.white, g.black)],
        [('d', 'b'), ('c', 'a')],
      );
      final colours = swapInRound(r, 'a', 'b');
      expect(
        [for (final g in colours) (g.white, g.black)],
        [('b', 'a'), ('c', 'd')],
      );
      expect(colours.first.id, '1');
    });
  });

  group('saved view', () {
    test('is saved with the keys and order older versions wrote', () {
      const saved = SavedResultsView(
        signature: 'open:2',
        round: 1,
        allRounds: false,
        scheduleRounds: true,
        search: 'chen',
        box: 'g-w',
        scroll: 120.5,
      );
      expect(
        jsonEncode(saved.toMap()),
        '{"signature":"open:2","round":1,"allRounds":false,'
        '"scheduleRounds":true,"search":"chen","box":"g-w","scroll":120.5}',
      );
      final back = SavedResultsView.restore(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(saved.toMap())) as Map),
        'open:2',
      )!;
      expect(back.toMap(), saved.toMap());
    });

    test(
      'is restored only for the same rounds, filling in what is missing',
      () {
        expect(
          SavedResultsView.restore({'signature': 'open:1'}, 'open:2'),
          isNull,
        );
        expect(SavedResultsView.restore({}, 'open:2'), isNull);
        final old = SavedResultsView.restore({
          'signature': 'open:2',
          'scroll': 3,
        }, 'open:2')!;
        expect(old.round, isNull);
        expect(old.allRounds, isFalse);
        expect(old.scheduleRounds, isTrue);
        expect(old.search, '');
        expect(old.box, isNull);
        expect(old.scroll, 3.0);
        expect(roundCountSignature([swiss(), quad()]), 'open:2|q:3');
      },
    );
  });
}
