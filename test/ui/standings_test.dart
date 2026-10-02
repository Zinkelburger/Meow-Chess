import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/standings.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/players_view.dart';
import '../support.dart';

Future<void> mountPlayers(WidgetTester tester, TournamentController c) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: c,
          builder: (_, _) => PlayersView(controller: c),
        ),
      ),
    ),
  );
}

Standing row(String name, int points, int bh, int sb) =>
    Standing(Player(id: name, name: name), points, bh, sb, 1);

void main() {
  test('ties share a rank marked T-, and the reason is spelled out', () {
    final rows = [
      row('Ann', 4, 6, 8),
      row('Bob', 4, 5, 8),
      row('Cy', 2, 5, 4),
      row('Di', 2, 5, 4),
      row('Ed', 0, 4, 0),
    ];
    expect(
      {for (final e in rankLabels(rows).entries) e.key: e.value.$1},
      {'Ann': '1', 'Bob': '2', 'Cy': 'T-3', 'Di': 'T-3', 'Ed': '5'},
    );
    expect(whyRank(rows, rows[0]), contains('Buchholz'));
    expect(whyRank(rows, rows[0]), contains('3 against 2½'));
    expect(whyRank(rows, rows[2]), contains('share the rank'));
    expect(whyRank(rows, rows[4]), 'The only player on 0 points.');
  });

  testWidgets('standings show rank, tiebreaks and why, without a menu', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    for (final g in c.event!.games) {
      c.recordResult(g.id, Outcome.draw);
    }
    await mountPlayers(tester, c);
    expect(find.text('RANK'), findsOneWidget);
    expect(find.text('BH'), findsOneWidget);
    expect(find.text('SB'), findsOneWidget);
    // All four in a quad drew: everyone is tied.
    expect(find.text('T-1'), findsNWidgets(8));
    final id = c.event!.sections.first.players.first;
    await tester.tap(find.byKey(ValueKey('rank-$id')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(ValueKey('why-$id')),
        matching: find.textContaining('share the rank'),
      ),
      findsOneWidget,
    );
    // Seed order drops the rank column and keeps pairing numbers.
    await tester.tap(find.text('Seed order'));
    await tester.pump();
    expect(find.text('RANK'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('prize classes are chips, and rank within the class', (
    tester,
  ) async {
    final c = TournamentController(SqliteEventRepository(':memory:'))
      ..create('Swiss');
    addTearDown(c.dispose);
    c.importPlayers([
      for (final (i, r) in [2100, 1900, 1700, 1500].indexed)
        Player(id: 'p$i', name: 'Player $i', rating: r),
    ]);
    c.addSection('Open', Format.swiss, 3);
    c.post((await tester.runAsync(() => c.propose()))!);
    for (final g in c.event!.games) {
      c.recordResult(g.id, Outcome.whiteWin);
    }
    await mountPlayers(tester, c);
    expect(find.byKey(const ValueKey('prize-classes')), findsOneWidget);
    // Classes holding some but not all rated players.
    expect(find.text('Under 2000'), findsOneWidget);
    expect(find.text('Under 1800'), findsOneWidget);
    expect(find.text('Under 2200'), findsNothing);
    await tester.tap(find.text('Under 1800'));
    await tester.pump();
    expect(find.text('Player 0'), findsNothing);
    expect(find.text('Player 1'), findsNothing);
    // Ranked within the class: nobody is third or fourth.
    for (final id in ['p2', 'p3']) {
      final label = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(ValueKey('rank-$id')),
              matching: find.byType(Text),
            ),
          )
          .data;
      expect(['1', '2', 'T-1'], contains(label));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pairing numbers are the section numbers the crosstable prints', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mountPlayers(tester, c);
    final q2 = c.event!.sections.last;
    final first = q2.players.first;
    // Quad 2's top seed is number 1, not 5.
    expect(
      find.descendant(
        of: find.byKey(ValueKey('player-$first')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
