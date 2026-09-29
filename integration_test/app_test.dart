import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meow_chess/application/demo.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native tournament day: post, keyboard score, print PDF, reopen and recover backup',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('meow-native-');
      final path = '${directory.path}/practice.meow';
      var c = TournamentController(SqliteEventRepository(path));
      populatePractice(c);
      final screenshotKey = GlobalKey();
      Future<void> mount() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: screenshotKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: meowTheme(Brightness.dark),
              home: Workspace(
                controller: c,
                path: path,
                onClose: () {},
                onTheme: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> screenshot(String name) async {
        await tester.pumpAndSettle();
        final boundary =
            screenshotKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('artifacts').createSync();
        await File(
          'artifacts/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await mount();
      await screenshot('event-overview');
      await tester.tap(find.text('Post ready sections'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post 5 ready sections'));
      await tester.pumpAndSettle();
      for (var round = 0; round < 3; round++) {
        final games =
            c.event!.sections.expand((s) => s.rounds.last.games).toList()
              ..sort((a, b) => a.board.compareTo(b.board));
        await tester.tap(find.byKey(ValueKey('game-${games.first.id}')));
        await tester.pump();
        for (var i = 0; i < games.length; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
          await tester.pumpAndSettle();
        }
        expect(c.event!.sections.every((s) => s.rounds.last.complete), true);
        if (round == 0) {
          await screenshot('results-grid');
        }
        if (round < 2) {
          await tester.tap(find.text('Post next round'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Post 5 ready sections'));
          await tester.pumpAndSettle();
        }
      }
      expect(c.event!.games.length, 33);
      expect(c.event!.games.every((g) => g.outcome == Outcome.draw), true);
      await tester.tap(find.text('Standings').first);
      await tester.pumpAndSettle();
      await screenshot('standings');
      final font = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
      );
      await File(
        'artifacts/round-packet.pdf',
      ).writeAsBytes(await reportPdf(c.event!, ReportKind.packet, font: font));
      final copy = '${directory.path}/backup.meow';
      c.repository.backup(copy);
      final expected = c.event!.encode();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      c = TournamentController(SqliteEventRepository(path));
      expect(c.event!.encode(), expected);
      c.dispose();
      c = TournamentController(SqliteEventRepository(copy));
      expect(c.event!.encode(), expected);
      c.dispose();
      directory.deleteSync(recursive: true);
    },
  );
}
