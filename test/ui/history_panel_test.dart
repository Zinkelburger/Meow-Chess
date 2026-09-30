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
    expect(find.text('Now'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('history-$paired')));
    await tester.pumpAndSettle();
    expect(find.text('RECORDED PLAY THAT WOULD BE REMOVED'), findsOneWidget);
    expect(find.text('•  Quad 1 round 1: 2 results'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history-restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go back anyway'));
    await tester.pumpAndSettle();
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

    // In the panel, the left arrow steps back like a move list.
    await tester.tap(find.byKey(ValueKey('history-${c.graph.head}')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(c.graph.head, paired);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
