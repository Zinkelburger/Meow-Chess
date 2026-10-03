import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/main.dart';
import 'package:meow_chess/ui/brand.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Bold.ttf'))).load();
  });

  setUp(() {
    directory = Directory.systemTemp.createTempSync('meow-entrance-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('meow_chess/file_open'),
      (_) async => <String>[],
    );
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('meow_chess/file_open'),
      null,
    );
  });

  testWidgets(
    'cat arrives, holds, docks, and does not replay on theme change',
    (tester) async {
      await tester.pumpWidget(MeowApp(dataDirectory: directory));
      await tester.pump();
      final flyingCat = find.byType(MeowLogo).last;
      expect(tester.getRect(flyingCat).bottom, lessThanOrEqualTo(0));
      await tester.pump(const Duration(milliseconds: 600));
      final centered = tester.getRect(flyingCat);
      expect(centered.center, const Offset(400, 300));
      expect(centered.size, const Size(600, 600));
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.getRect(flyingCat), centered);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(flyingCat).width, lessThan(600));
      await tester.pumpAndSettle();
      expect(find.byType(MeowLogo), findsOneWidget);
      await tester.tap(find.byTooltip('Dark mode'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Light mode'), findsOneWidget);
      expect(find.byType(MeowLogo), findsOneWidget);
      await tester.tap(find.text('New tournament'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('new-event-name')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('header keeps equal gaps and a large theme icon across widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [960.0, 1120.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(MeowApp(dataDirectory: directory));
      await tester.pumpAndSettle();
      final cat = tester.getRect(find.byType(MeowLogo));
      final title = tester.getRect(find.text('Meow Chess'));
      final moon = tester.getRect(find.byIcon(Icons.dark_mode_outlined));
      expect(title.left - cat.right, closeTo(24, .01));
      expect(moon.left - title.right, closeTo(24, .01));
      expect(moon.width, greaterThan(48));
      expect(moon.center.dy, closeTo(title.center.dy, .01));
      expect(cat.width, 396);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion skips the launch animation', (tester) async {
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(MeowApp(dataDirectory: directory));
    await tester.pump();
    expect(find.byType(MeowLogo), findsOneWidget);
    await tester.tap(find.text('New tournament'));
    await tester.pump();
    expect(find.byKey(const ValueKey('new-event-name')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
