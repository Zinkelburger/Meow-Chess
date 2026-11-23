import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';
import 'dock_host.dart';

Future<void> mount(WidgetTester tester, TournamentController c) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: DockHost(
          child: ListenableBuilder(
            listenable: c,
            builder: (_, _) => ResultsView(controller: c),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String legend(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('result-key-legend'))).data!;

void main() {
  testWidgets('F marks and unmarks a no-show; 1, 0 and D enter a played '
      'game on a forfeit board too', (tester) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await mount(tester, c);
    final g = c.event!.sections.first.rounds.last.games.first;
    Outcome outcome() => c.event!.games.firstWhere((x) => x.id == g.id).outcome;
    Future<void> type(bool white, LogicalKeyboardKey key) async {
      await tester.tap(
        find.byKey(ValueKey('score-${g.id}-${white ? 'w' : 'b'}')),
      );
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(legend(tester), contains('F on both: double forfeit'));
    await type(true, LogicalKeyboardKey.keyF);
    expect(outcome(), Outcome.blackForfeit);
    await type(false, LogicalKeyboardKey.keyF);
    expect(outcome(), Outcome.doubleForfeit);
    // Focus back on the board: the legend says what the keys do there.
    await tester.tap(find.byKey(ValueKey('score-${g.id}-b')));
    await tester.pump();
    expect(legend(tester), startsWith('Double forfeit'));
    // F again takes that player's no-show back: White's still stands.
    await type(false, LogicalKeyboardKey.keyF);
    expect(outcome(), Outcome.blackForfeit);
    await tester.tap(find.byKey(ValueKey('score-${g.id}-w')));
    await tester.pump();
    expect(legend(tester), startsWith('No-show · F takes it back'));
    // 1 is always a played win, never a forfeit win.
    await type(false, LogicalKeyboardKey.digit1);
    expect(outcome(), Outcome.blackWin);
    await type(true, LogicalKeyboardKey.keyF);
    expect(outcome(), Outcome.blackForfeit);
    await type(false, LogicalKeyboardKey.digit0);
    expect(outcome(), Outcome.whiteWin);
    await type(true, LogicalKeyboardKey.keyF);
    await type(true, LogicalKeyboardKey.keyD);
    expect(outcome(), Outcome.draw);
    // F on the only absent player leaves the board with no result.
    await type(true, LogicalKeyboardKey.keyF);
    expect(outcome(), Outcome.blackForfeit);
    await type(true, LogicalKeyboardKey.keyF);
    expect(outcome(), Outcome.unreported);
    await type(true, LogicalKeyboardKey.digit1);
    expect(outcome(), Outcome.whiteWin);
    // X is not a forfeit key any more.
    await type(true, LogicalKeyboardKey.keyX);
    expect(outcome(), Outcome.whiteWin);
    expect(legend(tester), startsWith('Not a result key'));
  });

  testWidgets('screen readers hear forfeits in words', (tester) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final g = c.event!.sections.first.rounds.last.games.first;
    c.recordResult(g.id, Outcome.whiteForfeit);
    await mount(tester, c);
    final white = c.event!.player(g.white).name;
    final black = c.event!.player(g.black).name;
    expect(
      find.bySemanticsLabel(RegExp("^$white's score: won by forfeit")),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp("^$black's score: forfeited")),
      findsOneWidget,
    );
  });
}
