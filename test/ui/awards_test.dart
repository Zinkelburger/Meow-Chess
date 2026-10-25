import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/prizes.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/awards_view.dart';
import 'package:meow_chess/ui/theme.dart';

Json place(int n, String item, {int dollars = 0}) => {
  'id': 'place$n',
  'kind': 'place',
  'place': n,
  'cents': dollars * 100,
  'item': item,
};

/// Four kids, two rounds. Quinn wins both; Zed and Aaron finish on 1 with
/// equal Modified Median and Solkoff, and Zed won first, so Zed is ahead on
/// Cumulative although Aaron sorts first by name.
Event scholastic({bool lastRoundDone = true, List<Json>? prizes}) {
  final players = [
    for (final name in ['Aaron', 'Zed', 'Pat', 'Quinn'])
      Player(id: name.toLowerCase(), name: name, rating: 700),
  ];
  Game game(String id, String w, String b, Outcome o, int board) =>
      Game(id: id, white: w, black: b, board: board, outcome: o);
  return Event(
    id: 'e',
    name: 'November Scholastics',
    date: '2026-11-15',
    players: players,
    sections: [
      Section(
        id: 'u1000',
        name: 'Under 1000',
        players: [for (final p in players) p.id],
        plannedRounds: 2,
        ratingCeiling: 1000,
        rounds: [
          Round(
            number: 1,
            games: [
              game('g1', 'zed', 'pat', Outcome.whiteWin, 1),
              game('g2', 'quinn', 'aaron', Outcome.whiteWin, 2),
            ],
          ),
          Round(
            number: 2,
            games: [
              game('g3', 'aaron', 'pat', Outcome.whiteWin, 1),
              game(
                'g4',
                'quinn',
                'zed',
                lastRoundDone ? Outcome.whiteWin : Outcome.unreported,
                2,
              ),
            ],
          ),
        ],
        prizes: {
          'list':
              prizes ??
              [place(1, 'Trophy'), place(2, 'Trophy'), place(3, 'Medal')],
        },
      ),
    ],
  );
}

void main() {
  test('rule 34A: a trophy tie goes by tie-breaks, not by name, even when '
      'equal scores share a place', () {
    final e = scholastic();
    expect(e.useTiebreaks, isFalse);
    final a = allocatePrizes(e, e.sections.single);
    final second = a.lines.firstWhere((l) => l.prize.id == 'place2');
    expect(second.trophyWinner, 'zed');
    expect(
      second.trophyNote,
      startsWith('Tied on 1 with Aaron; ahead of Aaron on Cumulative'),
    );
    final third = a.lines.firstWhere((l) => l.prize.id == 'place3');
    expect(third.trophyWinner, 'aaron');
    expect(third.prize.award, 'Medal');
  });

  test('equal on every tie-break: the director decides by lot', () {
    // Scores from byes: no opponents, so no tie-break can separate them.
    final players = [
      Player(id: 'a', name: 'Aaron', rating: 700),
      Player(id: 'z', name: 'Zed', rating: 700),
    ];
    final e = Event(
      id: 'e',
      name: 'Byes',
      date: '2026-11-15',
      players: players,
      sections: [
        Section(
          id: 's',
          name: 'Under 500',
          players: const ['a', 'z'],
          plannedRounds: 1,
          rounds: [
            Round(
              number: 1,
              games: const [],
              byes: [ByeAward('a', 2, 'test'), ByeAward('z', 2, 'test')],
            ),
          ],
          prizes: {
            'list': [place(1, 'Trophy')],
          },
        ),
      ],
    );
    final rows = awardRows(e, e.sections.single);
    expect(rows.single.lot, isTrue);
    expect(rows.single.detail, contains('decide by lot'));
  });

  test('an award reads as announced, and a plain trophy stays a trophy', () {
    expect(Prize(id: 'x', trophy: true).award, 'Trophy');
    expect(Prize(id: 'x', item: 'Medal').trophy, isTrue);
    final cleared = Prize(id: 'x', item: 'Medal').copy(trophy: false);
    expect(cleared.award, isEmpty);
    expect(cleared.trophy, isFalse);
    final back = Prize.fromJson(Prize(id: 'x', item: 'Plaque').toJson());
    expect(back.award, 'Plaque');
  });

  test('progress says provisional until every result is in', () {
    final playing = scholastic(lastRoundDone: false).sections.single;
    expect(
      awardsProgress(playing).text,
      'Provisional · round 2: 1 game still playing',
    );
    expect(awardsProgress(scholastic().sections.single).text, 'Final');
  });

  testWidgets('Awards list who takes what, and Handed out is remembered', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = TournamentController(SqliteEventRepository(':memory:'))
      ..create('November Scholastics');
    addTearDown(c.dispose);
    final e = scholastic();
    c.change(
      'Load test event',
      c.event!.copy(players: e.players, sections: e.sections),
    );
    Future<void> mount() => tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: c,
              builder: (_, _) => AwardsBoard(controller: c),
            ),
          ),
        ),
      ),
    );
    await mount();
    expect(tester.takeException(), isNull);
    expect(find.text('Quinn'), findsOneWidget);
    expect(find.text('Zed'), findsOneWidget);
    expect(find.text('Aaron'), findsOneWidget);
    expect(find.text('Medal'), findsOneWidget);
    expect(find.textContaining('ahead of Aaron on Cumulative'), findsOneWidget);
    expect(find.text('Final'), findsOneWidget);

    final zed = find.byKey(const ValueKey('handed-u1000|place2|zed'));
    await tester.tap(zed);
    await tester.pump();
    // Leaving Reports and coming back keeps the ticks.
    await tester.pumpWidget(const SizedBox());
    await mount();
    expect(
      tester
          .widget<PlainCheckbox>(
            find.byKey(const ValueKey('handed-u1000|place2|zed')),
          )
          .value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
