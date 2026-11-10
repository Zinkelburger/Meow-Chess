// After a withdrawal once pairings are posted, the boards that have not
// started are paired again from the Pairings page, beside the boards and
// without a dialog. A forfeit's withdraw offer uses the app's one phrasing.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';
import 'dock_host.dart';

Future<void> mount(
  WidgetTester tester,
  TournamentController c, {
  String? sectionId,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: DockHost(
          child: ListenableBuilder(
            listenable: c,
            builder: (_, _) => ResultsView(controller: c, sectionId: sectionId),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Eight players in one Swiss section, round 1 played, round 2 posted.
Future<TournamentController> secondRound(WidgetTester tester) async {
  final c = TournamentController(SqliteEventRepository(':memory:'));
  addTearDown(c.dispose);
  c.create('Club Open');
  c.importPlayers([
    for (var i = 0; i < 8; i++)
      Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 50),
  ]);
  c.addSection('Open', Format.swiss, 4);
  c.post((await tester.runAsync(() => c.propose()))!);
  for (final g in c.event!.sections.single.rounds.single.games) {
    c.recordResult(g.id, Outcome.whiteWin);
  }
  c.post((await tester.runAsync(() => c.propose()))!);
  return c;
}

List<Game> boards(TournamentController c) =>
    [...c.event!.sections.single.rounds.last.games]
      ..sort((a, b) => a.board.compareTo(b.board));

void main() {
  final toolbar = find.byKey(const ValueKey('repair-unstarted'));
  final apply = find.byKey(const ValueKey('apply-repair'));

  testWidgets('a withdrawn player on a waiting board is pointed out, and the '
      'boards not started are paired again with a reason', (tester) async {
    final c = await secondRound(tester);
    final section = c.event!.sections.single;
    final before = boards(c);
    await mount(tester, c, sectionId: section.id);
    // Offered beside Edit pairings as soon as the round is posted.
    expect(find.byKey(const ValueKey('edit-pairings')), findsOneWidget);
    expect(tester.widget<TextButton>(toolbar).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('repair-notice')), findsNothing);

    // One result in: swapping is over, re-pairing the rest is not.
    c.recordResult(before[0].id, Outcome.draw);
    final gone = c.event!.player(before[2].white);
    c.setWithdrawn([gone.id], true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-pairings')), findsNothing);
    expect(tester.widget<TextButton>(toolbar).onPressed, isNotNull);
    expect(
      find.text('${gone.name} withdrew but is still on board 3.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('repair-notice-action')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('repair-panel')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('repair-summary'))).data,
      startsWith(
        'Boards with a result or already started are kept. The 3 boards '
        'not started are paired again, without withdrawn players.',
      ),
    );
    // The reason starts as the withdrawal and is the director's to change.
    final reason = find.byKey(const ValueKey('repair-reason'));
    expect(
      tester.widget<TextField>(reason).controller!.text,
      '${gone.name} withdrew',
    );
    expect(find.widgetWithText(FilledButton, 'Re-pair 3 boards'), findsOne);
    // Exactly one filled button in the panel: the commit.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('repair-panel')),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );

    // Board 2 has started without a result yet: it is kept.
    await tester.tap(find.byKey(const ValueKey('repair-started-2')));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Re-pair 2 boards'), findsOne);

    // A reason is required, and its absence is said in words.
    await tester.enterText(reason, '  ');
    await tester.pump();
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    expect(find.text('Say why the pairings are changing.'), findsOne);
    await tester.enterText(reason, 'Left ill');
    await tester.pump();
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    final round = c.event!.sections.single.rounds.last;
    expect(round.note, 'Left ill');
    expect(c.graph.nodes[c.graph.head]!.action, contains('Re-pair round 2'));
    Game board(int n) => round.games.firstWhere((g) => g.board == n);
    // The board with a result and the board ticked as started are as they
    // were; nobody is paired against the player who left.
    expect(board(1).id, before[0].id);
    expect(board(1).outcome, Outcome.draw);
    expect(board(2).id, before[1].id);
    expect(
      round.games.any((g) => g.white == gone.id || g.black == gone.id),
      isFalse,
    );
    expect(find.byKey(const ValueKey('repair-saved')), findsOneWidget);
    expect(find.text('Round 2 re-paired'), findsOneWidget);
    expect(find.textContaining('2 boards were kept'), findsOneWidget);
    expect(find.textContaining('Reprint the pairings'), findsOneWidget);
    expect(find.byKey(const ValueKey('repair-notice')), findsNothing);

    // Undo in the panel puts the posted pairing back.
    await tester.tap(find.byKey(const ValueKey('repair-undo')));
    await tester.pumpAndSettle();
    expect(boards(c).map((g) => g.id), before.map((g) => g.id));
    expect(find.byKey(const ValueKey('repair-panel')), findsOneWidget);
    expect(tester.widget<TextField>(reason).controller!.text, 'Left ill');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the engine\'s refusal is shown in the panel in plain words', (
    tester,
  ) async {
    final c = await secondRound(tester);
    final section = c.event!.sections.single;
    await mount(tester, c, sectionId: section.id);
    await tester.tap(toolbar);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('repair-reason')),
      'Late change',
    );
    await tester.pump();
    // A result arrives on a board while the panel still lists it: the
    // panel follows, and the count drops.
    expect(find.widgetWithText(FilledButton, 'Re-pair 4 boards'), findsOne);
    c.recordResult(boards(c).first.id, Outcome.whiteWin);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Re-pair 3 boards'), findsOne);
    // Every waiting board ticked as started leaves nothing to do.
    for (final n in [2, 3, 4]) {
      final tick = find.byKey(ValueKey('repair-started-$n'));
      await tester.ensureVisible(tick);
      await tester.tap(tick);
      await tester.pump();
    }
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    expect(
      find.text('Every board is kept, so there is nothing to pair again.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('it is offered only where it can do something', (tester) async {
    final c = await secondRound(tester);
    final section = c.event!.sections.single;
    await mount(tester, c, sectionId: section.id);
    // An earlier round: not offered.
    await tester.tap(find.widgetWithText(ChoiceChip, '1'));
    await tester.pumpAndSettle();
    expect(toolbar, findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '2'));
    await tester.pumpAndSettle();
    expect(toolbar, findsOneWidget);
    // Every board has a result: it stays in place, unavailable.
    for (final g in boards(c)) {
      c.recordResult(g.id, Outcome.draw);
    }
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(toolbar).onPressed, isNull);
    // Every section at once: not offered.
    await mount(tester, c);
    expect(toolbar, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('withdrawing a no-show uses the same words as everywhere else '
      'and is named in History', (tester) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final game = c.event!.games.first;
    await mount(tester, c);
    await tester.tap(find.byKey(ValueKey('score-${game.id}-b')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    final withdraw = find.byKey(ValueKey('withdraw-${game.id}-${game.black}'));
    expect(
      find.descendant(
        of: withdraw,
        matching: find.text('Withdraw after round 1'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('future rounds'), findsNothing);
    await tester.tap(withdraw);
    await tester.pumpAndSettle();
    final name = c.event!.player(game.black).name;
    expect(c.event!.player(game.black).withdrawn, isTrue);
    expect(c.graph.nodes[c.graph.head]!.action, 'Withdraw $name');
    await tester.pumpWidget(const SizedBox());
  });
}
