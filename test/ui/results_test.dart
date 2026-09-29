import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';

void main() {
  testWidgets(
    '1/0/5 commit and advance once; key repeat and search cannot enter results',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixture(count: 12);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final games = c.event!.games.toList();
      await tester.pumpWidget(
        MaterialApp(
          theme: meowTheme(Brightness.dark),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => ResultsView(controller: c),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(ValueKey('game-${games[0].id}')));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit1);
      await tester.pump();
      expect(c.event!.games.where((g) => g.outcome.resolved).length, 1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pump();
      expect(c.event!.games.take(3).map((g) => g.outcome), [
        Outcome.whiteWin,
        Outcome.blackWin,
        Outcome.draw,
      ]);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '1');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.pump();
      expect(c.event!.games.where((g) => g.outcome.resolved).length, 3);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
  testWidgets(
    'missing-only traversal does not skip rows and one undo restores one board',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixture();
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final games = c.event!.games.toList();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => ResultsView(controller: c),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Missing only'));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('game-${games.first.id}')));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pump();
      expect(c.event!.games.take(2).map((g) => g.outcome), [
        Outcome.blackWin,
        Outcome.draw,
      ]);
      c.undo();
      await tester.pump();
      expect(c.event!.games.take(2).map((g) => g.outcome), [
        Outcome.blackWin,
        Outcome.unreported,
      ]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
  testWidgets('player name input never dispatches a result shortcut', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlayersView(controller: c)),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('player-search')), 'W015');
    await tester.pump();
    expect(c.event!.games.every((g) => !g.outcome.resolved), true);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
