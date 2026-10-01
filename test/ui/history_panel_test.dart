import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../support.dart';

void main() {
  Future<void> mount(WidgetTester tester, TournamentController c) async {
    tester.view.physicalSize = const Size(1400, 900);
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
  }

  testWidgets('history panel reviews a step and restores it', (tester) async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final paired = c.graph.head!;
    final games = c.event!.games.toList();
    c.recordResult(games[0].id, Outcome.whiteWin);
    c.recordResult(games[1].id, Outcome.draw);
    await mount(tester, c);
    await tester.tap(find.byTooltip('History (Ctrl+H)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-graph')), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('history-$paired')));
    await tester.pumpAndSettle();
    expect(find.text('Recorded play affected'), findsOneWidget);
    expect(find.text('Quad 1 round 1: 2 results'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history-restore')));
    await tester.pumpAndSettle();
    // No confirmation: the panel already showed what is affected, and the
    // notice offers the way back.
    expect(c.graph.head, paired);
    expect(find.textContaining('Went back past recorded play'), findsOneWidget);
    expect(find.text('Go forward'), findsOneWidget);
    expect(c.event!.games.every((g) => g.outcome == Outcome.unreported), true);

    // Ctrl+Shift+Z steps forward along the line just left.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
    expect(c.event!.games.first.outcome, Outcome.whiteWin);

    // In the panel, the left arrow steps back like a move list.
    await tester.tap(find.byKey(ValueKey('history-${c.graph.head}')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(c.graph.head, paired);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
  testWidgets(
    'details stay under numbered operations and branches can reopen',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      final fork = c.graph.head!;
      c.reserveBye('p0', 3, 1);
      final first = c.graph.head!;
      c.reserveBye('p1', 3, 1);
      final tip = c.graph.head!;
      c.restore(fork);
      c.reserveBye('p2', 3, 1);
      final current = c.graph.head!;
      await mount(tester, c);
      await tester.tap(find.byTooltip('History (Ctrl+H)'));
      await tester.pumpAndSettle();
      expect(find.text('Player 02: Round 3 bye (0.5 pt)'), findsOneWidget);
      expect(find.text('Saved branch · 2 operations'), findsOneWidget);
      expect(find.byKey(ValueKey('history-$tip')), findsNothing);
      expect(find.byKey(ValueKey('history-details-$current')), findsNothing);

      await tester.tap(find.byKey(ValueKey('history-branch-$first')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('history-$tip')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('history-$tip')));
      await tester.pumpAndSettle();
      final details = find.byKey(ValueKey('history-details-$tip'));
      expect(find.text('Undo 1 operation'), findsOneWidget);
      expect(find.text('Apply 2 operations'), findsOneWidget);
      expect(
        find.descendant(of: details, matching: find.text('#$current')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: details, matching: find.text('#$first')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(details).dy,
        greaterThan(
          tester.getBottomLeft(find.byKey(ValueKey('history-$tip'))).dy - 1,
        ),
      );
      expect(find.text('THIS STEP'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('history-restore')));
      await tester.pumpAndSettle();
      expect(c.graph.head, tip);
      expect(c.event!.player('p0').byes[3], 1);
      expect(c.event!.player('p1').byes[3], 1);
      expect(c.event!.player('p2').byes, isEmpty);
      expect(find.byKey(ValueKey('history-branch-$current')), findsOneWidget);
      expect(c.graph.nodes.containsKey(current), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets(
    'keyboard review scrolls inline details and Escape collapses them',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      for (var i = 0; i < 24; i++) {
        c.savePlayer(c.event!.player('p0').copy(notes: 'Note $i'));
      }
      final current = c.graph.head!;
      await mount(tester, c);
      await tester.tap(find.byTooltip('History (Ctrl+H)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('history-$current')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 15; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      final selected = current - 15;
      expect(
        find.byKey(ValueKey('history-$selected')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('history-details-$selected')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('history-details-$selected')), findsNothing);
      expect(c.graph.head, current);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
}
