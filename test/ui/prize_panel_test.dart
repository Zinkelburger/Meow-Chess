import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/prizes.dart';
import 'package:meow_chess/ui/prize_panel.dart';
import 'package:meow_chess/ui/theme.dart';

import '../support.dart';

void main() {
  testWidgets('prize rows edit in place, apply at once and undo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture();
    final section = c.event!.sections.first;
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: PrizeTablePanel(
                controller: c,
                sectionId: section.id,
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    PrizeTable table() => PrizeTable.fromJson(c.event!.sections.first.prizes);
    expect(find.text('No prizes yet.'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);

    await tester.tap(find.byKey(const ValueKey('add-prize')));
    await tester.pumpAndSettle();
    expect(table().list, hasLength(1));
    expect(c.graph.nodes[c.graph.head]!.action, 'Edit prizes for Quad 1');
    final id = table().list.single.id;

    await tester.enterText(find.byKey(ValueKey('prize-cents-$id')), '150');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(table().list.single.cents, 15000);
    expect(find.text('1 prize · \$150 in cash'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('prize-trophy-$id')));
    await tester.pumpAndSettle();
    expect(table().list.single.trophy, isTrue);

    await chooseOption(tester, find.byKey(ValueKey('prize-kind-$id')), 'Under');
    expect(table().list.single.kind, PrizeKind.under);
    await tester.enterText(find.byKey(ValueKey('prize-max-$id')), '1800');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(table().list.single.max, 1800);
    expect(table().list.single.title, '1st Under 1800');

    // A bad amount stays in the panel; the saved table is untouched.
    await tester.enterText(find.byKey(ValueKey('prize-cents-$id')), 'lots');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prize-error')), findsOneWidget);
    expect(table().list.single.cents, 15000);

    c.undo();
    await tester.pumpAndSettle();
    expect(table().list.single.max, 0);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(ValueKey('prize-max-$id')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '',
    );

    await tester.tap(find.byKey(ValueKey('remove-prize-$id')));
    await tester.pumpAndSettle();
    expect(table().list, isEmpty);
  });

  testWidgets('a value typed into a prize field survives closing the panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture();
    final section = c.event!.sections.first;
    final open = ValueNotifier(true);
    addTearDown(open.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: open,
            builder: (context, shown, _) => shown
                ? Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 400,
                      child: PrizeTablePanel(
                        controller: c,
                        sectionId: section.id,
                        onClose: () => open.value = false,
                      ),
                    ),
                  )
                : const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('prize-fund')), '250');
    // Closed while the field still has focus: no Enter, no blur first.
    open.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(PrizeTablePanel), findsNothing);
    expect(
      PrizeTable.fromJson(c.event!.sections.first.prizes).fundCents,
      25000,
    );
  });
}
