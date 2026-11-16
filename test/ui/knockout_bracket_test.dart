import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/formats/knockout_view.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';

import '../support.dart';

Future<void> mount(
  WidgetTester tester,
  TournamentController c,
  Widget Function() child, {
  Size size = const Size(1600, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: ListenableBuilder(listenable: c, builder: (_, _) => child()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Two four-player knockouts of one-game matches the director decides,
/// every semifinal drawn, so each bracket offers "Advance…" twice.
Future<TournamentController> drawnKnockouts(WidgetTester tester) async {
  final c = fixture();
  addTearDown(c.dispose);
  c.change(
    'Use knockouts',
    c.event!.copy(
      sections: [
        for (final (i, s) in c.event!.sections.indexed)
          s.copy(
            name: 'Knockout ${'AB'[i]}',
            format: Format.knockout,
            plannedRounds: 2,
            bracket: Bracket.fromJson(const {
              'gamesPerMatch': 1,
              'tiebreak': 'none',
            }),
          ),
      ],
    ),
  );
  for (final s in c.event!.sections) {
    c.post((await tester.runAsync(() => c.propose(sectionId: s.id)))!);
  }
  for (final g in c.event!.games.toList()) {
    c.recordResult(g.id, Outcome.draw);
  }
  return c;
}

Finder bracket(Section s) => find.byWidgetPredicate(
  (w) => w is KnockoutBracketView && w.section.id == s.id,
);

void main() {
  testWidgets('a knockout bracket lays out on the Pairings page', (
    tester,
  ) async {
    final c = await drawnKnockouts(tester);
    final s = c.event!.sections.first;
    // The bracket used to sit in an unbounded horizontal scroll, where its
    // last column could not fill what was left, and threw on every row.
    await mount(tester, c, () => ResultsView(controller: c, sectionId: s.id));
    expect(tester.takeException(), isNull);
    expect(bracket(s), findsOneWidget);
    expect(find.byKey(const ValueKey('knockout-placings')), findsOneWidget);
    expect(find.text('Advance…'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('every knockout lays out on the all-sections crosstable', (
    tester,
  ) async {
    final c = await drawnKnockouts(tester);
    await mount(
      tester,
      c,
      () => PlayersView(controller: c, standingsOnly: true),
      size: const Size(1400, 1400),
    );
    expect(tester.takeException(), isNull);
    for (final s in c.event!.sections) {
      expect(bracket(s), findsOneWidget);
      expect(find.byKey(ValueKey(('knockout', s.id))), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('knockout-placings')), findsNWidgets(2));
    expect(find.text('Advance…'), findsNWidgets(4));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a search keeps the reason typed for a drawn knockout match', (
    tester,
  ) async {
    final c = await drawnKnockouts(tester);
    await mount(
      tester,
      c,
      () => PlayersView(controller: c, standingsOnly: true),
      size: const Size(1400, 1400),
    );
    final [a, b] = c.event!.sections;
    // Knockout B's first drawn board is board 3, after A's two.
    final reason = find.descendant(
      of: bracket(b),
      matching: find.byKey(const ValueKey('advance-reason-3')),
    );
    await tester.enterText(reason, 'Coin toss');
    // A search matching only Knockout B's players leaves A's bracket out, so
    // B's moves up the table; it keeps its own state, not A's.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('player-search')),
        matching: find.byType(TextField),
      ),
      c.event!.player(b.players.first).name,
    );
    await tester.pumpAndSettle();
    expect(bracket(a), findsNothing);
    expect(tester.widget<TextField>(reason).controller!.text, 'Coin toss');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
