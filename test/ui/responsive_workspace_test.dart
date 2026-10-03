import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/reports_view.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../support.dart';

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final (size, scale) in [
    (const Size(960, 600), 1.0),
    (const Size(1280, 720), 2.0),
  ]) {
    for (final scenario in [
      'navigation',
      'event draft',
      'history',
      'new sections',
      'backups',
      'lookup',
      'keyboard help',
      'player byes',
      'report draft',
      'past rounds',
    ]) {
      testWidgets('$scenario at $size with ${scale}x text', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = fixture(practice: true);
        addTearDown(c.dispose);
        c.post((await tester.runAsync(() => c.propose()))!);
        await tester.pumpWidget(
          MaterialApp(
            theme: meowTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Workspace(
              controller: c,
              path: ':memory:',
              onClose: () {},
              onTheme: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> click(Finder target) async {
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          await tester.tap(target, warnIfMissed: true);
          await tester.pumpAndSettle();
        }

        switch (scenario) {
          case 'navigation':
            expect(
              tester
                  .getSize(find.byKey(const ValueKey('player-column-header')))
                  .height,
              lessThan(70),
            );
            for (final page in ['Pairings', 'Export', 'Players']) {
              await click(find.text(page).first);
            }
          case 'event draft':
            await click(find.byKey(const ValueKey('event-details')));
            await tester.enterText(
              find.byKey(const ValueKey('event-name')),
              'Updated tournament name',
            );
            await tester.pumpAndSettle();
            await click(find.text('Discard draft'));
            expect(c.event!.name, 'Saturday Quads');
          case 'history':
            await click(find.byTooltip('History (Ctrl+H)'));
            await click(find.byKey(ValueKey('history-${c.graph.head}')));
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(
              find.byKey(ValueKey('history-details-${c.graph.head}')),
              findsNothing,
            );
            expect(find.byKey(const ValueKey('history-graph')), findsOneWidget);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('history-graph')), findsNothing);
          case 'new sections':
            await click(find.byKey(const ValueKey('new-section')));
            final created = c.event!.sections.last;
            expect(created.players, isEmpty);
            expect(
              find.byKey(ValueKey('section-settings-${created.id}')),
              findsOneWidget,
            );
          case 'backups':
            await click(find.byKey(const ValueKey('status-backup')));
            expect(find.text('Choose folder…'), findsOneWidget);
          case 'lookup':
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            await click(find.byTooltip('Find player (Ctrl+L)'));
            expect(
              tester
                  .widget<EditableText>(
                    find.descendant(
                      of: find.byKey(const ValueKey('lookup-query')),
                      matching: find.byType(EditableText),
                    ),
                  )
                  .focusNode
                  .hasFocus,
              true,
            );
            await tester.enterText(
              find.byKey(const ValueKey('lookup-query')),
              '#1',
            );
            await tester.pumpAndSettle();
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('lookup-query')), findsNothing);
          case 'player byes':
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('player-p0')),
              100,
              scrollable: find.descendant(
                of: find.descendant(
                  of: find.byType(PlayersView),
                  matching: find.byType(ListView),
                ),
                matching: find.byType(Scrollable),
              ),
            );
            await click(find.text('Player 00', findRichText: true).first);
            final bye = find.byKey(const ValueKey('panel-bye-2'));
            await click(find.descendant(of: bye, matching: find.text('1/2')));
            expect(c.event!.player('p0').byes[2], 1);
          case 'report draft':
            await click(find.text('Export').first);
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('report-city')),
              200,
              scrollable: find
                  .descendant(
                    of: find.byType(ReportsView),
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is Scrollable &&
                          widget.axisDirection == AxisDirection.down,
                    ),
                  )
                  .first,
            );
            await tester.enterText(
              find.byKey(const ValueKey('report-city')),
              'Boston',
            );
            await tester.pumpAndSettle();
            await click(find.text('Save').first);
            expect(c.event!.city, 'Boston');
          case 'past rounds':
            for (var round = 1; round <= 2; round++) {
              for (final game
                  in c.event!.games
                      .where((g) => !g.outcome.resolved)
                      .toList()) {
                c.recordResult(game.id, Outcome.draw);
              }
              c.post((await tester.runAsync(() => c.propose()))!);
            }
            await tester.pumpAndSettle();
            await click(find.text('Pairings').first);
            await click(
              find.descendant(
                of: find.byKey(const ValueKey('round-selector')),
                matching: find.text('1'),
              ),
            );
            expect(
              find.byKey(const ValueKey('past-round-banner')),
              findsOneWidget,
            );
          case 'keyboard help':
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            await click(find.byTooltip('Keyboard shortcuts (F1)'));
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.text('Keyboard shortcuts'), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
