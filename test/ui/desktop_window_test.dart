import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/ui/desktop_window.dart';
import 'package:meow_chess/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('initialization leaves native decorations in place', () async {
    await initializeDesktopWindow();
    expect(calls.map((call) => call.method), [
      'ensureInitialized',
      'setMinimumSize',
    ]);
  });

  testWidgets('toolbar keeps navigation without custom window controls', (
    tester,
  ) async {
    var navigated = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              WorkspaceToolbar(
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => navigated = true,
                      child: const Text('Close event'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    for (final label in [
      'Minimize window',
      'Maximize window',
      'Restore window',
      'Close window',
    ]) {
      expect(find.byTooltip(label), findsNothing);
    }
    await tester.dragFrom(const Offset(300, 24), const Offset(80, 0));
    await tester.tap(find.text('Close event'));
    await tester.pump();
    expect(navigated, isTrue);
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
