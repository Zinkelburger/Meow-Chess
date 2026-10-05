import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../test/demo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets('browse, review, reopen and recover an earlier result', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = TournamentController(SqliteEventRepository(':memory:'));
    populatePractice(c);
    // Historical-round correction is the Swiss workflow. Quads publish their
    // whole schedule at once and remain directly editable while unstarted.
    c.change(
      'Prepare Swiss correction rehearsal',
      c.event!.copy(
        sections: [
          c.event!.sections.first.copy(format: Format.swiss),
          ...c.event!.sections.skip(1),
        ],
      ),
    );
    final section = c.event!.sections.first;
    c.post(await c.propose(sectionId: section.id));
    for (final g in c.event!.sections.first.rounds.first.games) {
      c.recordResult(g.id, Outcome.whiteWin);
    }
    c.post(await c.propose(sectionId: section.id));
    final before = c.graph.head!;
    final game = c.event!.games.first;
    c.workspaceState.write('view', '${section.id}|results');
    final screenshotKey = GlobalKey();
    var brightness = Brightness.light;
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
              home: Workspace(
                controller: c,
                path: 'Synthetic rehearsal event',
                onClose: () {},
                onTheme: () {},
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final boundary =
          screenshotKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('artifacts').createSync();
      await File(
        'artifacts/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    }

    await tester.tap(find.byKey(const ValueKey('all-rounds')));
    await tester.pumpAndSettle();
    await capture('correction-all-rounds');
    await tester.tap(find.byKey(const ValueKey('correct-round')));
    await tester.tap(find.byKey(ValueKey('score-${game.id}-w')));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('reopen-round-2')));
    await tester.tap(find.byKey(const ValueKey('reopen-round-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-unstarted')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('result-reason')),
      'Signed scoresheet shows Black won.',
    );
    await tester.pumpAndSettle();
    await tester.fling(
      find.byKey(const ValueKey('correction-whiteWin')),
      const Offset(0, 600),
      2000,
    );
    await tester.pumpAndSettle();
    expect(c.graph.head, before);
    await capture('correction-review-light');
    setTheme(() => brightness = Brightness.dark);
    await tester.pumpAndSettle();
    await capture('correction-review-dark');
    setTheme(() => brightness = Brightness.light);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-correction')));
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.rounds.length, 1);
    expect(c.event!.games.first.outcome, Outcome.blackWin);
    expect(find.textContaining('Round 2 onward is unpaired'), findsOneWidget);
    await capture('correction-saved');
    await tester.tap(find.byKey(const ValueKey('correction-done')));
    await tester.pumpAndSettle();
    final corrected = c.graph.head!;
    await tester.tap(find.byTooltip('History (Ctrl+H)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('history-$corrected')));
    await tester.pumpAndSettle();
    await capture('correction-transaction');
    expect(c.repository.snapshot(before).sections.first.rounds.length, 2);
    c.undo();
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.rounds.length, 2);
    expect(c.event!.games.first.outcome, Outcome.whiteWin);
    c.redo();
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.rounds.length, 1);
    expect(c.event!.games.first.outcome, Outcome.blackWin);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    c.dispose();
  });
}
