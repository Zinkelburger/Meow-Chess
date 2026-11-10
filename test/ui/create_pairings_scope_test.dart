import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/results_view.dart';

import '../support.dart';
import 'workspace_host.dart';

Future<void> press(WidgetTester tester, TournamentController c) async {
  final before = c.event!.revision;
  await tester.tap(find.byKey(const ValueKey('pair-next-round')));
  await tester.runAsync(() async {
    for (var i = 0; i < 200 && c.event!.revision == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  await tester.pumpAndSettle();
}

void finish(TournamentController c, String sectionId) {
  final s = c.event!.sections.firstWhere((s) => s.id == sectionId);
  for (final g in s.rounds.lastOrNull?.games ?? const <Game>[]) {
    if (!g.outcome.resolved) c.recordResult(g.id, Outcome.draw);
  }
}

void main() {
  final button = find.byKey(const ValueKey('pair-next-round'));
  final why = find.byKey(const ValueKey('post-blocked'));

  testWidgets('Create pairings pairs the chosen section and says which', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    await mountWorkspace(tester, c);
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();

    // All sections: every ready section, as the label says.
    expect(
      find.descendant(
        of: button,
        matching: find.text('Create pairings · Round 1 · 2 sections'),
      ),
      findsOneWidget,
    );

    await pickTab(tester, q1.id);
    expect(
      find.bySemanticsLabel('Create pairings · ${q1.name} · Round 1'),
      findsOneWidget,
    );
    await press(tester, c);
    // Only the chosen section is paired; the other, though ready, is not.
    expect(c.event!.sections.map((s) => s.rounds.length), [1, 0]);
    // Still on that section, on the Pairings page.
    expect(find.byType(ResultsView), findsOneWidget);
    expect(find.byKey(ValueKey('section-menu-${q1.id}')), findsOneWidget);
    // Why it is held is about this section.
    expect(button, findsNothing);
    expect(tester.widget<Text>(why).data, 'Enter 2 results first.');

    // The other section's tab offers its own round.
    await pickTab(tester, q2.id);
    expect(
      find.bySemanticsLabel('Create pairings · ${q2.name} · Round 1'),
      findsOneWidget,
    );
    expect(why, findsNothing);

    // All sections now pairs just the one that is ready.
    await pickTab(tester, 'all');
    expect(
      find.descendant(
        of: button,
        matching: find.text('Create pairings · Round 1 · 1 section'),
      ),
      findsOneWidget,
    );
    expect(tester.widget<Text>(why).data, '${q1.name} waits for 2 results.');
    await press(tester, c);
    expect(c.event!.sections.map((s) => s.rounds.length), [1, 1]);

    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets(
    'a finished section says so; only a finished event offers export',
    (tester) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      final [q1, q2] = c.event!.sections;
      for (var round = 0; round < q1.plannedRounds; round++) {
        c.post((await tester.runAsync(() => c.propose(sectionId: q1.id)))!);
        finish(c, q1.id);
      }
      await mountWorkspace(tester, c);
      await tester.tap(find.text('Pairings').first);
      await tester.pumpAndSettle();
      await pickTab(tester, q1.id);
      expect(button, findsNothing);
      expect(find.byKey(const ValueKey('event-complete')), findsNothing);
      expect(find.text('Finish & export'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('section-complete')))
            .data,
        '${q1.name} has played all its rounds',
      );

      for (var round = 0; round < q2.plannedRounds; round++) {
        c.post((await tester.runAsync(() => c.propose(sectionId: q2.id)))!);
        finish(c, q2.id);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('section-complete')), findsNothing);
      expect(find.byKey(const ValueKey('event-complete')), findsOneWidget);
      expect(find.text('Finish & export'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('fixed quads need no button; side games pair by hand', (
    tester,
  ) async {
    final c = fixture(count: 12);
    addTearDown(c.dispose);
    final [quad, swiss, side] = c.event!.sections;
    c.change(
      'Mix formats',
      c.event!.copy(
        sections: [
          quad,
          swiss.copy(format: Format.swiss),
          side.copy(format: Format.swiss, sideGames: true),
        ],
      ),
    );
    await mountWorkspace(tester, c);
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();
    await pickTab(tester, quad.id);
    expect(button, findsNothing);
    expect(why, findsNothing);
    await pickTab(tester, side.id);
    expect(button, findsNothing);
    expect(find.text('Pair a side game'), findsOneWidget);
    await pickTab(tester, swiss.id);
    expect(button, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'a long section name is cut short, not the round, at ${scale}x',
      (tester) async {
        final c = fixture(format: Format.swiss);
        addTearDown(c.dispose);
        final first = c.event!.sections.first;
        c.change(
          'Long name',
          c.event!.copy(
            sections: [
              for (final s in c.event!.sections)
                s.id == first.id
                    ? s.copy(
                        name:
                            'Under 1200 Reserve and Novice Scholastic '
                            'Championship of the Greater Metropolitan Area',
                      )
                    : s,
            ],
          ),
        );
        await mountWorkspace(
          tester,
          c,
          size: const Size(1024, 640),
          scale: scale,
        );
        await tester.tap(find.text('Pairings').first);
        await tester.pumpAndSettle();
        await pickTab(tester, first.id);
        expect(tester.takeException(), isNull);
        expect(button, findsOneWidget);
        // The words around the name are whole; only the name gives way.
        for (final part in ['Create pairings · ', ' · Round 1']) {
          final text = find.descendant(of: button, matching: find.text(part));
          expect(text, findsOneWidget);
          expect(
            tester.renderObject<RenderBox>(text).size.width,
            greaterThanOrEqualTo(
              tester
                  .renderObject<RenderBox>(text)
                  .getMaxIntrinsicWidth(double.infinity),
            ),
          );
        }
        final window = tester.getRect(find.byType(Scaffold));
        expect(tester.getRect(button).right, lessThanOrEqualTo(window.right));
        expect(tester.getRect(button).left, greaterThanOrEqualTo(window.left));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('no empty line is kept under the pages when no section pairs', (
    tester,
  ) async {
    // Quads keep a fixed schedule: no button for any tab.
    final c = fixture();
    addTearDown(c.dispose);
    await mountWorkspace(tester, c, size: const Size(1024, 640));
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-action-line')), findsNothing);
    final pages = tester.getRect(find.text('Pairings').first);
    final tabs = tester.getRect(find.byKey(const ValueKey('section-tabs')));
    expect(tabs.top - pages.bottom, lessThan(24));
    await pickTab(tester, c.event!.sections.first.id);
    expect(find.byKey(const ValueKey('page-action-line')), findsNothing);
    expect(
      tester.getRect(find.byKey(const ValueKey('section-tabs'))).top,
      tabs.top,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'with a button for some tab, changing tab never shifts the page',
    (tester) async {
      final c = fixture(count: 12);
      addTearDown(c.dispose);
      final [quad, swiss, _] = c.event!.sections;
      c.change(
        'One Swiss',
        c.event!.copy(
          sections: [
            for (final s in c.event!.sections)
              s.id == swiss.id ? s.copy(format: Format.swiss) : s,
          ],
        ),
      );
      await mountWorkspace(tester, c, size: const Size(1024, 640));
      await tester.tap(find.text('Pairings').first);
      await tester.pumpAndSettle();
      double top() =>
          tester.getRect(find.byKey(const ValueKey('section-tabs'))).top;
      expect(button, findsOneWidget);
      final all = top();
      // The quad's tab has no button, yet keeps the line.
      await pickTab(tester, quad.id);
      expect(button, findsNothing);
      expect(find.byKey(const ValueKey('page-action-line')), findsOneWidget);
      expect(top(), all);
      await pickTab(tester, swiss.id);
      expect(button, findsOneWidget);
      expect(top(), all);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
