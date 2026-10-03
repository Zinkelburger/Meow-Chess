import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/panels.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../test/support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'recover interrupted work and score at laptop size with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = fixture(count: 4);
      final boundaryKey = GlobalKey();
      final scale = ValueNotifier(2.0);
      final dark = ValueNotifier(false);
      c.post(await c.propose());
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
                path: 'Native rehearsal',
                onClose: () {},
                onTheme: () => dark.value = !dark.value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> click(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        expect(tester.takeException(), isNull);
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('artifacts').createSync();
        await File(
          'artifacts/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await click(find.byKey(const ValueKey('event-details')));
      await tester.enterText(
        find.byKey(const ValueKey('event-name')),
        'An unfinished event edit',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Discard draft'));
      await tester.pumpAndSettle();
      await capture('workflow-event-draft-200');
      await click(find.text('Discard draft'));
      expect(c.event!.name, 'Saturday Quads');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await click(find.byTooltip('Keyboard shortcuts (F1)'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsNothing);
      await click(find.text('Player 00', findRichText: true).first);
      expect(find.byType(PlayerPanel), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('panel-name')),
        'An unfinished edit',
      );
      await tester.pumpAndSettle();
      await capture('workflow-player-draft-200');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.event!.players.first.name, 'Player 00');
      await click(find.text('Rounds').first);
      final game = c.event!.games.first;
      await click(find.byKey(ValueKey('score-${game.id}-b')));
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();
      expect(c.event!.games.first.outcome, Outcome.blackWin);
      await capture('workflow-results-200');
      await click(find.byTooltip('Find player (Ctrl+L)'));
      await tester.enterText(find.byKey(const ValueKey('lookup-query')), '#1');
      await tester.pumpAndSettle();
      expect(find.byType(LookupPanel), findsOneWidget);
      await capture('workflow-lookup-200');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      scale.value = 1;
      await tester.pumpAndSettle();
      for (final g in c.event!.games.toList()) {
        c.recordResult(g.id, Outcome.draw);
      }
      c.post(await c.propose());
      await tester.pumpAndSettle();
      await click(
        find.descendant(
          of: find.byKey(const ValueKey('round-selector')),
          matching: find.text('1'),
        ),
      );
      tester.state<ResultsViewState>(find.byType(ResultsView)).printRound();
      await tester.pumpAndSettle();
      expect(tester.widget<PrintPanel>(find.byType(PrintPanel)).roundNumber, 1);
      c.savePlayer(c.event!.players.last.copy(name: 'A corrected player name'));
      await tester.pumpAndSettle();
      await capture('workflow-print-stale');
      await click(find.text('Refresh preview'));
      expect(find.byKey(const ValueKey('print-stale')), findsNothing);
      await capture('workflow-print-refreshed');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await click(find.text('Reports').first);
      await capture('workflow-reports');
      dark.value = true;
      scale.value = 2;
      await tester.pumpAndSettle();
      await capture('workflow-reports-dark-200');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      c.dispose();
      scale.dispose();
      dark.dispose();
    },
  );
}
