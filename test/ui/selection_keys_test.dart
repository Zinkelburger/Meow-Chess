import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/ui/selection_keys.dart';

// The app ships for the desktop and the web, so every case runs as Linux,
// Windows and macOS.
Widget app({
  required bool fixed,
  TextEditingController? field,
  ValueChanged<SelectedContent?>? onSelection,
}) {
  final body = Column(
    children: [
      const Text('Kim Lee'),
      TextField(controller: field),
      const Text('Jo Park'),
    ],
  );
  return MaterialApp(
    home: Scaffold(
      body: SelectionArea(
        onSelectionChanged: onSelection,
        child: fixed ? TextFieldKeysInSelection(child: body) : body,
      ),
    ),
  );
}

void main() {
  testWidgets('Flutter still needs the workaround', (tester) async {
    // When this starts passing, Flutter is fixed: remove
    // TextFieldKeysInSelection and this test.
    await tester.pumpWidget(app(fixed: false));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.takeException(), isA<TypeError>());
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('Up and Down move the caret in a field inside a selection area', (
    tester,
  ) async {
    final field = TextEditingController(text: '1800');
    addTearDown(field.dispose);
    await tester.pumpWidget(app(fixed: true, field: field));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    field.selection = const TextSelection.collapsed(offset: 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.takeException(), isNull);
    // On a single line, Up goes to the start and Down to the end.
    expect(field.selection, const TextSelection.collapsed(offset: 0));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(field.selection, const TextSelection.collapsed(offset: 4));
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('selecting text by keyboard outside fields still works', (
    tester,
  ) async {
    SelectedContent? selected;
    await tester.pumpWidget(app(fixed: true, onSelection: (c) => selected = c));
    // Drag across a name, then extend the selection down a line.
    final name = find.text('Kim Lee');
    final gesture = await tester.startGesture(
      tester.getTopLeft(name) + const Offset(1, 4),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(tester.getTopRight(name) + const Offset(-1, 4));
    await gesture.up();
    await tester.pump();
    final before = selected?.plainText ?? '';
    expect(before, isNotEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(tester.takeException(), isNull);
    // The selection area's own action ran: the selection grew.
    expect((selected?.plainText ?? '').length, greaterThan(before.length));
  }, variant: TargetPlatformVariant.desktop());
}
