import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/result_correction_panel.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';
import 'dock_host.dart';

Future<void> mount(
  WidgetTester tester,
  TournamentController c,
  Widget Function() view,
) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: DockHost(
          child: ListenableBuilder(listenable: c, builder: (_, _) => view()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ResultsViewState state(WidgetTester tester) =>
    tester.state<ResultsViewState>(find.byType(ResultsView));

String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
String box(String gameId, {bool white = true}) =>
    'score $gameId ${white ? 'white' : 'black'}';

/// Whether keyboard focus is on a board row (a score box or a name).
bool inGrid() {
  var inside = false;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
    final key = e.widget.key;
    if (key is ValueKey && '${key.value}'.startsWith('game-')) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'missing only: a skipped board does not pull focus back; the next board '
    'in the event-wide order gets it',
    (tester) async {
      final c = fixture(count: 12, format: Format.swiss);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      await mount(tester, c, () => ResultsView(controller: c));
      await tester.tap(find.text('Missing only'));
      await tester.pump();
      final rows = state(tester).visibleRows();
      final order = [for (final r in rows) r.game];
      expect(order.map((g) => g.board), [1, 2, 3, 4, 5, 6]);
      // Board 3 is in the next section; nothing earlier steals focus.
      expect(rows[2].section.id, isNot(rows[0].section.id));
      await tester.tap(find.byKey(ValueKey('score-${order[0].id}-w')));
      await tester.pump();
      await press(tester, LogicalKeyboardKey.enter);
      expect(focused(), box(order[1].id));
      await press(tester, LogicalKeyboardKey.keyW);
      expect(
        c.event!.games.firstWhere((g) => g.id == order[1].id).outcome,
        Outcome.whiteWin,
      );
      expect(focused(), box(order[2].id));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'after the last board focus wraps to a skipped one, then rests on '
    'All results entered so the next key changes nothing',
    (tester) async {
      final c = fixture(count: 12, format: Format.swiss);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      await mount(tester, c, () => ResultsView(controller: c));
      final order = [for (final r in state(tester).visibleRows()) r.game.id];
      await tester.tap(find.byKey(ValueKey('score-${order[0]}-b')));
      await tester.pump();
      await press(tester, LogicalKeyboardKey.enter);
      for (final id in order.skip(1)) {
        expect(focused(), box(id, white: false));
        await press(tester, LogicalKeyboardKey.digit1);
      }
      // The skipped first board, not the board just entered.
      expect(focused(), box(order[0], white: false));
      await press(tester, LogicalKeyboardKey.keyD);
      expect(c.event!.games.every((g) => g.outcome.resolved), isTrue);
      expect(find.byKey(const ValueKey('all-results-entered')), findsOneWidget);
      expect(focused(), 'all results entered');
      final before = c.event!.encode();
      await press(tester, LogicalKeyboardKey.digit0);
      expect(c.event!.encode(), before);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the grid is one Tab stop and Shift+Tab returns to the cell', (
    tester,
  ) async {
    final c = fixture(count: 12, format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await mount(tester, c, () => ResultsView(controller: c));
    final order = [for (final r in state(tester).visibleRows()) r.game.id];
    await tester.tap(find.byKey(ValueKey('score-${order[1]}-w')));
    await tester.pump();
    expect(focused(), box(order[1]));
    await press(tester, LogicalKeyboardKey.tab);
    expect(inGrid(), isFalse, reason: 'Tab leaves the grid in one press');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await press(tester, LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(focused(), box(order[1]), reason: 'returning restores the cell');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await press(tester, LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(inGrid(), isFalse, reason: 'Shift+Tab leaves it in one press');
    // Names stay available to screen readers.
    final white = c.event!.player(
      c.event!.games.firstWhere((g) => g.id == order[1]).white,
    );
    expect(find.bySemanticsLabel(RegExp(white.name)), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'legend and context line; a non-result key shows the keys and saves '
    'nothing; F2 opens the correction',
    (tester) async {
      final c = fixture(count: 8, format: Format.swiss);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      await mount(tester, c, () => ResultsView(controller: c));
      final legend = find.byKey(const ValueKey('result-key-legend'));
      expect(legend, findsOneWidget);
      expect(tester.widget<Text>(legend).data, contains('1 / W win'));
      final row = state(tester).visibleRows().first;
      final e = c.event!;
      await tester.tap(find.byKey(ValueKey('score-${row.game.id}-b')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('entry-context'))).data,
        '${row.section.name} · Round 1 · Board ${row.game.board} · '
        '${e.player(row.game.white).name} vs ${e.player(row.game.black).name}'
        " · entering Black's result",
      );
      final before = c.event!.encode();
      await press(tester, LogicalKeyboardKey.digit5);
      expect(c.event!.encode(), before);
      expect(focused(), box(row.game.id, white: false));
      expect(tester.widget<Text>(legend).data, startsWith('Not a result key'));
      expect(tester.widget<Text>(legend).data, contains('P playing'));
      await press(tester, LogicalKeyboardKey.keyL);
      expect(
        c.event!.games.firstWhere((g) => g.id == row.game.id).outcome,
        Outcome.whiteWin,
      );
      expect(tester.widget<Text>(legend).data, isNot(contains('Not a')));
      await tester.tap(find.byKey(ValueKey('score-${row.game.id}-b')));
      await tester.pump();
      await press(tester, LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('result-correction-review')),
        findsOneWidget,
      );
      expect(c.event!.encode(), isNot(before));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a fixed quad schedule does not make Swiss rounds read-only', (
    tester,
  ) async {
    final c = fixture(count: 8);
    addTearDown(c.dispose);
    final swiss = c.event!.sections.last;
    c.change(
      'One Swiss section',
      c.event!.copy(
        sections: [
          for (final s in c.event!.sections)
            s.id == swiss.id ? s.copy(format: Format.swiss) : s,
        ],
      ),
    );
    c.post((await tester.runAsync(() => c.propose(sectionId: swiss.id)))!);
    for (final g in c.event!.sections.last.rounds.single.games) {
      c.recordResult(g.id, Outcome.whiteWin);
    }
    c.post((await tester.runAsync(() => c.propose(sectionId: swiss.id)))!);
    await mount(tester, c, () => ResultsView(controller: c));
    final rows = state(tester).visibleRows();
    // The quad shows its whole schedule; the Swiss section its round 2.
    final quad = c.event!.sections.first.id;
    expect(
      rows.where((r) => r.section.id == quad).map((r) => r.round.number),
      containsAll([1, 2, 3]),
    );
    expect(
      rows.where((r) => r.section.id == swiss.id).map((r) => r.round.number),
      everyElement(2),
    );
    expect(find.byKey(const ValueKey('past-round-banner')), findsNothing);
    expect(find.byKey(const ValueKey('correct-round')), findsNothing);
    final game = c.event!.sections.last.rounds.last.games.first;
    await tester.tap(find.byKey(ValueKey('score-${game.id}-w')));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.digit1);
    expect(
      c.event!.games.firstWhere((g) => g.id == game.id).outcome,
      Outcome.whiteWin,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a game still playing shows its pairing assumption', (
    tester,
  ) async {
    final c = fixture(count: 8, format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final g = c.event!.games.first;
    c.recordResult(g.id, Outcome.unfinished);
    c.setPairingAssumption(g.id, Outcome.whiteWin, 'Long endgame');
    await mount(tester, c, () => ResultsView(controller: c));
    final white = find.byKey(ValueKey('score-${g.id}-w'));
    final black = find.byKey(ValueKey('score-${g.id}-b'));
    expect(find.descendant(of: white, matching: find.text('(1)')), findsOne);
    expect(find.descendant(of: black, matching: find.text('(0)')), findsOne);
    expect(
      find.descendant(of: white, matching: find.text('playing')),
      findsOne,
    );
    expect(
      find.bySemanticsLabel(RegExp('still playing, assumed 1 for pairing')),
      findsOne,
    );
    await tester.pumpWidget(const SizedBox());
  });

  group('correction panel', () {
    Future<String> open(
      WidgetTester tester,
      TournamentController c, {
      Outcome? outcome,
    }) async {
      c.post((await tester.runAsync(() => c.propose()))!);
      final g = c.event!.games.first;
      c.recordResult(g.id, Outcome.whiteWin);
      await mount(
        tester,
        c,
        () => Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                openResultCorrection(context, c, g.id, outcome: outcome),
            child: const Text('Review'),
          ),
        ),
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      return g.id;
    }

    Outcome outcomeOf(TournamentController c, String id) =>
        c.event!.games.firstWhere((g) => g.id == id).outcome;

    testWidgets('Undo disappears once another change lands after saving', (
      tester,
    ) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      final id = await open(tester, c, outcome: Outcome.draw);
      await tester.tap(find.byKey(const ValueKey('apply-correction')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('correction-undo')), findsOneWidget);
      c.recordResult(c.event!.games.last.id, Outcome.draw);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('correction-undo')), findsNothing);
      expect(outcomeOf(c, id), Outcome.draw);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('F on a forfeit win picks double forfeit', (tester) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      final id = await open(tester, c, outcome: Outcome.whiteForfeit);
      await press(tester, LogicalKeyboardKey.keyF);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcomeOf(c, id), Outcome.doubleForfeit);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('holding Enter saves once and does not press Done', (
      tester,
    ) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      final id = await open(tester, c, outcome: Outcome.draw);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('correction-saved')), findsOneWidget);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('correction-saved')), findsOneWidget);
      expect(outcomeOf(c, id), Outcome.draw);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Enter in the note saves; Shift+Enter does not', (
      tester,
    ) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      final id = await open(tester, c, outcome: Outcome.draw);
      final note = find.byKey(const ValueKey('result-reason'));
      await tester.ensureVisible(note);
      await tester.enterText(note, 'Scoresheet');
      await tester.pump();
      expect(find.text('Enter to save · Shift+Enter for a new line'), findsOne);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(outcomeOf(c, id), Outcome.whiteWin);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcomeOf(c, id), Outcome.draw);
      expect(find.byKey(const ValueKey('correction-saved')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
