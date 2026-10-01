import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../support.dart';

void main() {
  testWidgets('Ctrl+L and the toolbar open a large docked lookup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final g = c.event!.games.first;
    final white = c.event!.player(g.white), black = c.event!.player(g.black);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Workspace(
          controller: c,
          path: ':memory:',
          onClose: () {},
          onTheme: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lookup-panel')), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('lookup-query')),
      white.name.toLowerCase(),
    );
    await tester.pump();
    final answer = find.text('Board ${g.board} · White vs ${black.name}');
    expect(answer, findsOneWidget);
    expect(tester.getSize(answer).height, greaterThanOrEqualTo(24));
    // The toolbar button closes it again.
    await tester.tap(find.byTooltip('Find player (Ctrl+L)'));
    await tester.pump();
    expect(find.byKey(const ValueKey('lookup-panel')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a walk-up joins the section on screen when added', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture();
    addTearDown(c.dispose);
    final q2 = c.event!.sections.last;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => PlayersView(controller: c, sectionId: q2.id),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add player'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('panel-name')),
      'Late Kid',
    );
    await tester.tap(find.text('Add'));
    await tester.pump();
    final kid = c.event!.players.last;
    expect(kid.name, 'Late Kid');
    expect(c.event!.sectionOf(kid.id)?.id, q2.id);
    expect(
      find.text(
        'Added Late Kid to ${q2.name}. Enter the next player, or close.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
