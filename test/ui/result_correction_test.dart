import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/result_correction_panel.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../support.dart';
import 'dock_host.dart';

Future<void> prepare(WidgetTester tester, TournamentController c) async {
  final id = c.event!.sections.first.id;
  c.post((await tester.runAsync(() => c.propose(sectionId: id)))!);
  for (final g in c.event!.sections.first.rounds.first.games) {
    c.recordResult(g.id, Outcome.whiteWin);
  }
  c.post((await tester.runAsync(() => c.propose(sectionId: id)))!);
}

Future<void> mount(
  WidgetTester tester,
  TournamentController c,
  Widget Function() view, {
  Size size = const Size(1400, 1000),
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: DockHost(
          child: ListenableBuilder(listenable: c, builder: (_, _) => view()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget opener(TournamentController c, String gameId, {Outcome? outcome}) =>
    Builder(
      builder: (context) => TextButton(
        onPressed: () =>
            openResultCorrection(context, c, gameId, outcome: outcome),
        child: const Text('Review'),
      ),
    );

final panel = find.byKey(const ValueKey('result-correction-review'));
final save = find.byKey(const ValueKey('apply-correction'));
bool canSave(WidgetTester tester) =>
    tester.widget<FilledButton>(save).onPressed != null;

void main() {
  testWidgets('all rounds opens the correction beside the table; closing '
      'changes nothing and keeps the draft', (tester) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await prepare(tester, c);
    final section = c.event!.sections.first;
    await mount(
      tester,
      c,
      () => ResultsView(controller: c, sectionId: section.id),
    );
    await tester.tap(find.byKey(const ValueKey('all-rounds')));
    await tester.pumpAndSettle();
    for (final r in section.rounds) {
      for (final g in r.games) {
        expect(find.byKey(ValueKey('game-${g.id}')), findsOneWidget);
      }
    }
    final first = section.rounds.first.games.first;
    final second = section.rounds.last.games.first;
    expect(
      tester.getTopLeft(find.byKey(ValueKey('game-${first.id}'))).dy,
      lessThan(tester.getTopLeft(find.byKey(ValueKey('game-${second.id}'))).dy),
    );
    final before = c.event!.encode();
    await tester.tap(find.byKey(const ValueKey('correct-round')));
    await tester.tap(find.byKey(ValueKey('score-${first.id}-w')));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(c.event!.encode(), before);
    // The table stays usable beside the panel.
    expect(
      find.byKey(ValueKey('game-${second.id}')).hitTestable(),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('reopen-round-2')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('result-reason')),
      'Changed mind',
    );
    await tester.pumpAndSettle();
    // Save says why it is unavailable instead of greying out silently.
    expect(canSave(tester), isFalse);
    expect(find.textContaining('Confirm that no game'), findsOneWidget);

    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(c.event!.encode(), before);

    // Reopening the same game brings the draft back.
    await tester.tap(find.byKey(ValueKey('score-${first.id}-w')));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pumpAndSettle();
    expect(find.text('Changed mind'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'unpairing later rounds needs the unstarted confirmation; a note is optional',
    (tester) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      await prepare(tester, c);
      final game = c.event!.games.first;
      await mount(tester, c, () => opener(c, game.id, outcome: Outcome.draw));
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(canSave(tester), isTrue);
      expect(find.byKey(const ValueKey('correction-score-change')), findsOne);
      await tester.tap(find.byKey(const ValueKey('reopen-round-2')));
      await tester.pumpAndSettle();
      expect(canSave(tester), isFalse);
      await tester.tap(find.byKey(const ValueKey('confirm-unstarted')));
      await tester.pumpAndSettle();
      expect(find.text('Save and unpair from round 2'), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(c.event!.sections.first.rounds.length, 1);
      expect(c.event!.games.first.outcome, Outcome.draw);
      expect(find.byKey(const ValueKey('correction-saved')), findsOneWidget);
      expect(find.textContaining('is now ½–½ (was 1–0)'), findsOneWidget);

      // Undo in the confirmation puts the event and the form back.
      await tester.tap(find.byKey(const ValueKey('correction-undo')));
      await tester.pumpAndSettle();
      expect(c.event!.sections.first.rounds.length, 2);
      expect(c.event!.games.first.outcome, Outcome.whiteWin);
      expect(panel, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('results are buttons as well as keys', (tester) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await prepare(tester, c);
    final game = c.event!.games.first;
    final white = c.event!.player(game.white).name;
    final black = c.event!.player(game.black).name;
    await mount(tester, c, () => opener(c, game.id));
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Recorded'), findsOneWidget);
    expect(canSave(tester), isFalse);
    expect(find.textContaining('different from the recorded'), findsOneWidget);
    await tester.tap(find.text('$black won'));
    await tester.pumpAndSettle();
    expect(canSave(tester), isTrue);
    // Forfeits sit behind one disclosure; their keys still work. F marks
    // White absent, then 1 gives White the forfeit win instead.
    expect(find.text('$black wins by forfeit'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect(find.text('$black wins by forfeit'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    expect(find.text('$white wins by forfeit'), findsOneWidget);
    // A forfeit is never drawn.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
    expect(c.event!.games.first.outcome, Outcome.whiteForfeit);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'entry result opens the correction; result keys do not write behind it',
    (tester) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      await prepare(tester, c);
      final game = c.event!.games.first;
      await mount(
        tester,
        c,
        () => PlayersView(
          controller: c,
          sectionId: c.event!.sections.first.id,
          standingsOnly: true,
        ),
      );
      final before = c.event!.encode();
      await tester.tap(
        find.byKey(ValueKey('standing-score-${game.id}-${game.black}')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pumpAndSettle();
      expect(c.event!.encode(), before);
      expect(
        find.descendant(
          of: panel,
          matching: find.text('Correct board ${game.board}'),
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(c.event!.encode(), before);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'history fixes a selected result without undoing later player edits',
    (tester) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final game = c.event!.games.first;
      c.recordResult(game.id, Outcome.whiteWin);
      final resultNode = c.graph.head!;
      c.savePlayer(c.event!.player('p0').copy(notes: 'Retain this'));
      tester.view.physicalSize = const Size(1400, 1000);
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
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('History (Ctrl+H)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('history-$resultNode')));
      await tester.pumpAndSettle();
      expect(find.textContaining('→'), findsWidgets);
      await tester.ensureVisible(
        find.byKey(const ValueKey('history-undo-result')),
      );
      await tester.tap(find.byKey(const ValueKey('history-undo-result')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-graph')), findsNothing);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(c.event!.games.first.outcome, Outcome.unreported);
      expect(c.event!.player('p0').notes, 'Retain this');
      expect(c.graph.nodes.containsKey(resultNode), true);
      // Done returns to History.
      await tester.tap(find.byKey(const ValueKey('correction-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-graph')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets('correction fits narrow windows at double text size', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await prepare(tester, c);
    for (final brightness in Brightness.values) {
      await mount(
        tester,
        c,
        () => opener(c, c.event!.games.first.id, outcome: Outcome.draw),
        size: const Size(900, 650),
        textScale: 2,
        brightness: brightness,
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('result-reason')));
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    }
  });
}
