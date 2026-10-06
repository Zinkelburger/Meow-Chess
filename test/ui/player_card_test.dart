import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/player_actions.dart';
import 'package:meow_chess/ui/player_panel.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/theme.dart';

import '../support.dart';
import 'package:meow_chess/ui/select.dart';

Future<void> mountPlayers(WidgetTester tester, c) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: c,
          builder: (_, _) => PlayersView(controller: c),
        ),
      ),
    ),
  );
}

Future<void> mountPanel(WidgetTester tester, c, {String? focusField}) async {
  tester.view.physicalSize = const Size(600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: c,
          builder: (_, _) => PlayerPanel(
            controller: c,
            player: c.event!.player('p0'),
            focusField: focusField,
            onClose: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('a move in or out of a full quad must swap; a Swiss need not', () {
    final quads = fixture();
    addTearDown(quads.dispose);
    final e = quads.event!;
    final [quad1, quad2] = e.sections;
    expect(swapNeeded(e, quad1, quad2), true);

    final swiss = fixture(format: Format.swiss);
    addTearDown(swiss.dispose);
    final [a, b] = swiss.event!.sections;
    expect(swapNeeded(swiss.event!, a, b), false);

    // A quad trading with a Swiss still swaps so the quad stays at four.
    expect(swapNeeded(e, quad1, quad2.copy(format: Format.swiss)), true);
    // A Swiss player filling a short quad simply moves.
    expect(
      swapNeeded(
        e,
        quad1.copy(format: Format.swiss),
        quad2.copy(players: quad2.players.take(3).toList()),
      ),
      false,
    );
    // Round robins may exchange places but need not.
    final rr = quad2.copy(format: Format.roundRobin);
    expect(swapAllowed(quad1.copy(format: Format.swiss), rr), true);
    expect(swapNeeded(e, quad1.copy(format: Format.swiss), rr), false);
  });

  testWidgets('a Swiss row menu offers Byes and Move', (tester) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await mountPlayers(tester, c);
    await tester.tap(
      find.byKey(const ValueKey('player-p0')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    expect(find.text('Byes…'), findsOneWidget);
    expect(find.text('Move…'), findsOneWidget);
    expect(find.textContaining('Swap'), findsNothing);
    await tester.tap(find.text('Byes…'));
    await tester.pumpAndSettle();
    // The panel opens with the bye grid ready; one click requests a bye.
    expect(find.byKey(const ValueKey('bye-3-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bye-3-0')));
    await tester.pump();
    expect(c.event!.player('p0').byes[3], 0);
    expect(find.text('R3 0'), findsNothing, reason: 'the group is open');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the row menu opens from the keyboard', (tester) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mountPlayers(tester, c);
    final row = find.byKey(const ValueKey('player-p0'));
    Focus.of(
      tester.element(
        find.descendant(of: row, matching: find.byType(Row)).first,
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('Move…'), findsOneWidget);
    expect(find.textContaining('Swap'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the player card leads with withdraw and folds the extras', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await mountPanel(tester, c);
    expect(find.text('Withdraw after round 1'), findsOneWidget);
    // Team and notes stay closed until needed, showing their value.
    expect(find.byKey(const ValueKey('panel-team')), findsNothing);
    expect(find.byKey(const ValueKey('panel-notes')), findsNothing);
    expect(find.textContaining('sibling'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('panel-withdraw')));
    await tester.pump();
    expect(c.event!.player('p0').withdrawn, true);
    expect(find.text('Reinstate'), findsOneWidget);
    expect(find.text('Withdrawn'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Move in a quad exchanges places with a chosen player', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mountPanel(tester, c);
    expect(find.text('Section'), findsNothing);
    expect(find.textContaining('separate section entry'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('panel-move')));
    await tester.pump();
    tester
        .state<PlayerPanelState>(find.byType(PlayerPanel))
        .pickSection(c.event!.sections.last.id);
    await tester.pump();
    final confirm = find.byKey(const ValueKey('panel-confirm-move'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(find.text('No one'), findsNothing);
    await chooseOption(
      tester,
      find.byType(PlainSelect<String?>).last,
      'Player 04 · 1800',
    );
    await tester.tap(confirm);
    await tester.pump();
    expect(c.event!.sections.first.players, ['p4', 'p1', 'p2', 'p3']);
    expect(c.event!.sections.last.players, ['p0', 'p5', 'p6', 'p7']);
    expect(find.byKey(const ValueKey('panel-move-form')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the bye grid reads 0, ½, 1 down and rounds across', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await mountPanel(tester, c);
    await openPanelGroup(tester, 'byes');
    double top(int points) =>
        tester.getTopLeft(find.byKey(ValueKey('bye-1-$points'))).dy;
    expect(top(0), lessThan(top(1)));
    expect(top(1), lessThan(top(2)));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('bye-1-0'))).dx,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('bye-2-0'))).dx),
    );
    expect(find.text('Round'), findsOneWidget);
    expect(find.textContaining('Choose a round'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a report fix opens the group that holds its field', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mountPanel(tester, c, focusField: 'reportName');
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('panel-reportName')),
    );
    expect(field.focusNode!.hasFocus, true);
    await tester.pumpWidget(const SizedBox());
  });
}
