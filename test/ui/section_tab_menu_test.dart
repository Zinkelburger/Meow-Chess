import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/section_panel.dart';

import '../support.dart';
import 'workspace_host.dart';

void main() {
  testWidgets(
    'the chosen tab has a named menu button that the keyboard opens',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      final [q1, q2] = c.event!.sections;
      await mountWorkspace(tester, c);

      // All sections is chosen at first: its menu holds the print commands.
      expect(find.byKey(const ValueKey('section-menu-all')), findsOneWidget);
      expect(find.byKey(ValueKey('section-menu-${q1.id}')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('section-menu-all')));
      await tester.pumpAndSettle();
      expect(menuItem('Print player list'), findsOneWidget);
      expect(menuItem('Preview player list…'), findsOneWidget);
      expect(menuItem('Print wall chart'), findsOneWidget);
      expect(menuItem('Delete section'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await pickTab(tester, q1.id);
      final button = find.byKey(ValueKey('section-menu-${q1.id}'));
      expect(button, findsOneWidget);
      expect(find.byKey(ValueKey('section-menu-${q2.id}')), findsNothing);
      expect(find.byTooltip('Section actions'), findsOneWidget);
      expect(find.bySemanticsLabel('${q1.name} actions'), findsOneWidget);

      // Tab reaches it; Enter opens the whole menu.
      await tabTo(tester, button);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      for (final item in [
        'Print player list',
        'Preview player list…',
        'Print wall chart',
        'Rename / section settings…',
        'Combine sections…',
        'How these pairings work',
        'Delete section',
      ]) {
        expect(menuItem(item), findsOneWidget, reason: item);
      }
      expect(menuItem('Pair a side game…'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(menuItem('Delete section'), findsNothing);

      // Down opens it too; arrows and Enter choose from it.
      await tabTo(tester, button);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(menuItem('Rename / section settings…'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(SectionSettingsPanel), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Shift+F10 and the Menu key open it from the focused tab itself.
      final chip = find.byKey(ValueKey('section-chip-${q1.id}'));
      await tabTo(tester, chip);
      await chord(
        tester,
        LogicalKeyboardKey.f10,
        modifier: LogicalKeyboardKey.shiftLeft,
      );
      expect(menuItem('Combine sections…'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tabTo(tester, chip);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(menuItem('Combine sections…'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets('a side-games tab offers Pair a side game', (tester) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    final first = c.event!.sections.first;
    c.change(
      'Side games',
      c.event!.copy(
        sections: [
          for (final s in c.event!.sections)
            s.id == first.id ? s.copy(sideGames: true) : s,
        ],
      ),
    );
    await mountWorkspace(tester, c);
    await tabMenu(tester, first.id, 'Pair a side game…');
    expect(find.byKey(const ValueKey('post-side-game')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (size, scale) in [
    (const Size(1024, 640), 1.0),
    (const Size(1024, 640), 2.0),
  ]) {
    testWidgets('the tab strip fits with its menu button at $size, ${scale}x', (
      tester,
    ) async {
      final c = fixture(count: 24, format: Format.swiss);
      addTearDown(c.dispose);
      final last = c.event!.sections.last;
      c.change(
        'Long name',
        c.event!.copy(
          sections: [
            for (final s in c.event!.sections)
              s.id == last.id
                  ? s.copy(name: 'Under 1200 Reserve and Novice Championship')
                  : s,
          ],
        ),
      );
      await mountWorkspace(tester, c, size: size, scale: scale);
      await pickTab(tester, last.id);
      expect(tester.takeException(), isNull);
      final menu = find.byKey(ValueKey('section-menu-${last.id}'));
      expect(menu, findsOneWidget);
      // The long name is cut short rather than widening the tab without end.
      final name = tester.getSize(
        find.descendant(
          of: find.byKey(ValueKey('section-chip-${last.id}')),
          matching: find.text('Under 1200 Reserve and Novice Championship'),
        ),
      );
      expect(name.width, lessThanOrEqualTo(200 * scale));
      // The strip scrolls to the button, between All sections and New
      // section.
      await tester.ensureVisible(menu);
      await tester.pumpAndSettle();
      final button = tester.getRect(menu);
      expect(
        button.left,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('section-chip-all'))).right,
        ),
      );
      expect(
        button.right,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('new-section'))).left,
        ),
      );
      await tester.tap(find.byKey(ValueKey('section-menu-${last.id}')));
      await tester.pumpAndSettle();
      expect(menuItem('Combine sections…'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  }
}
