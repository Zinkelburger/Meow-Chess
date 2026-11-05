// Large events stay as quick as small ones because the long lists build only
// what is on screen. Asserted as counts of built rows, not timings, which
// vary with the machine and are meaningless in debug mode.
import 'package:flutter/material.dart';
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
}
