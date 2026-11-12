import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/tiebreaks.dart';
import 'package:meow_chess/ui/players_view_model.dart';

/// Swiss "open": b beat a and c drew d in round 1; round 2 is paired with
/// nothing entered. Quad "reserve" has not started. Two players have no
/// section.
Event club({bool tiebreaks = false}) => Event(
  id: 'e',
  name: 'Club',
  date: '2026-11-11',
  useTiebreaks: tiebreaks,
  players: [
    Player(id: 'a', name: 'Anna Chen', rating: 2000, memberId: '12345678'),
    Player(id: 'b', name: 'Ben Diaz', rating: 1900, team: 'Rooks'),
    Player(id: 'c', name: 'Cara Eze', rating: 1800, byes: const {3: 1}),
    Player(id: 'd', name: 'Dan Fox', rating: 1700),
    Player(id: 'q1', name: 'Quinn One', rating: 1500),
    Player(id: 'q2', name: 'Quinn Two', rating: 1400),
    Player(id: 'q3', name: 'Quinn Three', rating: 1300),
    Player(id: 'q4', name: 'Quinn Four', rating: 1200),
    Player(id: 'x', name: 'Xavier Low', rating: 900),
    Player(id: 'y', name: 'Yara High', rating: 1600, team: 'Rooks'),
  ],
  sections: [
    Section(
      id: 'open',
      name: 'Open',
      players: const ['a', 'b', 'c', 'd'],
      plannedRounds: 3,
      rounds: [
        Round(
          number: 1,
          games: const [
            Game(
              id: 'g1',
              white: 'a',
              black: 'b',
              board: 1,
              outcome: Outcome.blackWin,
            ),
            Game(
              id: 'g2',
              white: 'c',
              black: 'd',
              board: 2,
              outcome: Outcome.draw,
            ),
          ],
        ),
        Round(
          number: 2,
          games: const [
            Game(id: 'g3', white: 'b', black: 'c', board: 1),
            Game(id: 'g4', white: 'd', black: 'a', board: 2),
          ],
        ),
      ],
    ),
    Section(
      id: 'reserve',
      name: 'Reserve',
      format: Format.quad,
      players: const ['q1', 'q2', 'q3', 'q4'],
    ),
  ],
);

List<String> idsOf(Iterable<Player> players) => [for (final p in players) p.id];

