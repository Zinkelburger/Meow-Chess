import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meow_chess/ui/desktop_window.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../test/support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('compact toolbar and immediate section editing', (tester) async {
    final c = fixture(count: 22);
    final boundaryKey = GlobalKey();
    final scale = ValueNotifier(1.0);
    final dark = ValueNotifier(false);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
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

    expect(find.text('USCF expires'), findsOneWidget);
    expect(find.text('R1'), findsNothing);
    expect(find.byKey(const ValueKey('pair-next-round')), findsNothing);
    expect(find.byKey(const ValueKey('refresh-uscf')), findsOneWidget);
    await capture('toolbar-sections-wide');
    await tester.tap(find.byKey(const ValueKey('player-tools')));
    await tester.pumpAndSettle();
    expect(find.text('Refresh from URL'), findsOneWidget);
    expect(find.text('Import file…'), findsOneWidget);
    await capture('workflow-player-tools');
    await tester.tap(find.byKey(const ValueKey('player-tools')));
    await tester.pumpAndSettle();
    final first = c.event!.sections.first;
    await tester.tap(find.byKey(ValueKey('section-chip-${first.id}')));
    await tester.pumpAndSettle();
    final table = find.byKey(const ValueKey('player-column-header'));
    final before = tester.getRect(table);
    await capture('workflow-players');
    await tester.tap(
      find.text(c.event!.player(first.players.first).name, findRichText: true),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(table), before);
    await capture('workflow-player-card');
    await tester.tap(find.byTooltip('Close (Esc)').last);
    await tester.pumpAndSettle();
    expect(tester.getRect(table), before);
    await tester.tap(find.byKey(const ValueKey('section-chip-all')));
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(960, 600));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(WorkspaceToolbar)).height, 48);
    expect(
      tester.getCenter(find.text('Players').first).dy,
      lessThan(tester.getCenter(find.byKey(const ValueKey('section-tabs'))).dy),
    );
    expect(
      tester.getCenter(find.byTooltip('Help articles')).dy,
      lessThan(tester.getCenter(find.byKey(const ValueKey('section-tabs'))).dy),
    );
    await capture('toolbar-sections-small');
    await tester.tap(find.byKey(const ValueKey('new-section')));
    await tester.pumpAndSettle();
    expect(c.event!.sections.last.name, 'Section 1');
    await capture('toolbar-section-editor');
    await tester.tap(find.byTooltip('Close (Esc)').last);
    dark.value = true;
    await tester.pumpAndSettle();
    await capture('toolbar-sections-dark');
    scale.value = 2;
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    await tester.pumpAndSettle();
    await capture('toolbar-sections-200');
    scale.value = 1;
    dark.value = false;
    await tester.binding.setSurfaceSize(const Size(960, 600));
    await tester.tap(find.byKey(const ValueKey('section-chip-all')));
    await tester.pumpAndSettle();
    c.post((await tester.runAsync(() => c.propose()))!);
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();
    await capture('toolbar-rounds-small');
    await tester.ensureVisible(
      find.byKey(const ValueKey('player-column-header')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('player-column-header')),
        matching: find.text('#'),
      ),
      findsOneWidget,
    );
    expect(find.text('R1'), findsOneWidget);
    expect(find.text('USCF expires'), findsNothing);
    expect(find.byKey(const ValueKey('player-tools')), findsNothing);
    await capture('workflow-crosstable-small');
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.tap(find.byKey(ValueKey('section-chip-${first.id}')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('player-column-header')),
    );
    await tester.pumpAndSettle();
    await capture('workflow-crosstable');
    await tester.ensureVisible(
      find.byKey(const ValueKey('board-column-header')),
    );
    await tester.pumpAndSettle();
    await capture('workflow-pairings');
    c.change(
      'Empty registration fixture',
      c.event!.copy(name: 'Club night', players: [], sections: []),
    );
    await tester.tap(find.text('Players').first);
    await tester.pumpAndSettle();
    await capture('toolbar-empty-registration');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    scale.dispose();
    dark.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}
