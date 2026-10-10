import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/event_panel.dart';
import 'package:meow_chess/ui/side_game_panel.dart';
import '../support.dart';

void main() {
  testWidgets(
    'side-game panel selects opponents and posts independent entries',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.change(
        'Create side-game sections',
        c.event!.copy(
          sections: [
            ...c.event!.sections,
            Section(id: 'side-a', name: 'Side A', players: [], sideGames: true),
            Section(id: 'side-b', name: 'Side B', players: [], sideGames: true),
          ],
        ),
      );
      String? paired;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SideGamePanel(
              controller: c,
              sectionId: 'side-b',
              onClose: () {},
              onPaired: (id) => paired = id,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('side-game-white')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Player 00').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('side-game-black')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Player 01').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('post-side-game')));
      await tester.tap(find.byKey(const ValueKey('post-side-game')));
      await tester.pump();
      expect(paired, 'side-b');
      expect(
        c.event!.sections.firstWhere((s) => s.id == 'side-a').rounds,
        isEmpty,
      );
      final side = c.event!.sections.firstWhere((s) => s.id == paired);
      expect(side.sideGames, isTrue);
      expect(side.rounds.single.games.single.outcome, Outcome.unreported);
      expect(c.event!.sections.first.rounds, isEmpty);
    },
  );

  testWidgets(
    'event details default to shared places and enable tie-breaks explicitly',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventPanel(controller: c, onClose: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.event!.useTiebreaks, isFalse);
      // Tie-breaks stay folded away until the TD opens them.
      expect(find.byKey(const ValueKey('event-use-tiebreaks')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('event-group-tiebreaks')),
      );
      await tester.tap(find.byKey(const ValueKey('event-group-tiebreaks')));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('event-use-tiebreaks'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(c.event!.useTiebreaks, isTrue);
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pump();
      expect(c.event!.useTiebreaks, isFalse);
    },
  );
}
