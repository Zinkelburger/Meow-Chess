// Large events stay as quick as small ones because the long lists build only
// what is on screen. Asserted as counts of built rows, not timings, which
// vary with the machine and are meaningless in debug mode.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/workspace.dart';

int built(String prefix) => find
    .byWidgetPredicate(
      (w) =>
          w.key is ValueKey &&
          '${(w.key as ValueKey).value}'.startsWith(prefix),
      skipOffstage: false,
    )
    .evaluate()
    .length;

Future<TournamentController> mount(
  WidgetTester tester,
  int players, {
  Size window = const Size(1400, 900),
}) async {
  final c = TournamentController(SqliteEventRepository(':memory:'));
  addTearDown(c.dispose);
  c.create('Big Open');
  c.importPlayers([
    for (var i = 0; i < players; i++)
      Player(id: 'p$i', name: 'Player $i', rating: 2400 - i % 1800),
  ]);
  c.addSection('Open', Format.swiss, 5);
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Workspace(
        controller: c,
        path: ':memory:',
        onClose: () {},
        onTheme: () {},
      ),
    ),
  );
  await tester.pump();
  return c;
}

void main() {
  testWidgets('a roster of 2,000 builds only the rows on screen', (
    tester,
  ) async {
    await mount(tester, 2000);
    expect(built('player-p'), inInclusiveRange(1, 100));
    // Typing a search rebuilds the list from the filter, still lazily.
    await tester.enterText(find.byType(TextField).first, 'Player 1');
    await tester.pump();
    expect(built('player-p'), inInclusiveRange(1, 100));
    await tester.pumpWidget(const SizedBox());
  });

  // A window wide enough for boards beside standings. Narrower windows
  // stack the two in one scroll and still build every board: see
  // docs/TESTING.md, "Scale".
  testWidgets('a round of 500 boards builds only the boards on screen', (
    tester,
  ) async {
    final c = await mount(tester, 1000, window: const Size(1920, 1080));
    c.post((await tester.runAsync(() => c.propose()))!);
    await tester.tap(find.text('Pairings').first);
    await tester.pump();
    final boards = c.event!.sections.single.rounds.single.games.length;
    expect(boards, 500);
    expect(built('score-'), inInclusiveRange(1, 200));
    await tester.pumpWidget(const SizedBox());
  });

  // The lazy list drops rows scrolled away, but their focus nodes remember
  // the dropped row. Entering a result far down must still reach a board
  // skipped near the top, and the next key must land there.
  testWidgets('a result far down returns the cursor to a skipped board', (
    tester,
  ) async {
    final c = await mount(tester, 400, window: const Size(1920, 1080));
    c.post((await tester.runAsync(() => c.propose()))!);
    await tester.tap(find.text('Pairings').first);
    await tester.pump();
    final games = [...c.event!.sections.single.rounds.single.games]
      ..sort((a, b) => a.board.compareTo(b.board));
    final skipped = games[1], far = games[180];
    Finder box(Game g) => find.byKey(ValueKey('score-${g.id}-w'));
    expect(box(skipped), findsOneWidget);
    for (final g in games) {
      if (g != skipped && g != far) c.recordResult(g.id, Outcome.whiteWin);
    }
    await tester.pump();
    // Found once: the board it was found by scrolls away.
    final scrollable = tester.element(
      find.ancestor(of: box(skipped), matching: find.byType(Scrollable)).first,
    );
    final list = find.byElementPredicate((e) => identical(e, scrollable));
    await tester.dragUntilVisible(box(far), list, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(box(skipped), findsNothing);
    await tester.tap(box(far));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    expect(box(skipped), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'score ${skipped.id} white',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pumpAndSettle();
    final outcome = {for (final g in c.event!.games) g.id: g.outcome};
    expect(outcome[far.id], Outcome.whiteWin);
    expect(outcome[skipped.id], Outcome.blackWin);
    await tester.pumpWidget(const SizedBox());
  });
}
