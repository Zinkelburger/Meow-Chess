import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meow_chess/application/demo.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('open player details beside the roster and round boards', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = TournamentController(SqliteEventRepository(':memory:'));
    populatePractice(c);
    final screenshotKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: meowTheme(Brightness.light),
          home: Workspace(
            controller: c,
            path: 'Practice event',
            onClose: () {},
            onTheme: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> doubleClick(Finder target) async {
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<void> screenshot(String name) async {
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

    final first = c.event!.players.first;
    await doubleClick(
      find.descendant(
        of: find.byKey(ValueKey('player-${first.id}')),
        matching: find.text(first.name, findRichText: true),
      ),
    );
    expect(find.byKey(const ValueKey('panel-name')), findsOneWidget);
    await screenshot('player-details-roster');
    c.post(await c.propose());
    await tester.tap(find.text('Rounds').first);
    await tester.pumpAndSettle();
    final game = c.event!.sections.first.rounds.single.games.first;
    await doubleClick(
      find.byKey(ValueKey('round-player-${game.id}-${game.white}')),
    );
    expect(find.byKey(const ValueKey('panel-name')), findsOneWidget);
    await screenshot('player-details-rounds');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    c.dispose();
  });
}
