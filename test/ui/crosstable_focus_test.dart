import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/result_format.dart';
import 'package:meow_chess/ui/theme.dart';

/// A six-player Swiss with round 1 posted.
Future<TournamentController> posted(WidgetTester tester) async {
  final c = TournamentController(SqliteEventRepository(':memory:'))
    ..create('Club Swiss');
  c.importPlayers([
    for (final (i, r) in [2100, 1900, 1700, 1500, 1300, 1100].indexed)
      Player(id: 'p$i', name: 'Player $i', rating: r),
  ]);
  c.addSection('Open', Format.swiss, 3);
  c.post((await tester.runAsync(() => c.propose()))!);
  return c;
}

/// The crosstable as Pairings embeds it; [opened] collects the players it
/// asks its parent to show.
Future<void> mount(
  WidgetTester tester,
  TournamentController c, {
  List<String>? opened,
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
            sectionId: c.event!.sections.single.id,
            standingsOnly: true,
            onPlayer: (id, {focus}) => opened?.add(id),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every score cell's focus node on screen.
List<FocusNode> cells(WidgetTester tester) => [
  for (final focus in tester.widgetList<Focus>(find.byType(Focus)))
    if (focus.focusNode case final node?
        when (node.debugLabel ?? '').startsWith('standing-'))
      node,
];

String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

String label(Game g, String player) => 'standing-${g.id}-$player';

Future<void> tapCell(WidgetTester tester, Game g, String player) async {
  await tester.tap(find.byKey(ValueKey('standing-score-${g.id}-$player')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the crosstable is one Tab stop, entered at a missing result', (
    tester,
  ) async {
    final c = await posted(tester);
    addTearDown(c.dispose);
    final games = c.event!.sections.single.rounds.single.games;
    // The top row's game is in; the next row's is the first one missing.
    final order = c.event!.sections.single.players;
    final first = games.firstWhere(
      (g) => g.white == order.first || g.black == order.first,
    );
    c.recordResult(first.id, Outcome.whiteWin);
    await mount(tester, c);
    expect(cells(tester).length, 6);
    final stops = cells(tester).where((n) => !n.skipTraversal).toList();
    expect(stops.length, 1);
    expect(stops.single.debugLabel, isNot(contains(first.id)));
    // Rows are not Tab stops of their own.
    for (final id in order) {
      expect(
        tester
            .widget<InkWell>(find.byKey(ValueKey('player-$id')))
            .canRequestFocus,
        false,
      );
    }

    // Tab from the search box reaches the grid at that cell, and the next
    // Tab leaves the grid instead of walking its cells.
    await tester.tap(find.byKey(const ValueKey('player-search')));
    await tester.pumpAndSettle();
    var entered = false;
    for (var i = 0; i < 6 && !entered; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      entered = focused()?.startsWith('standing-') ?? false;
    }
    expect(entered, true);
    expect(focused(), stops.single.debugLabel);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(focused()?.startsWith('standing-') ?? false, false);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('arrows move inside the crosstable and Space opens the player', (
    tester,
  ) async {
    final c = await posted(tester);
    addTearDown(c.dispose);
    for (final g in c.event!.games) {
      c.recordResult(g.id, Outcome.draw);
    }
    c.post((await tester.runAsync(() => c.propose()))!);
    final opened = <String>[];
    await mount(tester, c, opened: opened);
    final section = c.event!.sections.single;
    Game game(int round, String id) => section.rounds[round - 1].games
        .firstWhere((g) => g.white == id || g.black == id);
    final rows = [
      for (final row in tester.widgetList<InkWell>(
        find.byWidgetPredicate(
          (w) => w is InkWell && '${w.key}'.contains('player-'),
        ),
      ))
        (row.key! as ValueKey<String>).value.substring('player-'.length),
    ];
    final top = rows[0], next = rows[1];

    await tapCell(tester, game(1, top), top);
    expect(focused(), label(game(1, top), top));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focused(), label(game(2, top), top));
    // Wherever the arrows went is where Tab stops now.
    expect(
      cells(tester).where((n) => !n.skipTraversal).single.debugLabel,
      label(game(2, top), top),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(), label(game(2, next), next));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(focused(), label(game(1, next), next));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focused(), label(game(1, top), top));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(opened, [top]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a key that replaces a recorded result says so, with Undo', (
    tester,
  ) async {
    final c = await posted(tester);
    addTearDown(c.dispose);
    final g = c.event!.sections.single.rounds.single.games.first;
    c.recordResult(g.id, Outcome.whiteWin);
    await mount(tester, c);

    // A first result is not an overwrite.
    final other = c.event!.sections.single.rounds.single.games.last;
    await tapCell(tester, other, other.white);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    expect(
      c.event!.games.firstWhere((x) => x.id == other.id).outcome,
      Outcome.whiteWin,
    );
    expect(find.byKey(const ValueKey('undo-notice')), findsNothing);

    await tapCell(tester, g, g.white);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(
      c.event!.games.firstWhere((x) => x.id == g.id).outcome,
      Outcome.draw,
    );
    expect(
      find.text(resultChangeText(g.board, Outcome.whiteWin, Outcome.draw)),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(
      c.event!.games.firstWhere((x) => x.id == g.id).outcome,
      Outcome.whiteWin,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a key that is not a result is answered, not ignored', (
    tester,
  ) async {
    final c = await posted(tester);
    addTearDown(c.dispose);
    final g = c.event!.sections.single.rounds.single.games.first;
    await mount(tester, c);
    await tapCell(tester, g, g.white);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('standing-key-hint')), findsOneWidget);
    expect(
      c.event!.games.firstWhere((x) => x.id == g.id).outcome,
      Outcome.unreported,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('standing-key-hint')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
