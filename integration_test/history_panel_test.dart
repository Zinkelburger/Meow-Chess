import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/demo.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('review numbered history and expand a saved branch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = TournamentController(SqliteEventRepository(':memory:'));
    populatePractice(c);
    final players = c.event!.players;
    c.savePlayer(players.first.copy(name: 'Diego Alvarez'));
    c.reserveBye(players.first.id, 3, 1);
    final bye = c.graph.head!;
    c.savePlayer(c.event!.players[1].copy(notes: 'Arriving at 10:30'));
    final branch = c.graph.head!;
    c.savePlayer(c.event!.players[2].copy(withdrawn: true));
    c.restore(bye);
    c.savePlayer(c.event!.players[3].copy(rating: 1850));
    c.reserveBye(players[4].id, 2, 1);
    final screenshotKey = GlobalKey();
    var brightness = Brightness.light;
    var textScale = 1.0;
    late StateSetter setTheme;
    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: StatefulBuilder(
          builder: (context, setState) {
            setTheme = setState;
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: meowTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: Workspace(
                controller: c,
                path: 'Practice event',
                onClose: () {},
                onTheme: () {},
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('History (Ctrl+H)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('history-$bye')));
    await tester.pumpAndSettle();
    expect(find.text('Diego Alvarez: Round 3 bye (0.5 pt)'), findsOneWidget);
    expect(find.text('Undo 2 operations'), findsOneWidget);
    expect(find.text('Saved branch · 2 operations'), findsOneWidget);
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

    await screenshot('history-inline-light');
    await tester.tap(find.byKey(ValueKey('history-branch-$branch')));
    await tester.pumpAndSettle();
    await screenshot('history-branches-light');
    setTheme(() => brightness = Brightness.dark);
    await tester.pumpAndSettle();
    await screenshot('history-branches-dark');
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    setTheme(() => textScale = 2.0);
    await tester.pumpAndSettle();
    await screenshot('history-large-text-dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    c.dispose();
  });
}
