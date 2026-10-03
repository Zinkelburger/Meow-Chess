import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../test/support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'section workflow uses keyboard results in both views and generates wall sheets',
    (tester) async {
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

      final section = c.event!.sections.first;
      await tester.tap(find.byKey(ValueKey('section-chip-${section.id}')));
      await tester.tap(find.text('Pairings').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pair-next-round')));
      await tester.pumpAndSettle();
      expect(c.event!.sections.every((s) => s.rounds.length == 1), true);
      expect(find.byKey(const ValueKey('pair-next-round')), findsNothing);
      final games = c.event!.sections.first.rounds.single.games;
      await tester.tap(find.byKey(ValueKey('score-${games.first.id}-w')));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.pumpAndSettle();
      expect(c.event!.games.first.outcome, Outcome.whiteWin);
      await capture('section-workflow-pairings');
      await tester.tap(find.byKey(const ValueKey('show-crosstable')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey('standing-score-${games.last.id}-${games.last.black}'),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();
      expect(
        c.event!.games.firstWhere((g) => g.id == games.last.id).outcome,
        Outcome.draw,
      );
      await capture('section-workflow-standings');
      final font = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
      );
      final bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Inter-SemiBold.ttf'),
      );
      await File('artifacts/section-wall-sheets.pdf').writeAsBytes(
        await reportPdf(c.event!, ReportKind.sections, font: font, bold: bold),
      );
      await tester.tap(find.text('Pairings'));
      await tester.pumpAndSettle();
      await tester.binding.setSurfaceSize(const Size(960, 600));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('score-${games.first.id}-b')).hitTestable(),
        findsOneWidget,
      );
      await capture('section-workflow-laptop');
      dark.value = true;
      scale.value = 2;
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      await tester.pumpAndSettle();
      await capture('section-workflow-large-text');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      scale.dispose();
      dark.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
}
