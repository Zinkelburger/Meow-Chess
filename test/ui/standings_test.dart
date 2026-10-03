import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/standings.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/players_view.dart';
import '../support.dart';

Future<void> mountPlayers(
  WidgetTester tester,
  TournamentController c, {
  Size size = const Size(1600, 1000),
  String? sectionId,
  bool standingsOnly = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: c,
          builder: (_, _) => PlayersView(
            controller: c,
            sectionId: sectionId,
            standingsOnly: standingsOnly,
          ),
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

  testWidgets('standings show plain ranks with explanations on hover', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    for (final g in c.event!.games) {
      c.recordResult(g.id, Outcome.draw);
    }
    await mountPlayers(tester, c);
    expect(find.text('Rank'), findsOneWidget);
    expect(find.text('BH'), findsNothing);
    expect(find.text('SB'), findsNothing);
    // All four in a quad drew: everyone is tied.
    expect(find.text('T-1'), findsNWidgets(8));
    final id = c.event!.sections.first.players.first;
    final rank = find.byKey(ValueKey('rank-$id'));
    expect(
      find.descendant(of: rank, matching: find.byType(Icon)),
      findsNothing,
    );
    expect(
      find.descendant(of: rank, matching: find.byType(InkWell)),
      findsNothing,
    );
    final tooltip = tester.widget<Tooltip>(
      find.descendant(of: rank, matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, contains('share the place'));
    await tester.tap(rank);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('why-$id')), findsNothing);
    expect(find.byKey(const ValueKey('panel-name')), findsOneWidget);
    expect(find.text('Seed order'), findsNothing);
    expect(find.byKey(const ValueKey('pairings-pane')), findsNothing);
    expect(find.text('Print standings'), findsOneWidget);
    expect(find.text('Print pairings'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(1600, 1000), const Size(960, 700)]) {
    testWidgets('standings reserve a stable player card area at $size', (
      tester,
    ) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final section = c.event!.sections.first;
      await mountPlayers(tester, c, size: size, sectionId: section.id);
      await tester.pumpAndSettle();
      final standings = find.byKey(const ValueKey('standings-pane'));
      final details = find.byKey(const ValueKey('player-details-area'));
      final header = find.byKey(const ValueKey('player-column-header'));
      final standingsBefore = tester.getRect(standings);
      final headerBefore = tester.getRect(header);
      final detailsBefore = tester.getRect(details);
      expect(detailsBefore.width, 360);
      expect(standingsBefore.right, lessThanOrEqualTo(detailsBefore.left));
      expect(
        find.byKey(const ValueKey('standings-pairings-tabs')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('pairings-pane')), findsNothing);
      expect(find.text('Print standings'), findsOneWidget);
      // A four-player section should not stretch its table to fill the page.
      final list = find.descendant(
        of: standings,
        matching: find.byType(ListView),
      );
      expect(tester.getSize(list).height, lessThan(350));
      final player = c.event!.player(section.players.first);
      await tester.tap(find.text(player.name, findRichText: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('panel-name')), findsOneWidget);
      expect(tester.getRect(standings), standingsBefore);
      expect(tester.getRect(header), headerBefore);
      expect(tester.getRect(details), detailsBefore);
      await tester.tap(find.byTooltip('Close (Esc)'));
      await tester.pumpAndSettle();
      expect(tester.getRect(standings), standingsBefore);
      expect(tester.getRect(header), headerBefore);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'old prize filters cannot hide players in the compact standings',
    (tester) async {
      final c = TournamentController(SqliteEventRepository(':memory:'))
        ..create('Swiss');
      addTearDown(c.dispose);
      c.importPlayers([
        for (final (i, r) in [2100, 1900, 1700, 1500].indexed)
          Player(id: 'p$i', name: 'Player $i', rating: r),
      ]);
      c.addSection('Open', Format.swiss, 3);
      c.post((await tester.runAsync(() => c.propose()))!);
      c.workspaceState.writeMap('players-view-all', {
        'ceiling': 1800,
        'prizes': true,
        'showRatingPreview': true,
      });
      await mountPlayers(tester, c);
      expect(find.byKey(const ValueKey('prize-classes')), findsNothing);
      expect(find.text('Show rating estimates'), findsNothing);
      expect(find.text('USCF expires'), findsNothing);
      expect(find.text('1 / W win · 0 / L loss · D draw'), findsNothing);
      expect(find.byTooltip('1 / W win · 0 / L loss · D draw'), findsNothing);
      for (var i = 0; i < 4; i++) {
        expect(find.byKey(ValueKey('player-p$i')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

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
