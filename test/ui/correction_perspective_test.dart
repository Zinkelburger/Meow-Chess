// The correction panel's result keys score the player whose box it was
// opened from, as the grid's keys do.
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

Future<void> mount(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(body: DockHost(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump();
}

/// The result [o] is the one picked in the open correction panel.
void expectChosen(WidgetTester tester, Outcome o) => expect(
  tester.getSemantics(find.byKey(ValueKey('correction-${o.name}'))),
  isSemantics(isChecked: true),
  reason: '${o.name} should be the chosen result',
);

void main() {
  Outcome outcome(TournamentController c, String id) =>
      c.event!.games.firstWhere((g) => g.id == id).outcome;

  testWidgets("F2 from Black's box: 1 is Black's win, 0 Black's loss", (
    tester,
  ) async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final g = c.event!.games.first;
    c.recordResult(g.id, Outcome.draw);
    await mount(
      tester,
      ListenableBuilder(
        listenable: c,
        builder: (_, _) => ResultsView(controller: c),
      ),
    );
    await tester.tap(find.byKey(ValueKey('score-${g.id}-b')));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('result-correction-review')),
      findsOneWidget,
    );
    final black = c.event!.player(g.black).name;
    expect(find.text('Keys score $black'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.digit1);
    expectChosen(tester, Outcome.blackWin);
    await press(tester, LogicalKeyboardKey.digit0);
    expectChosen(tester, Outcome.whiteWin);
    await press(tester, LogicalKeyboardKey.digit1);
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(outcome(c, g.id), Outcome.blackWin);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("F2 from White's box scores White and adds no perspective line", (
    tester,
  ) async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final g = c.event!.games.first;
    c.recordResult(g.id, Outcome.draw);
    await mount(
      tester,
      ListenableBuilder(
        listenable: c,
        builder: (_, _) => ResultsView(controller: c),
      ),
    );
    await tester.tap(find.byKey(ValueKey('score-${g.id}-w')));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('correction-perspective')), findsNothing);
    await press(tester, LogicalKeyboardKey.digit1);
    expectChosen(tester, Outcome.whiteWin);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a key typed in Black's box of a round with later rounds keeps "
      "scoring Black in the review", (tester) async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final first = c.event!.sections.single.rounds.single;
    for (final g in first.games) {
      c.recordResult(g.id, Outcome.draw);
    }
    c.post((await tester.runAsync(() => c.propose()))!);
    final g = first.games.first;
    await mount(
      tester,
      ListenableBuilder(
        listenable: c,
        builder: (_, _) => ResultsView(controller: c),
      ),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('correct-round')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('score-${g.id}-b')));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    // The typed result is preselected, and the keys still score Black.
    expectChosen(tester, Outcome.blackWin);
    expect(outcome(c, g.id), Outcome.draw);
    await press(tester, LogicalKeyboardKey.digit0);
    expectChosen(tester, Outcome.whiteWin);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the adjudication checkbox carries no rule number; the rule is '
      'in the explanation under it', (tester) async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final g = c.event!.games.first;
    c.recordResult(g.id, Outcome.whiteWin);
    await mount(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => openResultCorrection(context, c, g.id),
          child: const Text('Review'),
        ),
      ),
    );
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Adjudicated by the director'), findsOneWidget);
    expect(find.bySemanticsLabel('Adjudicated by the director'), findsWidgets);
    expect(find.textContaining('rule 18G'), findsOneWidget);
    expect(find.textContaining('ADJ'), findsOneWidget);
    // No row offers a key that is not one: X was a forfeit key once.
    await tester.tap(find.byKey(const ValueKey('correction-more')));
    await tester.pumpAndSettle();
    expect(find.text('X'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
