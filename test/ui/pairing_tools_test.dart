import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/workspace_actions.dart';
import 'package:meow_chess/ui/reports_view.dart';
import '../support.dart';

void main() {
  testWidgets(
    'section setup saves scoring and acceleration, then locks played policies',
    (tester) async {
      final c = fixture(count: 6);
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => WorkspaceActions(
                  context,
                  c,
                ).sectionSettings(c.event!.sections.single.id),
                child: const Text('Settings'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('field-win')));
      await tester.enterText(find.byKey(const ValueKey('field-win')), '3');
      await tester.ensureVisible(
        find.byKey(const ValueKey('field-acceleration')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('field-acceleration')),
        '1: 1,1\n2: 1,1',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(c.event!.sections.single.scoring.win, 6);
      expect(c.event!.sections.single.acceleration, {
        'p0': [2, 2],
        'p1': [2, 2],
      });
      c.post((await tester.runAsync(() => c.propose()))!);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-win')), findsNothing);
      expect(find.byKey(const ValueKey('field-acceleration')), findsNothing);
      expect(find.byKey(const ValueKey('field-tiebreak')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rating inspector reports local evidence separately from upload acceptance',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.change(
        'Report details',
        c.event!.copy(
          date: '2024-01-01',
          tdId: '12345678',
          affiliateId: 'A1234567',
          city: 'Boston',
          state: 'MA',
          zip: '02116',
          players: [for (final p in c.event!.players) p.copy(state: 'MA')],
        ),
      );
      for (var n = 0; n < 3; n++) {
        c.post((await tester.runAsync(() => c.propose()))!);
        for (final g in c.event!.sections.single.rounds.last.games) {
          c.recordResult(g.id, Outcome.draw);
        }
      }
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReportsView(controller: c)),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('check-rating-files')),
      );
      await tester.tap(find.byKey(const ValueKey('check-rating-files')));
      await tester.pumpAndSettle();
      expect(find.text('Local rating file checks passed'), findsOneWidget);
      expect(
        find.textContaining('upload acceptance has not been tested'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
