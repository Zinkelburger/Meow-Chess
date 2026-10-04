import 'scenarios/team_workflow.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/demo.dart';
import 'package:meow_chess/main.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart' show hasFixedQuadSchedule;
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  registerTeamWorkflowTests();
  testWidgets('event library opens, closes, and reopens a real event file', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('meow-library-');
    final eventPath = '${directory.path}/club.meow';
    final event = TournamentController(SqliteEventRepository(eventPath));
    event.create('Saturday at the club');
    event.dispose();
    await tester.pumpWidget(
      MeowApp(dataDirectory: directory, initialPath: eventPath),
    );
    await tester.pumpAndSettle();
    expect(find.text('Practice copy'), findsNothing);
    expect(find.text('Saturday at the club'), findsWidgets);
    await tester.tap(find.byTooltip('Close event'));
    await tester.pumpAndSettle();
    expect(find.text('Recent events'), findsOneWidget);
    final recent =
        jsonDecode(File('${directory.path}/library.json').readAsStringSync())
            as List;
    expect(recent, hasLength(1));
    final saved = SqliteEventRepository(recent.single as String);
    expect(saved.load()!.players, isEmpty);
    expect(saved.load()!.practice, false);
    saved.close();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MeowApp(dataDirectory: directory, initialPath: recent.single as String),
    );
    await tester.pumpAndSettle();
    expect(find.text('Practice copy'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    directory.deleteSync(recursive: true);
  });
  testWidgets(
    'native tournament day: mixed quad and Swiss schedules, keyboard score, print PDF and recover',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('meow-native-');
      final path = '${directory.path}/practice.meow';
      var c = TournamentController(SqliteEventRepository(path));
      populatePractice(c);
      final screenshotKey = GlobalKey();
      var dark = false;
      Future<void> mount() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: screenshotKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: meowTheme(dark ? Brightness.dark : Brightness.light),
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
        // Dismiss the transient pairing notice before capturing the workspace.
        tester
            .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
            .removeCurrentSnackBar();
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
      await screenshot('players');
      await tester.tap(find.text('Pairings').first);
      await tester.pumpAndSettle();
      final quads = c.event!.sections.where(hasFixedQuadSchedule).toList();
      final swiss = c.event!.sections
          .where((s) => !hasFixedQuadSchedule(s))
          .toList();
      expect(quads, hasLength(4));
      expect(swiss, hasLength(1));
      expect(c.event!.games, isEmpty);
      expect(
        c.pairingEvent.sections
            .where(hasFixedQuadSchedule)
            .every((s) => s.rounds.length == 3),
        true,
      );
      // Only the six-player remainder needs posting; each quad already has its
      // complete schedule on screen, without persisted results or a post step.
      await tester.tap(find.byKey(const ValueKey('pair-next-round')));
      await tester.pumpAndSettle();
      expect(
        c.event!.sections
            .where(hasFixedQuadSchedule)
            .every((s) => s.rounds.isEmpty),
        true,
      );
      expect(
        c.event!.sections.firstWhere((s) => s.id == swiss.single.id).rounds,
        hasLength(1),
      );
      for (var round = 0; round < 3; round++) {
        for (final section in c.event!.sections) {
          final sectionTile = find.byKey(
            ValueKey('section-chip-${section.id}'),
          );
          await tester.ensureVisible(sectionTile);
          await tester.pumpAndSettle();
          await tester.tap(sectionTile);
          await tester.pumpAndSettle();
          final displayed = c.pairingEvent.sections.firstWhere(
            (s) => s.id == section.id,
          );
          if (hasFixedQuadSchedule(section)) {
            expect(displayed.rounds, hasLength(3));
            expect(find.byKey(const ValueKey('pair-next-round')), findsNothing);
          }
          final games = displayed.rounds
              .firstWhere((r) => r.number == round + 1)
              .games;
          for (final game in games) {
            // Select the intended round explicitly: quads show future rounds
            // too, and keyboard advance may move into the next one.
            final score = find.byKey(ValueKey('score-${game.id}-w'));
            await tester.ensureVisible(score);
            await tester.pumpAndSettle();
            await tester.tap(score);
            await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
            await tester.pumpAndSettle();
            expect(
              c.event!.games.firstWhere((g) => g.id == game.id).outcome,
              Outcome.draw,
            );
          }
          if (round == 0 && section.id == c.event!.sections.first.id) {
            // Keyboard advance scrolls to the next quad round in the stacked
            // layout. Bring the packet toolbar back before clicking it.
            final printPacket = find.byKey(const ValueKey('print-round'));
            await tester.ensureVisible(printPacket);
            await tester.pumpAndSettle();
            expect(printPacket.hitTestable(), findsOneWidget);
            await screenshot('results-section');
            await tester.tap(printPacket);
            await tester.pumpAndSettle(const Duration(seconds: 1));
            expect(find.byKey(const ValueKey('print-panel')), findsOneWidget);
            await screenshot('print-docked');
            await tester.tap(find.byTooltip('Close (Esc)'));
            await tester.pumpAndSettle();
            await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
            await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byKey(const ValueKey('lookup-query')),
              'morgan',
            );
            await tester.pumpAndSettle();
            await screenshot('lookup-docked');
            await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
            await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
            await tester.pumpAndSettle();
          }
        }
        for (final section in c.event!.sections) {
          expect(
            section.rounds.firstWhere((r) => r.number == round + 1).complete,
            true,
          );
          expect(
            c.pairingEvent.sections
                .firstWhere((s) => s.id == section.id)
                .rounds
                .where((r) => r.number > round + 1)
                .expand((r) => r.games)
                .every((g) => g.outcome == Outcome.unreported),
            true,
            reason:
                'Entering round ${round + 1} must not score a future quad round',
          );
        }
        final allSections = find.byKey(const ValueKey('section-chip-all'));
        await tester.ensureVisible(allSections);
        await tester.pumpAndSettle();
        await tester.tap(allSections);
        await tester.pumpAndSettle();
        if (round == 0) await screenshot('results-grid');
        if (round < 2) {
          await tester.tap(find.text('Pairings').first);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('pair-next-round')));
          await tester.pumpAndSettle();
        }
      }
      expect(c.event!.games.length, 33);
      expect(c.event!.games.every((g) => g.outcome == Outcome.draw), true);
      expect(find.byKey(const ValueKey('event-complete')), findsOneWidget);
      expect(find.byKey(const ValueKey('pair-next-round')), findsNothing);
      await tester.tap(find.text('Players').first);
      await tester.pumpAndSettle();
      await screenshot('standings');
      await tester.tap(find.text('Export').first);
      await tester.pumpAndSettle();
      await screenshot('reports');
      dark = true;
      await mount();
      await tester.tap(find.text('Pairings').first);
      await tester.pumpAndSettle();
      await screenshot('results-dark');
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
