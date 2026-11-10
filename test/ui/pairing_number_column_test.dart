import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/fide.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/standings.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/theme.dart';

/// One Swiss section whose list order is not its rating order, so a
/// pairing number can be told apart from a place or a sort position.
TournamentController swiss() {
  final c = TournamentController(SqliteEventRepository(':memory:'))
    ..create('Club Swiss');
  c.importPlayers([
    for (final (i, r) in [1500, 2100, 1300, 1900, 1100, 1700].indexed)
      Player(id: 'p$i', name: 'Player $i', rating: r),
  ]);
  c.addSection('Open', Format.swiss, 3);
  return c;
}

Future<void> mount(
  WidgetTester tester,
  TournamentController c, {
  required bool standingsOnly,
  Size size = const Size(1400, 900),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: c,
          builder: (_, _) => PlayersView(
            controller: c,
            sectionId: c.event!.sections.single.id,
            standingsOnly: standingsOnly,
            // As Pairings embeds it: the card opens in the parent.
            onPlayer: standingsOnly ? (_, {focus}) {} : null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder cell(String column, String id, String text) => find.descendant(
  of: find.byKey(ValueKey('$column-$id')),
  matching: find.text(text),
);

void expectNumbers(TournamentController c) {
  final section = c.event!.sections.single;
  for (final (i, id) in section.players.indexed) {
    expect(cell('number', id, '${i + 1}'), findsOneWidget, reason: id);
  }
}

void main() {
  test('pairing numbers are the place on the section list, or FIDE order', () {
    final c = swiss();
    addTearDown(c.dispose);
    final e = c.event!, s = e.sections.single;
    expect(pairingNumbers(e, s), {
      for (final (i, id) in s.players.indexed) id: i + 1,
    });
    // A FIDE-rated Swiss numbers by C.04.2's ranking instead.
    final fide = s.copy(fideRated: true);
    expect(pairingNumbers(e, fide), {
      for (final (i, p) in fidePairingOrder(e, fide).indexed) p.id: i + 1,
    });
  });

  testWidgets('# on Players is the pairing number, also while searching', (
    tester,
  ) async {
    final c = swiss();
    addTearDown(c.dispose);
    await mount(tester, c, standingsOnly: false);
    expect(find.text('#'), findsOneWidget);
    expect(find.text('Rank'), findsNothing);
    expectNumbers(c);
    await tester.enterText(
      find.byKey(const ValueKey('player-search')),
      'Player 4',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player-p0')), findsNothing);
    expect(cell('number', 'p4', '5'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the crosstable keeps # and adds Rank once it is ranked', (
    tester,
  ) async {
    final c = swiss();
    addTearDown(c.dispose);
    await mount(tester, c, standingsOnly: true);
    // Before round 1 there is no place to show.
    expect(find.text('Rank'), findsNothing);
    expect(find.text('#'), findsOneWidget);
    expectNumbers(c);

    c.post((await tester.runAsync(() => c.propose()))!);
    // Black wins everywhere, so the standings order leaves the list order.
    for (final g in c.event!.games) {
      c.recordResult(g.id, Outcome.blackWin);
    }
    await tester.pumpAndSettle();
    expect(find.text('Rank'), findsOneWidget);
    expect(find.text('#'), findsOneWidget);
    expectNumbers(c);
    final e = c.event!, section = e.sections.single;
    final table = standings(e, section);
    expect([
      for (final row in table) row.player.id,
    ], isNot(orderedEquals(section.players)));
    for (final (i, row) in table.indexed) {
      expect(cell('rank', row.player.id, '${i + 1}'), findsOneWidget);
    }
    // Rank is left of #, and both keep their meaning under a search.
    expect(
      tester.getTopLeft(find.text('Rank')).dx,
      lessThan(tester.getTopLeft(find.text('#')).dx),
    );
    final last = table.last.player.id;
    await tester.enterText(
      find.byKey(const ValueKey('player-search')),
      e.player(last).name,
    );
    await tester.pumpAndSettle();
    expect(cell('rank', last, '${table.length}'), findsOneWidget);
    expect(
      cell('number', last, '${section.players.indexOf(last) + 1}'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the ranked crosstable fits a Pairings pane at ${scale}x', (
      tester,
    ) async {
      final c = swiss();
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      await mount(
        tester,
        c,
        standingsOnly: true,
        size: Size(560 * scale + 400, 700),
        scale: scale,
      );
      expect(find.text('Rank'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
