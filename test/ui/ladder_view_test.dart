import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';

void main() {
  testWidgets('record a challenge inline, confirm with Undo, no dialogs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture(count: 4, format: Format.ladder);
    addTearDown(c.dispose);
    final section = c.event!.sections.single;
    final [p0, p1, p2, p3] = section.players;
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) =>
                ResultsView(controller: c, sectionId: section.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ladder-table')), findsOneWidget);
    expect(find.text('Create pairings'), findsNothing);
    // Record is the only filled button, and it waits for a full challenge.
    expect(find.byType(FilledButton), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('ladder-record')))
          .onPressed,
      isNull,
    );

    await chooseOption(
      tester,
      find.byKey(const ValueKey('ladder-challenger')),
      '#4 ${c.event!.player(p3).name}',
    );
    await tester.tap(find.byKey(const ValueKey('ladder-defender')));
    await tester.pumpAndSettle();
    // Only the two places above are offered.
    expect(
      find.widgetWithText(MenuItemButton, '#1 ${c.event!.player(p0).name}'),
      findsNothing,
    );
    await tester.tap(
      find
          .widgetWithText(MenuItemButton, '#2 ${c.event!.player(p1).name}')
          .last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ladder-result-win')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ladder-record')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(c.event!.sections.single.players, [p0, p3, p1, p2]);
    expect(
      c.event!.sections.single.rounds.single.games.single.outcome,
      Outcome.blackWin,
    );
    expect(
      find.text('${c.event!.player(p3).name} moves to #2'),
      findsOneWidget,
    );
    expect(find.text('1–0 v. ${c.event!.player(p1).name}'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ladder-undo')));
    await tester.pumpAndSettle();
    expect(c.event!.sections.single.players, [p0, p1, p2, p3]);
    expect(c.event!.sections.single.rounds, isEmpty);
    expect(find.byKey(const ValueKey('ladder-undo')), findsNothing);
  });
}
