import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/ui/select.dart';

void main() {
  late FocusNode focus;
  late List<String> changes;
  setUp(() {
    focus = FocusNode();
    changes = [];
  });
  tearDown(() => focus.dispose());

  Future<void> show(
    WidgetTester tester,
    String value,
    List<SelectOption<String>> options,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              child: PlainSelect<String>(
                value: value,
                options: options,
                label: 'Pick',
                focusNode: focus,
                onChanged: changes.add,
              ),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
  }

  Finder item(int i) => find.byKey(ValueKey(('select-option', i)));
  bool focused(WidgetTester tester, int i) =>
      tester.widget<MenuItemButton>(item(i)).focusNode!.hasFocus;
  Future<void> type(WidgetTester tester, String letter) async {
    final key = LogicalKeyboardKey(letter.codeUnitAt(0));
    await tester.sendKeyDownEvent(key, character: letter);
    await tester.sendKeyUpEvent(key);
    await tester.pumpAndSettle();
  }

  final many = [
    for (var i = 0; i < 40; i++)
      SelectOption('v$i', 'Option ${i.toString().padLeft(2, '0')}'),
  ];

  testWidgets('Down opens on the current choice, scrolled into view', (
    tester,
  ) async {
    await show(tester, 'v30', many);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(item(30), findsOneWidget);
    expect(focused(tester, 30), true);
    final viewport = tester.getRect(
      find.ancestor(of: item(30), matching: find.byType(Scrollable)).first,
    );
    final row = tester.getRect(item(30));
    expect(viewport.top <= row.top && row.bottom <= viewport.bottom, true);
  });

  testWidgets('Space opens; Esc closes without changing the value', (
    tester,
  ) async {
    await show(tester, 'v2', many);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(focused(tester, 2), true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(tester, 3), true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(item(3), findsNothing);
    expect(changes, isEmpty);
  });

  testWidgets('disabled choices are skipped', (tester) async {
    const options = [
      SelectOption('a', 'Alpha', enabled: false),
      SelectOption('b', 'Bravo'),
      SelectOption('c', 'Charlie', enabled: false),
      SelectOption('d', 'Delta'),
    ];
    // A disabled current choice starts on the first one that can be picked.
    await show(tester, 'a', options);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(tester, 1), true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(tester, 3), true);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(changes, ['d']);
  });

  testWidgets('typing a letter jumps to the next choice starting with it', (
    tester,
  ) async {
    const options = [
      SelectOption('apple', 'Apple'),
      SelectOption('banana', 'Banana'),
      SelectOption('boysen', 'Boysenberry', enabled: false),
      SelectOption('blue', 'Blueberry'),
      SelectOption('avila', 'Ávila'),
    ];
    await show(tester, 'apple', options);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await type(tester, 'b');
    expect(focused(tester, 1), true);
    await type(tester, 'b');
    expect(focused(tester, 3), true);
    await type(tester, 'b');
    expect(focused(tester, 1), true);
    // Accents do not hide a match.
    await type(tester, 'a');
    expect(focused(tester, 4), true);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(changes, ['avila']);
  });
}
