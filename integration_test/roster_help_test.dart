import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../test/support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('horizontal workspace and offline help at desktop sizes', (
    tester,
  ) async {
    final c = fixture(count: 22);
    final boundaryKey = GlobalKey();
    final scale = ValueNotifier(1.0);
    final dark = ValueNotifier(false);
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: ValueListenableBuilder(
          valueListenable: dark,
          builder: (_, isDark, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: meowTheme(isDark ? Brightness.dark : Brightness.light),
            builder: (context, child) => ValueListenableBuilder(
              valueListenable: scale,
              builder: (_, value, _) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(value)),
                child: child!,
              ),
            ),
            home: Workspace(
              controller: c,
              path: 'Saturday Quads.meow',
              onClose: () {},
              onTheme: () => dark.value = !dark.value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'artifacts/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    await capture('roster-horizontal-tabs');
    c.post((await tester.runAsync(() => c.propose()))!);
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('result-keys')), findsNothing);
    expect(find.byTooltip('Find player (Ctrl+L)'), findsNothing);
    await capture('workspace-simplified-rounds');
    await tester.tap(find.text('Players').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Help articles'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('help-search')), 'quads');
    await tester.pumpAndSettle();
    await tester.tap(find.text('How quads are paired'));
    await tester.pumpAndSettle();
    await capture('roster-quad-help');
    dark.value = true;
    scale.value = 2;
    await tester.pumpAndSettle();
    await capture('roster-help-dark-200');
    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pumpAndSettle();
    scale.value = 1;
    await tester.binding.setSurfaceSize(const Size(960, 600));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('player-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('update-event')));
    await tester.pumpAndSettle();
    await capture('workspace-empty-url');
    await tester.enterText(
      find.byKey(const ValueKey('roster-url')),
      'https://boylstonchess.org/tournament/entries/1563',
    );
    await tester.pumpAndSettle();
    await capture('roster-update-small');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    c.dispose();
    scale.dispose();
    dark.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}
