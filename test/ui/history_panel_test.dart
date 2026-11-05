import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/history_panel.dart' show historyTime;
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
    expect(find.text('Now'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('history-$paired')));
    await tester.pumpAndSettle();
    // Consequences are listed before the button that commits them.
    expect(find.text('Removes recorded play'), findsOneWidget);
    expect(find.text('Quad 1 round 1: 2 results'), findsOneWidget);
    expect(find.text('Undoes 2 changes'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Removes recorded play')).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('history-restore'))).dy,
      ),
    );
    expect(find.byType(Dialog), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('history-restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('history-restore')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(c.graph.head, paired);
    expect(c.event!.games.every((g) => g.outcome == Outcome.unreported), true);

    // Ctrl+Shift+Z steps forward along the line just left.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
    expect(c.event!.games.first.outcome, Outcome.whiteWin);

    // Arrow keys only choose; the event moves on Enter.
    await tester.tap(find.byKey(ValueKey('history-${c.graph.head}')));
    await tester.pumpAndSettle();
    final head = c.graph.head;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(c.graph.head, head);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(c.graph.head, isNot(head));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
  testWidgets(
    'details stay under their change and undone changes can come back',
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
      expect(find.textContaining('2 undone changes, kept · '), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      expect(find.byKey(ValueKey('history-$tip')), findsNothing);
      expect(find.byKey(ValueKey('history-details-$current')), findsNothing);

      await tester.tap(find.byKey(ValueKey('history-branch-$first')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('history-$tip')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('history-$tip')));
      await tester.pumpAndSettle();
      final details = find.byKey(ValueKey('history-details-$tip'));
      expect(find.text('Undoes 1 change'), findsOneWidget);
      expect(find.text('Brings back 2 changes'), findsOneWidget);
      expect(
        find.descendant(
          of: details,
          matching: find.text('Player 02: Round 3 bye (0.5 pt)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: details,
          matching: find.text('Player 00: Round 3 bye (0.5 pt)'),
        ),
        findsOneWidget,
      );
      // No transaction numbers or git words reach the TD.
      final history = find.byKey(const ValueKey('history-graph'));
      for (final word in ['#', 'operation', 'branch', 'Transaction']) {
        expect(
          find.descendant(of: history, matching: find.textContaining(word)),
          findsNothing,
        );
      }
      expect(
        tester.getTopLeft(details).dy,
        greaterThan(
          tester.getBottomLeft(find.byKey(ValueKey('history-$tip'))).dy - 1,
        ),
      );
      expect(find.text('THIS STEP'), findsNothing);

      expect(find.text('Switch to this version'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('history-restore')));
      await tester.pumpAndSettle();
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

  testWidgets(
    'an Undo with consequences opens History on that step instead of a dialog',
    (tester) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      final id = c.event!.sections.first.id;
      c.post((await tester.runAsync(() => c.propose(sectionId: id)))!);
      for (final g in c.event!.sections.first.rounds.first.games) {
        c.recordResult(g.id, Outcome.whiteWin);
      }
      c.post((await tester.runAsync(() => c.propose(sectionId: id)))!);
      final game = c.event!.games.first;
      c.correctResult(c.reviewResult(game.id), Outcome.draw);
      final corrected = c.graph.head!, back = c.graph.back!;
      await mount(tester, c);
      expect(find.byKey(const ValueKey('history-graph')), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(c.graph.head, corrected);
      expect(find.byKey(ValueKey('history-details-$back')), findsOneWidget);
      expect(
        find.text('An earlier result changes while later rounds stay paired'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('history-restore')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-restore')));
      await tester.pumpAndSettle();
      expect(c.graph.head, back);
      expect(c.event!.games.first.outcome, Outcome.whiteWin);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  group('going back by recovery point', () {
    testWidgets(
      'a recovery point selects its version, then Return to latest comes back',
      (tester) async {
        final c = fixture(format: Format.swiss);
        addTearDown(c.dispose);
        c.post((await tester.runAsync(() => c.propose()))!);
        for (final g in c.event!.games) {
          c.recordResult(g.id, Outcome.draw);
        }
        final newest = c.graph.head;
        await mount(tester, c);
        await tester.tap(find.byTooltip('History (Ctrl+H)'));
        await tester.pumpAndSettle();
        final point = c.recoveryPoints().firstWhere(
          (p) => p.mark.title == 'Before round 1 pairings',
        );
        expect(find.text('Recovery points (2)'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('history-points')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('history-earlier')), findsNothing);
        await tester.tap(
          find.byKey(
            ValueKey('history-point-${point.node}-${point.mark.title}'),
          ),
        );
        await tester.pumpAndSettle();
        // Choosing only shows the version: what it holds and what it removes.
        expect(c.graph.head, newest);
        expect(find.text('At this point'), findsOneWidget);
        expect(find.text('Quad 1: not paired yet'), findsOneWidget);
        expect(find.text('Removes recorded play'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('history-restore')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('history-restore')));
        await tester.pumpAndSettle();
        expect(c.graph.head, point.node);
        expect(c.event!.sections.every((s) => s.rounds.isEmpty), isTrue);

        // The newest version is one press away, from the top of History.
        await tester.drag(
          find.byKey(const ValueKey('history-graph')),
          const Offset(0, 2000),
        );
        await tester.pumpAndSettle();
        expect(find.text('The event is on an earlier version'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('history-return')));
        await tester.pumpAndSettle();
        expect(c.graph.head, newest);
        expect(c.event!.games.every((g) => g.outcome == Outcome.draw), isTrue);
        expect(find.byKey(const ValueKey('history-earlier')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets('the status line says what Undo did and offers Redo', (
      tester,
    ) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final game = c.event!.games.first;
      c.recordResult(game.id, Outcome.whiteWin);
      await mount(tester, c);
      expect(find.byKey(const ValueKey('status-moved')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('undo')));
      await tester.pumpAndSettle();
      expect(c.event!.games.first.outcome, Outcome.unreported);
      final moved = tester.widget<Text>(
        find.byKey(const ValueKey('status-moved')),
      );
      expect(moved.data, startsWith('Undid: '));
      expect(moved.data, contains('1–0'));
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.byKey(const ValueKey('status-move-back')));
      await tester.pumpAndSettle();
      expect(c.event!.games.first.outcome, Outcome.whiteWin);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('status-moved'))).data,
        startsWith('Redid: '),
      );
      // The next change ends the report.
      c.recordResult(c.event!.games.last.id, Outcome.draw);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('status-moved')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('undone groups say when their work was done', (tester) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final [a, b, ...] = c.event!.games.toList();
      c.recordResult(a.id, Outcome.whiteWin);
      c.undo();
      c.recordResult(b.id, Outcome.draw);
      await mount(tester, c);
      await tester.tap(find.byTooltip('History (Ctrl+H)'));
      await tester.pumpAndSettle();
      final time = historyTime(
        c.graph.nodes[c.graph.branches.values.single.single]!.timestamp,
      );
      expect(find.text('1 undone change, kept · $time'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('history-keys')),
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('history-graph')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.textContaining('Ctrl+Z undo'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
