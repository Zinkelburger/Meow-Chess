import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/player_actions.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/select.dart';
import 'package:meow_chess/ui/theme.dart';

import '../support.dart';

Future<void> mount(
  WidgetTester tester,
  TournamentController c, {
  bool standingsOnly = false,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: c,
          builder: (_, _) => PlayersView(
            controller: c,
            standingsOnly: standingsOnly,
            onRefreshRatings: standingsOnly ? null : () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tick(WidgetTester tester, String id) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(ValueKey('player-$id')),
      matching: find.byType(PlainCheckbox),
    ),
  );
  await tester.pump();
}

/// Gives [sectionId] a hand-edited quad schedule.
void editPairings(TournamentController c, String sectionId) => c.change(
  'Edit pairings by hand',
  c.event!.copy(
    sections: [
      for (final s in c.event!.sections)
        s.id == sectionId
            ? s.copy(
                quadPairings: const [
                  [0, 3, 1, 2],
                  [2, 0, 3, 1],
                  [0, 1, 2, 3],
                ],
              )
            : s,
    ],
  ),
);

const reset = 'The hand-edited pairings for Quad 2 were reset.';

void main() {
  test('removing a player says when hand-edited quad pairings were reset', () {
    final c = fixture();
    addTearDown(c.dispose);
    final [quad1, quad2] = c.event!.sections;
    editPairings(c, quad2.id);
    final done = applyStatus(c, StatusAction.remove, [quad2.players.last]);
    expect(c.event!.sections.last.quadPairings, isEmpty);
    expect(
      done.message,
      endsWith('Quad 2 now has 3 players. A quad needs four. $reset'),
    );
    // Nothing is claimed where no hand edit was lost.
    final plain = applyStatus(c, StatusAction.remove, [quad1.players.last]);
    expect(plain.message, isNot(contains('hand-edited')));
    expect(pairingsResetNote(c.event!, c.event!), isNull);
  });

  testWidgets('a bulk move out of a hand-edited quad says it was reset', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    final [quad1, quad2] = c.event!.sections;
    editPairings(c, quad2.id);
    await mount(tester, c);
    await tick(tester, quad2.players.first);
    await tester.tap(find.byKey(ValueKey('move-to-${quad1.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Players moved'), findsOneWidget);
    expect(find.textContaining(reset), findsOneWidget);
    expect(find.byKey(const ValueKey('done-undo')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Move player panel confirms the move with Undo', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    // A Swiss player joins a quad of three whose pairings were hand-edited.
    final [first, second] = c.event!.sections;
    c.removePlayers([second.players.last]);
    c.change(
      'Make the first section a Swiss',
      c.event!.copy(
        sections: [
          for (final s in c.event!.sections)
            s.id == first.id ? s.copy(format: Format.swiss) : s,
        ],
      ),
    );
    editPairings(c, second.id);
    final mover = first.players.first;
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) =>
                MovePlayerPanel(controller: c, playerId: mover, onClose: () {}),
          ),
        ),
      ),
    );
    await chooseOption(
      tester,
      find.byWidgetPredicate(
        (w) => w is PlainSelect<String?> && w.label == 'Move to',
      ),
      second.name,
    );
    final head = c.graph.head;
    await tester.tap(find.byKey(const ValueKey('apply-player-operation')));
    await tester.pumpAndSettle();
    expect(c.event!.sectionOf(mover)!.id, second.id);
    expect(
      find.text('Moved ${c.event!.player(mover).name} to Quad 2. $reset'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(c.graph.head, head);
    expect(c.event!.sectionOf(mover)!.id, first.id);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Do not pair together is confirmed, with Undo', (tester) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await mount(tester, c);
    await tick(tester, 'p0');
    await tick(tester, 'p1');
    await tester.ensureVisible(find.text('Do not pair together'));
    await tester.tap(find.text('Do not pair together'));
    await tester.pumpAndSettle();
    expect(c.event!.player('p0').avoid, {'p1'});
    expect(find.text('Request saved'), findsOneWidget);
    expect(
      find.textContaining(
        'Player 00 and Player 01 will not be paired together',
      ),
      findsOneWidget,
    );
    expect(find.text('2 players selected'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('done-undo')));
    await tester.pumpAndSettle();
    expect(c.event!.player('p0').avoid, isEmpty);
    expect(c.event!.player('p1').avoid, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an empty crosstable does not talk about a search', (
    tester,
  ) async {
    final c = TournamentController(SqliteEventRepository(':memory:'))
      ..create('New event');
    addTearDown(c.dispose);
    await mount(tester, c, standingsOnly: true);
    expect(find.text('No matches'), findsNothing);
    expect(find.textContaining('Try a different name'), findsNothing);
    expect(find.text('No players yet.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a search with no match still says so', (tester) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await mount(tester, c);
    await tester.enterText(
      find.byKey(const ValueKey('player-search')),
      'nobody by this name',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Players page says US Chess, never USCF', (tester) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await mount(tester, c);
    expect(find.text('US Chess ID'), findsOneWidget);
    expect(find.text('US Chess expires'), findsOneWidget);
    expect(find.text('Refresh from US Chess'), findsOneWidget);
    expect(find.textContaining('USCF'), findsNothing);
    expect(find.byTooltip('Print player list'), findsNothing);
    expect(find.text('Print player list'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
