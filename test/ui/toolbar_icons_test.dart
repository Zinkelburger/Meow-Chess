import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/ui/help_panel.dart';

import '../support.dart';
import 'workspace_host.dart';

void main() {
  IconData icon(WidgetTester tester, String key) =>
      (tester.widget<IconButton>(find.byKey(ValueKey(key))).icon as Icon).icon!;

  testWidgets('Undo, Redo and Close event look like what they do', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    var closed = 0;
    await mountWorkspace(tester, c, onClose: () => closed++);
    expect(icon(tester, 'undo'), Icons.undo);
    expect(icon(tester, 'redo'), Icons.redo);
    // A way out of the event, not the × that closes a panel.
    expect(icon(tester, 'close-event'), Icons.logout);
    expect(find.byTooltip('Close event'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-event')));
    await tester.pumpAndSettle();
    expect(closed, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('F1 is Help; the shortcut list has its own key', (tester) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mountWorkspace(tester, c);
    expect(find.byTooltip('Help (F1)'), findsOneWidget);
    expect(find.byTooltip('Keyboard shortcuts (Shift+F1)'), findsOneWidget);
    expect(find.byTooltip('Help articles'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(find.byType(HelpPanel), findsOneWidget);
    expect(find.text('Keyboard shortcuts'), findsNothing);
    // F1 again closes it, as the button does.
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(find.byType(HelpPanel), findsNothing);

    await chord(
      tester,
      LogicalKeyboardKey.f1,
      modifier: LogicalKeyboardKey.shiftLeft,
    );
    expect(find.byType(HelpPanel), findsNothing);
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.text('F1 — Help'), findsOneWidget);
    expect(find.text('Shift+F1 — This list'), findsOneWidget);
    // What Esc does to an edit is said as it is.
    expect(
      find.textContaining('save their changes as they close'),
      findsOneWidget,
    );
    expect(find.textContaining('keep its draft'), findsNothing);
    await tester.tap(find.byTooltip('Keyboard shortcuts (Shift+F1)'));
    await tester.pumpAndSettle();
    expect(find.text('Keyboard shortcuts'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
