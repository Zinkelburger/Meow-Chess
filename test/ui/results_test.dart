import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';
import 'package:meow_chess/ui/overview.dart';

void main() {
  testWidgets('player inspector saves an edit before opening its bye action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture();
    addTearDown(c.dispose);
    final player = c.event!.players.first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editPlayer(context, c, player: player),
              child: const Text('Inspect player'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Inspect player'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('field-name')),
      'Reviewed Player',
    );
    await tester.tap(find.text('Save & byes'));
    await tester.pumpAndSettle();
    expect(c.event!.player(player.id).name, 'Reviewed Player');
    expect(find.text('Byes · Reviewed Player'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('field-round')), '2');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.event!.player(player.id).byes[2], 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
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
  testWidgets('event overview and results remain usable at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture(count: 22);
    addTearDown(c.dispose);
    Widget host(Widget child) => MaterialApp(
      theme: meowTheme(Brightness.dark),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(1280, 900),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(body: child),
      ),
    );
    await tester.pumpWidget(
      host(
        EventOverview(
          controller: c,
          onPlayers: () {},
          onCheckIn: () {},
          onQuads: () {},
          onPost: () {},
          onResults: () {},
          onReports: () {},
          onSection: (_) {},
          onSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    c.post((await tester.runAsync(() => c.propose()))!);
    await tester.pumpWidget(host(ResultsView(controller: c)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