void main() {
  group('the column beside the table', () {
    test('rests on the ticked players, then a rating review, then nothing', () {
      expect(
        restingSideFor(ticked: true, reviewing: true),
        PlayersSide.selection,
      );
      expect(
        restingSideFor(ticked: false, reviewing: true),
        PlayersSide.ratingReview,
      );
      expect(restingSideFor(ticked: false, reviewing: false), isNull);
    });

    test('ticking shows the actions unless a form is open', () {
      for (final side in [
        null,
        PlayersSide.selection,
        PlayersSide.ratingReview,
        PlayersSide.done,
      ]) {
        expect(
          sideAfterTicking(side, ticked: true, resting: PlayersSide.selection),
          (change: true, side: PlayersSide.selection),
          reason: '$side',
        );
      }
      for (final side in [
        PlayersSide.player,
        PlayersSide.add,
        PlayersSide.team,
        PlayersSide.newSection,
        PlayersSide.paste,
      ]) {
        expect(
          sideAfterTicking(side, ticked: true, resting: PlayersSide.selection),
          (change: false, side: side),
          reason: '$side',
        );
      }
    });

    test('unticking the last player closes only the actions', () {
      expect(
        sideAfterTicking(
          PlayersSide.selection,
          ticked: false,
          resting: PlayersSide.ratingReview,
        ),
        (change: true, side: PlayersSide.ratingReview),
      );
      expect(sideAfterTicking(PlayersSide.team, ticked: false, resting: null), (
        change: false,
        side: PlayersSide.team,
      ));
    });

    test('a saved column reopens only while it still applies', () {
      expect(
        restoredSide(PlayersSide.done, reviewing: true, ticked: true),
        isNull,
      );
      expect(
        restoredSide(PlayersSide.ratingReview, reviewing: false, ticked: true),
        isNull,
      );
      expect(
        restoredSide(PlayersSide.ratingReview, reviewing: true, ticked: false),
        PlayersSide.ratingReview,
      );
      expect(
        restoredSide(PlayersSide.selection, reviewing: false, ticked: false),
        isNull,
      );
      expect(
        restoredSide(PlayersSide.selection, reviewing: false, ticked: true),
        PlayersSide.selection,
      );
      expect(
        restoredSide(PlayersSide.player, reviewing: false, ticked: false),
        PlayersSide.player,
      );
      expect(restoredSide(null, reviewing: true, ticked: true), isNull);
    });
  });

  group('selection', () {
    test(
      'changing the ticks drops a pending move or swap; ticking again does not',
      () {
        final picks = PlayerSelection()..tick(['a', 'b'], true);
        picks
          ..moveTo = 'reserve'
          ..moveRevision = 7
          ..swapping = true;
        picks.tick(['a'], true);
        expect(picks.moveTo, 'reserve');
        expect(picks.swapping, isTrue);
        picks.tick(['c'], false);
        expect(picks.moveTo, 'reserve');
        picks.tick(['a'], false);
        expect(picks.ticked, {'b'});
        expect(picks.moveTo, isNull);
        expect(picks.swapping, isFalse);
        // The revision is kept; it is saved only while a move or swap waits.
        expect(picks.moveRevision, 7);
      },
    );

    test('Shift-click ticks the rows from the last one clicked', () {
      final order = ['a', 'b', 'c', 'd', 'e'];
      final picks = PlayerSelection();
      expect(picks.clickRange(order, 'c', shift: true), ['c']);
      picks.anchor = 'd';
      expect(picks.clickRange(order, 'b', shift: true), ['b', 'c', 'd']);
      expect(picks.clickRange(order, 'e', shift: true), ['d', 'e']);
      expect(picks.clickRange(order, 'b', shift: false), ['b']);
      // An anchor filtered out of view starts no range.
      picks.anchor = 'z';
      expect(picks.clickRange(order, 'b', shift: true), ['b']);
    });

    test(
      'players gone from the event are unticked, and clearing unticks all',
      () {
        final e = club();
        final picks = PlayerSelection()..tick(['a', 'gone'], true);
        picks.moveTo = 'reserve';
        picks.keepOnly(e.players);
        expect(picks.ticked, {'a'});
        expect(picks.moveTo, isNull);
        picks.moveTo = 'reserve';
        picks.keepOnly(e.players);
        expect(picks.moveTo, 'reserve');
        picks
          ..swapping = true
          ..clear();
        expect(picks.ticked, isEmpty);
        expect(picks.moveTo, isNull);
        expect(picks.swapping, isFalse);
      },
    );

    test('the ticks change only in ways that drop a pending move', () {
      final picks = PlayerSelection()..tick(['a', 'b'], true);
      final ticks = picks.ticked;
      expect(() => ticks.clear(), throwsUnsupportedError);
      expect(() => ticks.add('c'), throwsUnsupportedError);
      expect(picks.ticked, {'a', 'b'});
      picks
        ..moveTo = 'reserve'
        ..moveRevision = 4;
      // Unticking everyone, as after moving them, drops the staged move so
      // it is never saved with the view or confirmed for another group.
      picks.tick(ticks.toList(), false);
      expect(ticks, isEmpty, reason: 'the view follows the ticks');
      expect(picks.moveTo, isNull);
      picks
        ..tick(['a', 'b'], true)
        ..swapping = true
        ..clear();
      expect(ticks, isEmpty);
      expect(picks.swapping, isFalse);
    });
  });

  test('search matches name, US Chess ID or team', () {
    final e = club();
    expect(playerMatches(e.player('a'), ' anna '), isTrue);
    expect(playerMatches(e.player('a'), '1234'), isTrue);
    expect(playerMatches(e.player('b'), 'ROOKS'), isTrue);
    expect(playerMatches(e.player('c'), 'rooks'), isFalse);
    expect(playerMatches(e.player('c'), ''), isTrue);
  });

  group('roster layout', () {
    test(
      'the players page lists each section, then the unassigned by rating',
      () {
        final e = club();
        final layout = layoutRoster(
          e,
          sectionId: null,
          standingsOnly: false,
          query: '',
          prizeStandings: false,
        );
        expect(
          [for (final g in layout.groups) g.$1?.id],
          ['open', 'reserve', null],
        );
        expect(idsOf(layout.order), [
          'a',
          'b',
          'c',
          'd',
          'q1',
          'q2',
          'q3',
          'q4',
          'y',
          'x',
        ]);
        expect(layout.shown, 10);
        expect(layout.started, isFalse);
        expect(layout.rounds, 0);
        expect(layout.cellGames, isEmpty);
        expect(layout.ranks, isEmpty);
        expect(layout.numbers, containsPair('d', 4));
        expect(layout.numbers, containsPair('q1', 1));
      },
    );

    test('a search keeps whole-section numbers and drops empty groups', () {
      final e = club();
      final layout = layoutRoster(
        e,
        sectionId: null,
        standingsOnly: false,
        query: 'rooks',
        prizeStandings: false,
      );
      expect([for (final g in layout.groups) g.$1?.id], ['open', null]);
      expect(idsOf(layout.order), ['b', 'y']);
      expect(layout.numbers['b'], 2);
      // Without a search an empty section still shows, to move players in.
      final empty = e.copy(
        sections: [
          ...e.sections,
          Section(id: 'new', name: 'New', players: const []),
        ],
      );
      final groups = layoutRoster(
        empty,
        sectionId: null,
        standingsOnly: false,
        query: '',
        prizeStandings: false,
      ).groups;
      expect(groups.where((g) => g.$1?.id == 'new').single.$2, isEmpty);
    });

    test(
      'the crosstable ranks a started section and lays out its score cells',
      () {
        final e = club();
        final layout = layoutRoster(
          e,
          sectionId: 'open',
          standingsOnly: true,
          query: '',
          prizeStandings: false,
        );
        expect(layout.started, isTrue);
        expect(layout.groups.single.$1!.id, 'open');
        expect(layout.order.first.id, 'b');
        expect(layout.order.last.id, 'a');
        expect(layout.ranks['b'], 1);
        expect(layout.ranks['a'], 4);
        expect(layout.tables['open']!['b']!.points, 2);
        expect(layout.rounds, 3);
        expect([for (final g in layout.cellGames['a']!) g.id], ['g1', 'g4']);
        expect(layout.prizeSection, isFalse);
        expect(layout.tiebreakColumns, isEmpty);
        // Pairing numbers stay the section's list order.
        expect(layout.numbers['a'], 1);
        expect(
          layoutRoster(
            club(tiebreaks: true),
            sectionId: 'open',
            standingsOnly: true,
            query: '',
            prizeStandings: false,
          ).tiebreakColumns,
          isNotEmpty,
        );
      },
    );

    test('while a result is entered the rows keep the order they had', () {
      final layout = layoutRoster(
        club(),
        sectionId: 'open',
        standingsOnly: true,
        query: '',
        prizeStandings: false,
        entryOrder: const ['d', 'c', 'b', 'a'],
      );
      expect(idsOf(layout.order), ['d', 'c', 'b', 'a']);
      expect(layout.ranks['b'], 1);
    });

    test(
      'the held order puts rows not on it first, in the order they came',
      () {
        List<String> order(List<String>? held, {String query = ''}) => idsOf(
          layoutRoster(
            club(),
            sectionId: null,
            standingsOnly: true,
            query: query,
            prizeStandings: false,
            entryOrder: held,
          ).order,
        );
        // Standings order without a held order: b 2, c and d 1½... a 0.
        final standings = order(null);
        expect(standings.take(4), ['b', 'c', 'd', 'a']);
        expect(standings.skip(4), ['q1', 'q2', 'q3', 'q4', 'y', 'x']);
        // Held: each group follows the held list; rows missing from it lead,
        // in standings, list or rating order.
        expect(order(['x', 'a', 'q4', 'y', 'b', 'q1']), [
          'c',
          'd',
          'a',
          'b',
          'q2',
          'q3',
          'q4',
          'q1',
          'x',
          'y',
        ]);
        // A search filters the held order without changing it.
        expect(order(['x', 'a', 'q4', 'y', 'b', 'q1'], query: 'Quinn'), [
          'q2',
          'q3',
          'q4',
          'q1',
        ]);
        // The players page holds its order the same way.
        expect(
          idsOf(
            layoutRoster(
              club(),
              sectionId: null,
              standingsOnly: false,
              query: '',
              prizeStandings: false,
              entryOrder: const ['d', 'a'],
            ).order,
          ),
          ['b', 'c', 'd', 'a', 'q1', 'q2', 'q3', 'q4', 'y', 'x'],
        );
      },
    );

    test('a player\'s games in a round are found without throwing', () {
      final open = club().sections.first;
      expect([for (final g in gamesOf(open, 1, 'a')) g.id], ['g1']);
      expect([for (final g in gamesOf(open, 2, 'c')) g.id], ['g3']);
      // A round not posted yet, and a player not in the round.
      expect(gamesOf(open, 3, 'a'), isEmpty);
      expect(gamesOf(open, 1, 'q1'), isEmpty);
      final double = open.copy(
        rounds: [
          Round(
            number: 1,
            games: const [
              Game(id: 'l1', white: 'a', black: 'b', board: 1),
              Game(id: 'l2', white: 'b', black: 'a', board: 1),
            ],
          ),
        ],
      );
      expect([for (final g in gamesOf(double, 1, 'a')) g.id], ['l1', 'l2']);
    });

    test('a quad that has not started is not ranked', () {
      final layout = layoutRoster(
        club(),
        sectionId: 'reserve',
        standingsOnly: true,
        query: '',
        prizeStandings: false,
      );
      expect(layout.started, isFalse);
      expect(layout.prizeSection, isFalse);
      expect(idsOf(layout.order), ['q1', 'q2', 'q3', 'q4']);
      expect(layout.cellGames.values.every((g) => g.isEmpty), isTrue);
    });
  });

  group('shown columns', () {
    ShownColumns columns({
      bool standingsOnly = false,
      bool? checkboxes,
      bool started = false,
      bool reviewing = false,
      bool usChessView = true,
      bool fideListed = false,
      bool showIds = true,
      int rounds = 0,
    }) => ShownColumns.of(
      standingsOnly: standingsOnly,
      // As embedded in Pairings, the crosstable has none.
      checkboxes: checkboxes ?? !standingsOnly,
      started: started,
      reviewing: reviewing,
      ratingPreview: false,
      showIds: showIds,
      usChessView: usChessView,
      fideListed: fideListed,
      rounds: rounds,
      tiebreaks: const [TiebreakMethod.modifiedMedian, TiebreakMethod.solkoff],
    );

    test('the table is as wide as the columns it shows', () {
      // Check, number, name, ID, rating, membership, note and the margin.
      expect(columns().width, 40 + 28 + 200 + 100 + 64 + 216 + 240 + 28);
      // Rank, number, name, three rounds, points, two tie-breaks, margin.
      expect(
        columns(standingsOnly: true, started: true, rounds: 3).width,
        40 + 28 + 160 + 120 + 40 + 112 + 28,
      );
      // FIDE only: the FIDE ID and rating, no US Chess columns.
      expect(
        columns(usChessView: false, fideListed: true).width,
        40 + 28 + 200 + 100 + 64 + 240 + 28,
      );
    });

    test('the embedded crosstable has no tick boxes or roster columns', () {
      final cross = columns(standingsOnly: true, fideListed: true);
      expect(cross.checkbox, isFalse);
      expect(cross.ids || cross.rating || cross.fide, isFalse);
      expect(cross.membership || cross.note, isFalse);
      // No tie-breaks before play, whatever the event ranks by.
      expect(cross.scores, isFalse);
      expect(cross.tiebreaks, isEmpty);
      expect(
        columns(standingsOnly: true, started: true).tiebreaks,
        hasLength(2),
      );
      // A crosstable on its own, with its own side column, can tick.
      expect(columns(standingsOnly: true, checkboxes: true).checkbox, isTrue);
      final roster = columns();
      expect(roster.checkbox && roster.ids && roster.rating, isTrue);
      expect(roster.membership && roster.note, isTrue);
    });

    test('a rating review always shows IDs and ratings', () {
      final review = columns(
        reviewing: true,
        usChessView: false,
        showIds: false,
      );
      expect(review.review, isTrue);
      expect(review.ids, isTrue);
      expect(review.rating, isTrue);
      expect(review.membership, isFalse);
      expect(columns(showIds: false).ids, isFalse);
    });
  });

  group('crosstable keys', () {
    final e = club();
    final layout = layoutRoster(
      e,
      sectionId: 'open',
      standingsOnly: true,
      query: '',
      prizeStandings: false,
      entryOrder: const ['a', 'b', 'c', 'd'],
    );
    final cells = roundCells(layout.order, e, 2);
    final g4 = e.games.firstWhere((g) => g.id == 'g4');
    final g1 = e.games.firstWhere((g) => g.id == 'g1');
    CellKeyAction act(
      CellKeyPress press, {
      String player = 'a',
      Game? game,
      bool entering = false,
    }) => cellKeyAction(
      press,
      player: player,
      game: game ?? g4,
      cells: cells,
      games: layout.cellGames[player]!,
      entering: entering,
    );

    test('a round\'s cells run down the rows', () {
      expect(
        [for (final x in cells) '${x.$1.id}:${x.$2.id}'],
        ['a:g4', 'b:g3', 'c:g3', 'd:g4'],
      );
      expect(cellIndex(cells, 'c', 'g3'), 2);
      expect(cellIndex(cells, 'c', 'g1'), -1);
      expect(cellKey('g3', 'c'), 'g3-c');
    });

    test('Up, Down and Enter move through the round, stopping at the ends', () {
      expect(
        act(const CellKeyPress(CellKey.down)),
        isA<CellMove>().having((m) => m.player, 'player', 'b'),
      );
      expect(
        act(const CellKeyPress(CellKey.enter)),
        isA<CellMove>().having((m) => m.game.id, 'game', 'g3'),
      );
      expect(act(const CellKeyPress(CellKey.up)), isA<CellKeySwallowed>());
      expect(
        act(const CellKeyPress(CellKey.enter, shift: true)),
        isA<CellKeySwallowed>(),
      );
      expect(
        act(const CellKeyPress(CellKey.up), player: 'd'),
        isA<CellMove>().having((m) => m.player, 'player', 'c'),
      );
      expect(
        act(const CellKeyPress(CellKey.down, shift: true), player: 'd'),
        isA<CellMove>().having((m) => m.player, 'player', 'c'),
      );
      expect(
        act(const CellKeyPress(CellKey.down), player: 'd'),
        isA<CellKeySwallowed>(),
      );
    });

    test('Left and Right move to the same player\'s other rounds', () {
      expect(
        act(const CellKeyPress(CellKey.left)),
        isA<CellMove>()
            .having((m) => m.game.id, 'game', 'g1')
            .having((m) => m.player, 'player', 'a'),
      );
      expect(act(const CellKeyPress(CellKey.right)), isA<CellKeySwallowed>());
      expect(
        act(const CellKeyPress(CellKey.left), game: g1),
        isA<CellKeySwallowed>(),
      );
      // Holding an arrow keeps moving; any other held key does nothing.
      expect(
        act(const CellKeyPress(CellKey.left, repeat: true)),
        isA<CellMove>(),
      );
      expect(
        act(
          const CellKeyPress(
            CellKey.other,
            repeat: true,
            outcome: Outcome.whiteWin,
          ),
        ),
        isA<CellKeyIgnored>(),
      );
      expect(
        act(const CellKeyPress(CellKey.left, release: true)),
        isA<CellKeyIgnored>(),
      );
      expect(
        act(const CellKeyPress(CellKey.left, modified: true)),
        isA<CellKeyIgnored>(),
      );
    });

    test('Space opens the player; result keys enter unless one is saving', () {
      expect(act(const CellKeyPress(CellKey.details)), isA<CellShowPlayer>());
      expect(
        act(const CellKeyPress(CellKey.other, outcome: Outcome.blackWin)),
        isA<CellEnter>()
            .having((a) => a.outcome, 'outcome', Outcome.blackWin)
            .having((a) => a.save, 'save', isTrue),
      );
      expect(
        act(
          const CellKeyPress(CellKey.other, outcome: Outcome.blackWin),
          entering: true,
        ),
        isA<CellEnter>().having((a) => a.save, 'save', isFalse),
      );
      expect(
        act(const CellKeyPress(CellKey.other, printable: true)),
        isA<CellRefuse>(),
      );
      expect(act(const CellKeyPress(CellKey.other)), isA<CellKeyIgnored>());
    });

    test(
      'Tab enters at the active cell, else the first one missing a result',
      () {
        final games = layout.cellGames;
        // Rows a, b, c, d: a's round 1 is in, so a's round 2 is the first
        // missing one.
        expect(entryCellFor(layout.order, games, null), 'g4-a');
        expect(entryCellFor(layout.order, games, 'g3-c'), 'g3-c');
        // A cell no longer listed is forgotten.
        expect(entryCellFor(layout.order, games, 'gone-a'), 'g4-a');
        // Every result in: the first cell.
        final done = {
          for (final MapEntry(:key, :value) in games.entries)
            key: [
              for (final g in value)
                g.copy(outcome: g.outcome.resolved ? null : Outcome.draw),
            ],
        };
        expect(entryCellFor(layout.order, done, null), 'g1-a');
        expect(entryCellFor(const [], games, 'g4-a'), isNull);
      },
    );

    test(
      'after a result the next cell missing one follows, wrapping round',
      () {
        final outcomes = {'g3': Outcome.whiteWin, 'g4': Outcome.unreported};
        Outcome of(String id) => outcomes[id]!;
        final next = nextMissingCell(cells, 1, 'g3', of)!;
        expect('${next.$1.id}:${next.$2.id}', 'd:g4');
        expect(nextMissingCell(cells, 3, 'g4', of), isNull);
        outcomes['g4'] = Outcome.draw;
        expect(nextMissingCell(cells, 0, 'g4', of), isNull);
      },
    );
  });

  test('round cells say what happened or what is planned', () {
    final e = club();
    final open = e.sections.first;
    expect(roundCellText(e, e.player('a'), open, 1), (
      '',
      'Round 1: 0 (lost) vs Ben Diaz (1900) as White',
    ));
    expect(roundCellText(e, e.player('b'), open, 2), (
      '',
      'Round 2: vs Cara Eze (1800) as White, no result yet',
    ));
    expect(roundCellText(e, e.player('c'), open, 3), (
      'H---',
      'Round 3: ½-point bye requested',
    ));
    expect(roundCellText(e, e.player('d'), open, 3), (
      '—',
      'Round 3: not paired yet.',
    ));
    expect(roundCellText(e, e.player('x'), null, 1), (
      '—',
      'Round 1: not paired yet.',
    ));
    final withBye = open.copy(
      rounds: [
        ...open.rounds,
        Round(
          number: 3,
          games: const [],
          byes: const [ByeAward('d', 2, 'Full-point bye')],
        ),
      ],
    );
    expect(roundCellText(e, e.player('d'), withBye, 3), (
      'B---',
      'Round 3: Full-point bye',
    ));
  });

  group('saved view', () {
    test('is saved with the keys and order older versions wrote', () {
      const saved = SavedPlayersView(
        search: 'ann',
        open: 'a',
        side: PlayersSide.selection,
        selected: ['a', 'b'],
        activeResult: 'g4-a',
        showRatingPreview: true,
        moveTo: 'reserve',
        moveRevision: 9,
        moveReason: 'Wrong section',
        scroll: 40,
      );
      expect(
        jsonEncode(saved.toMap()),
        '{"search":"ann","open":"a","side":"selection","selected":["a","b"],'
        '"activeResult":"g4-a","showRatingPreview":true,"prizeStandings":false,'
        '"moveTo":"reserve","moveRevision":9,"swapping":false,'
        '"moveReason":"Wrong section","scroll":40.0}',
      );
      final back = SavedPlayersView.fromMap(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(saved.toMap())) as Map),
      );
      expect(back.side, PlayersSide.selection);
      expect(back.selected, ['a', 'b']);
      expect(back.moveRevision, 9);
      expect(back.moveReason, 'Wrong section');
    });

    test('keeps the revision only while a move or swap waits on it', () {
      expect(
        const SavedPlayersView(moveRevision: 3).toMap()['moveRevision'],
        isNull,
      );
      expect(
        const SavedPlayersView(
          moveRevision: 3,
          swapping: true,
        ).toMap()['moveRevision'],
        3,
      );
    });

    test('reads what older versions wrote, ignoring what it does not know', () {
      final old = SavedPlayersView.fromMap({
        'side': 'retired',
        'selected': ['a', 3, null],
        'moveRevision': 4.0,
        'scroll': 12,
      });
      expect(old.side, isNull);
      expect(old.selected, ['a']);
      expect(old.moveRevision, 4);
      expect(old.search, '');
      expect(SavedPlayersView.scrollOf({'scroll': 12}), 12.0);
      expect(SavedPlayersView.scrollOf({}), 0.0);
    });
  });
}
