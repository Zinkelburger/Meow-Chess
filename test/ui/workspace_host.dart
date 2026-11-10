import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/infrastructure/remembered_printing.dart';
import 'package:meow_chess/ui/section_tabs.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';

/// Mounts the whole workspace on [c] in a window of [size] at [scale] times
/// the normal text size. [path] is the event file the workspace names; it
/// does not open it, the controller has already.
Future<void> mountWorkspace(
  WidgetTester tester,
  TournamentController c, {
  String path = ':memory:',
  Size size = const Size(1400, 900),
  double scale = 1,
  RememberedPrinting? printing,
  VoidCallback? onClose,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Workspace(
        controller: c,
        path: path,
        onClose: onClose ?? () {},
        onTheme: () {},
        printing: printing,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Chooses a section's tab (`all` for All sections).
Future<void> pickTab(WidgetTester tester, String id) async {
  final chip = find.byKey(ValueKey('section-chip-$id'));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  // Near its start: at large text a tab can be wider than the strip's
  // view, which then shows its start.
  await tester.tapAt(tester.getTopLeft(chip) + const Offset(12, 12));
  await tester.pumpAndSettle();
}

/// An entry of the open section-tab menu.
Finder menuItem(String item) =>
    find.widgetWithText(PopupMenuItem<SectionMenuAction>, item);

/// Chooses [item] from the menu button on the tab of section [id], which
/// becomes the chosen tab first.
Future<void> tabMenu(WidgetTester tester, String id, String item) async {
  await pickTab(tester, id);
  await tester.tap(find.byKey(ValueKey('section-menu-$id')));
  await tester.pumpAndSettle();
  await tester.tap(menuItem(item));
  await tester.pumpAndSettle();
}

/// Presses [key] with [modifier] held.
Future<void> chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
}) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

/// Presses Tab until the focused control sits inside [target].
Future<void> tabTo(WidgetTester tester, Finder target) async {
  final element = tester.element(target);
  bool inside() {
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus == null) return false;
    var found = focus == element;
    focus.visitAncestorElements((ancestor) {
      if (ancestor == element) found = true;
      return !found;
    });
    return found;
  }

  for (var i = 0; i < 80 && !inside(); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(inside(), true, reason: 'Tab never reached $target');
}
