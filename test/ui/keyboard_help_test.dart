import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/ui/keyboard_help.dart';
import 'package:meow_chess/ui/theme.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('shortcut list reads key then action at ${scale}x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: meowTheme(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: KeyboardHelpPanel(onClose: () {}),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Grouped, with each key on its own cap rather than "1 / W — ...".
      for (final heading in ['Results', 'Moving around', 'Anywhere']) {
        expect(find.text(heading), findsOneWidget);
      }
      expect(find.textContaining(' — '), findsNothing);
      expect(find.text('W'), findsOneWidget);
      expect(find.text('This player wins'), findsOneWidget);
      // A screen reader hears the row as one sentence.
      expect(find.bySemanticsLabel('1 or W: This player wins'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Tab then Enter: Open the focused player'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  }
}
