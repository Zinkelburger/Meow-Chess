import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import '../support.dart';
import 'standings_test.dart' show mountPlayers;

void main() {
  testWidgets(
    'Players tools keeps estimates optional and live without result columns',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      for (final p in c.event!.players) {
        c.savePlayer(p.copy(rating: 2190));
      }
      c.post((await tester.runAsync(() => c.propose()))!);
      final game = c.event!.games.first;
      await mountPlayers(tester, c, standingsOnly: false);
      expect(find.text('R1'), findsNothing);
      expect(find.text('Pts'), findsNothing);
      expect(find.text('USCF expires'), findsOneWidget);
      final cell = ValueKey('rating-preview-${game.white}');
      expect(find.byKey(cell), findsNothing);
      await tester.tap(find.byKey(const ValueKey('player-tools')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show rating estimates'));
      await tester.pumpAndSettle();
      c.recordResult(game.id, Outcome.whiteWin);
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(cell)).data, '≈2200 (+10)');
      expect(c.event!.player(game.white).rating, 2190);
      await tester.pumpWidget(const SizedBox());
      await mountPlayers(tester, c, standingsOnly: false);
      expect(find.byKey(cell), findsOneWidget);
      expect(find.text('Pts'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'saved rating preview preferences do not add estimates to standings',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final game = c.event!.games.first;
      c.recordResult(game.id, Outcome.whiteWin);
      c.workspaceState.writeMap('players-view-all', {
        'showRatingPreview': true,
      });
      final before = c.event!.encode();
      await mountPlayers(tester, c);
      expect(find.byKey(const ValueKey('show-rating-preview')), findsNothing);
      expect(
        find.byKey(ValueKey('rating-preview-${game.white}')),
        findsNothing,
      );
      expect(find.text('Est. regular (Δ)'), findsNothing);
      expect(c.event!.encode(), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
