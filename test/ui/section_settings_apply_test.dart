import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/section_panel.dart';

import '../support.dart';
import 'workspace_host.dart';

void main() {
  Finder name() => find.byKey(const ValueKey('field-name'));
  Finder notice() => find.byKey(const ValueKey('undo-notice'));

  Future<void> edit(
    WidgetTester tester,
    TournamentController c,
    int section,
    String newName,
  ) async {
    await tabMenu(
      tester,
      c.event!.sections[section].id,
      'Rename / section settings…',
    );
    await tester.enterText(name(), newName);
    await tester.pump();
  }

  testWidgets('closing section settings saves the edit, with Undo', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    final [q1, _] = c.event!.sections;
    await mountWorkspace(tester, c);

    await edit(tester, c, 0, 'Open');
    expect(
      find.text('Not saved yet · saves when this panel closes'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.name, 'Open');
    expect(find.byType(SectionSettingsPanel), findsNothing);
    expect(
      find.descendant(
        of: notice(),
        matching: find.text('Saved Open’s settings.'),
      ),
      findsOneWidget,
    );
    // Nothing is left behind as a draft.
    expect(c.workspaceState.read('draft-section-${q1.id}') ?? '', isEmpty);
    // One step: the toast's Undo takes the whole edit back.
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.name, q1.name);

    await edit(tester, c, 0, 'Premier');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.name, 'Premier');
    expect(find.byType(SectionSettingsPanel), findsNothing);
    expect(notice(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opening something else saves the settings edit first', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    await mountWorkspace(tester, c);

    // Another section's tab.
    await edit(tester, c, 0, 'Tab');
    await pickTab(tester, q2.id);
    expect(c.event!.sections.first.name, 'Tab');
    expect(find.byType(SectionSettingsPanel), findsNothing);
    expect(find.byKey(ValueKey('section-menu-${q2.id}')), findsOneWidget);
    expect(notice(), findsOneWidget);

    // Another section's settings.
    await edit(tester, c, 0, 'Settings');
    await tabMenu(tester, q2.id, 'Rename / section settings…');
    expect(c.event!.sections.first.name, 'Settings');
    expect(
      tester.widget<TextField>(name()).controller!.text,
      c.event!.sections.last.name,
    );

    // Another panel in the dock.
    await edit(tester, c, 0, 'Dock');
    await tester.tap(find.byKey(const ValueKey('event-details')));
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.name, 'Dock');
    expect(find.byType(SectionSettingsPanel), findsNothing);
    expect(find.byKey(const ValueKey('event-name')), findsOneWidget);

    // Another page.
    await edit(tester, c, 0, 'Page');
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.name, 'Page');
    expect(find.byType(SectionSettingsPanel), findsNothing);
    expect(c.workspaceState.read('draft-section-${q1.id}') ?? '', isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an edit that cannot be saved keeps the panel open', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    await mountWorkspace(tester, c);
    final revision = c.event!.revision;

    await edit(tester, c, 0, '');
    for (final leave in <Future<void> Function()>[
      () => tester.sendKeyEvent(LogicalKeyboardKey.escape),
      () => tester.tap(find.byTooltip('Close (Esc)')),
      () => tester.tap(find.byKey(ValueKey('section-chip-${q2.id}'))),
      () => tester.tap(find.byKey(const ValueKey('event-details'))),
      () => tester.tap(find.text('Pairings').first),
    ]) {
      await leave();
      await tester.pumpAndSettle();
      expect(find.byType(SectionSettingsPanel), findsOneWidget);
      expect(find.text('Enter the name.'), findsOneWidget);
      expect(find.byKey(const ValueKey('section-settings-held')), findsOne);
      // Still on the same section's Players page.
      expect(find.byKey(ValueKey('section-menu-${q1.id}')), findsOneWidget);
      expect(find.byKey(const ValueKey('event-name')), findsNothing);
    }
    expect(c.event!.revision, revision);
    expect(notice(), findsNothing);

    // A problem with a number is held the same way.
    await tester.enterText(name(), q1.name);
    await tester.enterText(find.byKey(const ValueKey('field-rounds')), '99');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SectionSettingsPanel), findsOneWidget);
    expect(
      find.text('Number of rounds must be between 1 and 32.'),
      findsOneWidget,
    );

    // Discard draft is the way out without saving.
    await tester.ensureVisible(find.text('Discard draft'));
    await tester.tap(find.text('Discard draft'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SectionSettingsPanel), findsNothing);
    expect(c.event!.revision, revision);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing untouched settings changes nothing and says nothing', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await mountWorkspace(tester, c);
    final revision = c.event!.revision;
    await tabMenu(
      tester,
      c.event!.sections.first.id,
      'Rename / section settings…',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SectionSettingsPanel), findsNothing);
    expect(c.event!.revision, revision);
    expect(notice(), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
