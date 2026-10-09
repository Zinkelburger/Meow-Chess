import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/ui/desktop_window.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('the minimum window fits a 1366x768 laptop at 125% scaling', () {
    // 768 / 1.25 = 614 logical pixels, less a 48 pixel taskbar.
    expect(minimumWindowSize.height, lessThanOrEqualTo(614 - 48 / 1.25));
    expect(minimumWindowSize.width, lessThanOrEqualTo(1366 / 1.25));
  });

  test('a window manager failure does not block startup', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'unavailable'),
        );
    await initializeDesktopWindow();
  });

  testWidgets('the workspace works at the minimum window size', (tester) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
    tester.view.physicalSize = minimumWindowSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixture(practice: true);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Workspace(
          controller: c,
          path: ':memory:',
          onClose: () {},
          onTheme: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> click(Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target, warnIfMissed: true);
      await tester.pumpAndSettle();
    }

    for (final page in ['Pairings', 'Export', 'Players']) {
      await click(find.text(page).first);
    }
    await click(find.byKey(const ValueKey('event-details')));
    await tester.enterText(
      find.byKey(const ValueKey('event-name')),
      'Updated tournament name',
    );
    await tester.pumpAndSettle();
    await click(find.text('Discard draft'));
    await click(find.byTooltip('History (Ctrl+H)'));
    await click(find.byKey(ValueKey('history-${c.graph.head}')));
    await click(find.byKey(const ValueKey('status-backup')));
    expect(find.text('Choose folder…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
