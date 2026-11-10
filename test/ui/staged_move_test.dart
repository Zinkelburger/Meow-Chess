import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/theme.dart';

import '../support.dart';

/// The Players page, with a switch that takes it away and brings it back
/// the way visiting Pairings does.
Future<ValueNotifier<bool>> mountPlayers(
  WidgetTester tester,
  TournamentController c,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final shown = ValueNotifier(true);
  addTearDown(shown.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: Listenable.merge([c, shown]),
          builder: (_, _) => shown.value
              ? PlayersView(controller: c)
              : const Text('Another page'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shown;
}

Future<void> visitAnotherPage(
  WidgetTester tester,
  ValueNotifier<bool> shown,
) async {
  shown.value = false;
  await tester.pumpAndSettle();
  expect(find.byType(PlayersView), findsNothing);
  shown.value = true;
  await tester.pumpAndSettle();
}

Future<void> tick(WidgetTester tester, String id) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(ValueKey('player-$id')),
      matching: find.byType(PlainCheckbox),
    ),
  );
  await tester.pump();
}

const changed = 'The event changed. Choose the destination and review again.';

void main() {
  testWidgets('a staged bulk move still applies after visiting another page', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    // A section transfer waits for the round's games to finish.
    for (final g in c.event!.games) {
      c.recordResult(g.id, Outcome.draw);
    }
    final [from, to] = c.event!.sections;
    final mover = from.players.first;
    final shown = await mountPlayers(tester, c);
    await tick(tester, mover);
    await tester.tap(find.byKey(ValueKey('move-to-${to.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Move to ${to.name}?'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('move-reason')),
      'Asked to play up',
    );

    await visitAnotherPage(tester, shown);
    expect(find.text('Move to ${to.name}?'), findsOneWidget);
    expect(find.text('Asked to play up'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await tester.pumpAndSettle();
    expect(find.text(changed), findsNothing);
    expect(find.text('Players moved'), findsOneWidget);
    expect(c.event!.sectionOf(mover)!.id, to.id);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a staged bulk move is refused once the event really changed', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    // A section transfer waits for the round's games to finish.
    for (final g in c.event!.games) {
      c.recordResult(g.id, Outcome.draw);
    }
    final [from, to] = c.event!.sections;
    final mover = from.players.first;
    final shown = await mountPlayers(tester, c);
    await tick(tester, mover);
    await tester.tap(find.byKey(ValueKey('move-to-${to.id}')));
    await tester.pumpAndSettle();

    shown.value = false;
    await tester.pumpAndSettle();
    c.savePlayer(c.event!.player(to.players.first).copy(team: 'Knights'));
    shown.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Move to ${to.name}?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await tester.pumpAndSettle();
    expect(find.text(changed), findsOneWidget);
    expect(c.event!.sectionOf(mover)!.id, from.id);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a swap waiting for its confirmation survives a page switch', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    final [quad1, quad2] = c.event!.sections;
    final a = quad1.players.first, b = quad2.players.first;
    final shown = await mountPlayers(tester, c);
    await tick(tester, a);
    await tick(tester, b);
    await tester.tap(find.text('Swap sections'));
    await tester.pumpAndSettle();
    final confirm = find.textContaining('Confirm swap:');
    expect(confirm, findsOneWidget);

    await visitAnotherPage(tester, shown);
    expect(confirm, findsOneWidget);
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(c.event!.sectionOf(a)!.id, quad2.id);
    expect(c.event!.sectionOf(b)!.id, quad1.id);
    expect(find.text('Players swapped'), findsOneWidget);
    expect(find.byKey(const ValueKey('done-undo')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
