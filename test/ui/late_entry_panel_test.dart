import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/standings.dart';
import 'package:meow_chess/ui/player_panel.dart';

import '../application/late_entry_test.dart' show post, swiss;

Future<void> show(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

int points(TournamentController c, String name) {
  final e = c.event!;
  final id = e.players.firstWhere((p) => p.name == name).id;
  return standings(
    e,
    e.sectionOf(id)!,
  ).firstWhere((r) => r.player.id == id).points;
}

void main() {
  testWidgets('a walk-up joins a round in progress with half-point byes', (
    tester,
  ) async {
    final c = swiss();
    addTearDown(c.dispose);
    // Pairing runs on another isolate, which the test clock does not wait for.
    await tester.runAsync(() => post(c));
    final open = c.event!.sections.single;
    final key = GlobalKey<PlayerPanelState>();
    await show(
      tester,
      PlayerPanel(
        key: key,
        controller: c,
        sectionId: open.id,
        onClose: () {},
        memberSearch: (_) async => const [],
      ),
    );
    // The form says what joining now means before anything is saved.
    expect(find.byKey(const ValueKey('panel-late-entry')), findsOneWidget);
    expect(find.textContaining('paired from round 2'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('panel-name')),
      'Late, Larry',
    );
    await tester.enterText(find.byKey(const ValueKey('panel-rating')), '1400');
    expect(key.currentState!.commit(), isTrue);
    await tester.pumpAndSettle();
    // In the section at once, round 1 still unfinished, with half a point.
    final e = c.event!;
    final late = e.players.firstWhere((p) => p.name == 'Late, Larry');
    expect(e.sectionOf(late.id)!.id, open.id);
    expect(e.transitions, isEmpty);
    expect(points(c, 'Late, Larry'), 1);
    expect(find.textContaining('not to'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero-point byes are a choice, and the card changes them', (
    tester,
  ) async {
    final c = swiss();
    addTearDown(c.dispose);
    // Pairing runs on another isolate, which the test clock does not wait for.
    await tester.runAsync(() => post(c));
    final open = c.event!.sections.single;
    final key = GlobalKey<PlayerPanelState>();
    await show(
      tester,
      PlayerPanel(
        key: key,
        controller: c,
        sectionId: open.id,
        onClose: () {},
        memberSearch: (_) async => const [],
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('panel-name')),
      'Late, Lena',
    );
    await tester.tap(find.text('0-point byes'));
    await tester.pump();
    expect(key.currentState!.commit(), isTrue);
    await tester.pumpAndSettle();
    expect(points(c, 'Late, Lena'), 0);

    // Her card lists the round she missed, with zero and half only.
    final lena = c.event!.players.firstWhere((p) => p.name == 'Late, Lena');
    await show(
      tester,
      ListenableBuilder(
        listenable: c,
        builder: (_, _) => PlayerPanel(
          controller: c,
          player: c.event!.player(lena.id),
          onClose: () {},
        ),
      ),
    );
    final grid = find.byKey(const ValueKey('missed-bye-grid'));
    expect(grid, findsOneWidget);
    expect(
      find.descendant(
        of: grid,
        matching: find.byKey(const ValueKey('bye-1-2')),
      ),
      findsNothing,
    );
    await tester.tap(
      find.descendant(
        of: grid,
        matching: find.byKey(const ValueKey('bye-1-1')),
      ),
    );
    await tester.pumpAndSettle();
    expect(points(c, 'Late, Lena'), 1);
    // Folded, the group sums up what the grid now says.
    expect(find.textContaining('R1 ½'), findsNothing);
    await tester.tap(find.text('Rounds missed'));
    await tester.pumpAndSettle();
    expect(grid, findsNothing);
    expect(find.textContaining('R1 ½'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
