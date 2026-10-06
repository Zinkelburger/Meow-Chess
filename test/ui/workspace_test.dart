import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../support.dart';

void main() {
  Future<void> mount(WidgetTester tester, TournamentController c) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Workspace(
          controller: c,
          path: ':memory:',
          onClose: () {},
          onTheme: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> doubleClick(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'player details fit beside standings and preserve result boards',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      await mount(tester, c);
      final player = c.event!.players.first;
      final rosterRow = find.byKey(ValueKey('player-${player.id}'));
      await doubleClick(
        tester,
        find.descendant(
          of: rosterRow,
          matching: find.text(player.name, findRichText: true),
        ),
      );
      final details = find.byKey(const ValueKey('player-details-area'));
      expect(
        tester.getRect(rosterRow).right,
        lessThanOrEqualTo(tester.getTopLeft(details).dx),
      );
      expect(tester.getRect(rosterRow).width, greaterThan(0));
      expect(find.byKey(const ValueKey('panel-name')), findsOneWidget);
      await tester.tap(find.text('Pairings').first);
      await tester.pumpAndSettle();
      final game = c.event!.sections.first.rounds.single.games.first;
      final board = find.byKey(ValueKey('game-${game.id}'));
      final boardBefore = tester.getRect(board);
      await doubleClick(
        tester,
        find.byKey(ValueKey('round-player-${game.id}-${game.white}')),
      );
      expect(tester.getTopLeft(board), boardBefore.topLeft);
      expect(tester.getSize(board).width, boardBefore.width);
      expect(
        tester.getTopLeft(details).dx,
        greaterThanOrEqualTo(boardBefore.right),
      );
      expect(find.byKey(const ValueKey('section-tabs')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('panel-name')))
            .controller!
            .text,
        c.event!.player(game.white).name,
      );
      await tester.enterText(
        find.byKey(const ValueKey('panel-name')),
        'Edited name',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await doubleClick(
        tester,
        find.byKey(ValueKey('round-player-${game.id}-${game.black}')),
      );
      expect(c.event!.player(game.white).name, 'Edited name');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('panel-name')))
            .controller!
            .text,
        c.event!.player(game.black).name,
      );
      expect(
        c.event!.games.every((g) => g.outcome == Outcome.unreported),
        true,
      );
      await tester.tap(find.byTooltip('Close (Esc)'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('panel-name')), findsNothing);
      expect(tester.getTopLeft(board), boardBefore.topLeft);
      expect(tester.getSize(board).width, boardBefore.width);
      tester.view.physicalSize = const Size(1100, 900);
      await tester.pumpAndSettle();
      await doubleClick(
        tester,
        find.byKey(ValueKey('round-player-${game.id}-${game.white}')),
      );
      expect(tester.getRect(details).right, lessThanOrEqualTo(1100));
      expect(
        find.byKey(const ValueKey('panel-name')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [1100.0, 1400.0]) {
    testWidgets(
      'side panels preserve result boards and roster access at width $width',
      (tester) async {
        final c = fixture();
        addTearDown(c.dispose);
        c.post((await tester.runAsync(() => c.propose()))!);
        await mount(tester, c);
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        final player = c.event!.players.first;
        final game = c.event!.games.first;
        for (final rounds in [false, true]) {
          if (rounds) {
            await tester.tap(find.text('Pairings').first);
            await tester.pumpAndSettle();
          }
          final row = find.byKey(
            ValueKey(rounds ? 'game-${game.id}' : 'player-${player.id}'),
          );
          final before = tester.getRect(row);
          await doubleClick(
            tester,
            rounds
                ? find.byKey(ValueKey('round-player-${game.id}-${game.white}'))
                : find.descendant(
                    of: row,
                    matching: find.text(player.name, findRichText: true),
                  ),
          );
          expect(find.byKey(const ValueKey('panel-name')), findsOneWidget);
          if (rounds) {
            expect(tester.getRect(row), before);
          } else {
            expect(
              tester
                  .getRect(find.byKey(const ValueKey('standings-pane')))
                  .right,
              lessThanOrEqualTo(
                tester
                    .getTopLeft(
                      find.byKey(const ValueKey('player-details-area')),
                    )
                    .dx,
              ),
            );
          }
          // Replacing the embedded editor with workspace tools must use the
          // same space, including tools wider than the player editor.
          for (final target in [
            find.byTooltip('Keyboard shortcuts (F1)'),
            find.byKey(const ValueKey('event-details')),
            find.byTooltip('History (Ctrl+H)'),
          ]) {
            await tester.tap(target);
            await tester.pumpAndSettle();
            if (rounds) expect(tester.getRect(row), before);
            expect(find.byKey(const ValueKey('panel-name')), findsNothing);
            final historyClose = find.byTooltip('Close history (Ctrl+H)');
            await tester.tap(
              historyClose.evaluate().isNotEmpty
                  ? historyClose
                  : find.byTooltip('Close (Esc)'),
            );
            await tester.pumpAndSettle();
            expect(tester.getRect(row), before);
            expect(tester.takeException(), isNull);
          }
        }
      },
    );
  }

  testWidgets('an empty event opens on Players with Add from URL first', (
    tester,
  ) async {
    final c = TournamentController(SqliteEventRepository(':memory:'))
      ..create('Club night');
    addTearDown(c.dispose);
    await mount(tester, c);
    expect(find.text('Overview'), findsNothing);
    final labels = ['Add from URL', 'Import file…', 'Paste', 'Add one player'];
    for (final label in labels) {
      expect(find.widgetWithText(OutlinedButton, label), findsOneWidget);
    }
    // All four fit on one row at a normal window width.
    final rows = labels.map((l) => tester.getTopLeft(find.text(l)).dy).toSet();
    expect(rows, hasLength(1));
    expect(find.byKey(const ValueKey('player-tools')), findsNothing);
    expect(find.byKey(const ValueKey('pair-next-round')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('add-from-url')));
    await tester.pumpAndSettle();
    expect(find.text('Fetch players'), findsOneWidget);
  });

  testWidgets('entry panels focus the first field and support Tab and Enter', (
    tester,
  ) async {
    final c = TournamentController(SqliteEventRepository(':memory:'))
      ..create('Club night');
    addTearDown(c.dispose);
    await mount(tester, c);

    void expectFocused(String key) {
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.focusNode.hasFocus, true, reason: key);
    }

    await tester.tap(find.text('Add one player'));
    await tester.pumpAndSettle();
    expectFocused('panel-name');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: 'Keyboard Player'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expectFocused('panel-memberId');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: '12345678'),
    );
    // The inline identity tools remain reachable by keyboard before Rating.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Find by name.
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Check ID.
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Rating.
    await tester.pumpAndSettle();
    expectFocused('panel-rating');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: '1500'),
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.event!.players.single.name, 'Keyboard Player');
    expect(c.event!.players.single.memberId, '12345678');
    expect(c.event!.players.single.rating, 1500);
    expectFocused('panel-name');

    // Switching panels claims focus even while the previous field has it.
    await tester.tap(find.byKey(const ValueKey('event-details')));
    await tester.pumpAndSettle();
    expectFocused('event-name');
    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add player'));
    await tester.pumpAndSettle();
    expectFocused('panel-name');
    await tester.tap(find.byKey(const ValueKey('player-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expectFocused('paste-roster');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: 'Name,Rating\nPasted Player,1200'),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('confirm-roster-import')), findsOneWidget);
    expect(c.event!.players.length, 1);
    // The review is a window over the workspace; closing it returns to
    // the pasted rows.
    await tester.tap(find.byTooltip('Close (Esc)').last);
    await tester.pumpAndSettle();
    expectFocused('paste-roster');
    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-section')));
    await tester.pumpAndSettle();
    expectFocused('new-section-name');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: 'Open'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expectFocused('new-section-rounds');
    tester.testTextInput.updateEditingValue(const TextEditingValue(text: '3'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.event!.sections.single.name, 'Open');
    expect(tester.takeException(), isNull);
  });

  testWidgets('players without sections are offered a tournament type', (
    tester,
  ) async {
    final c = TournamentController(SqliteEventRepository(':memory:'))
      ..create('Club night');
    addTearDown(c.dispose);
    c.importPlayers([
      for (var i = 0; i < 8; i++)
        Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 50),
    ]);
    await mount(tester, c);
    // Sections come from the one New section action beside the tabs.
    expect(find.text('Create sections…'), findsNothing);
    expect(find.byKey(const ValueKey('print-standings')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('new-section')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quads'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create 2 sections'));
    await tester.pumpAndSettle();
    expect(c.event!.sections.map((s) => s.name), ['Quad 1', 'Quad 2']);
    expect(find.byKey(const ValueKey('pair-next-round')), findsNothing);
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();
    // A four-player quad exposes all three fixed rounds immediately.
    expect(find.byKey(const ValueKey('pair-next-round')), findsNothing);
    expect(c.event!.games, isEmpty);
    expect(c.pairingEvent.sections.every((s) => s.rounds.length == 3), true);
    expect(c.pairingEvent.games, hasLength(12));
    final game = c.pairingEvent.games.first;
    await tester.tap(find.byKey(ValueKey('score-${game.id}-w')));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    expect(
      c.event!.games.firstWhere((g) => g.id == game.id).outcome,
      Outcome.whiteWin,
    );
  });

  testWidgets('ticked players move between sections at once before play', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mount(tester, c);
    final [quad1, quad2] = c.event!.sections;
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('player-${quad1.players.first}')),
        matching: find.byType(PlainCheckbox),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('player-${quad2.players.first}')),
        matching: find.byType(PlainCheckbox),
      ),
    );
    await tester.pump();
    // Bulk actions open at the right; the table does not move.
    expect(find.text('2 players selected'), findsOneWidget);
    // Swap: move one Quad 2 player up, then the Quad 1 player down.
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('player-${quad1.players.first}')),
        matching: find.byType(PlainCheckbox),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('move-to-${quad1.id}')));
    await tester.pumpAndSettle();
    // Before play a move is a roster edit: no confirm step, Undo beside it,
    // and the quad left at five says so.
    expect(find.text('Players moved'), findsOneWidget);
    expect(
      find.textContaining(
        '${quad1.name} now has 5 players. '
        '${quad2.name} now has 3 players. A quad needs four.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('done-undo')), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('player-${quad1.players.first}')),
        matching: find.byType(PlainCheckbox),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('move-to-${quad2.id}')));
    await tester.pumpAndSettle();
    final [a, b] = c.event!.sections;
    expect(a.players, [...quad1.players.skip(1), quad2.players.first]);
    expect(b.players, [...quad2.players.skip(1), quad1.players.first]);
    // A pre-round move is a roster edit: both stay quads.
    expect([a.format, b.format], [Format.quad, Format.quad]);
    expect(find.textContaining('selected'), findsNothing);
    expect(find.text('Moved 1 player to ${b.name}.'), findsOneWidget);
  });
  testWidgets('shift-click ticks a range; right-click acts on all of it', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mount(tester, c);
    final [quad1, quad2] = c.event!.sections;
    Finder box(String id) => find.descendant(
      of: find.byKey(ValueKey('player-$id')),
      matching: find.byType(PlainCheckbox),
    );
    await tester.tap(box(quad1.players[1]));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(box(quad2.players[0]));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('4 players selected'), findsOneWidget);
    // Right-clicking a ticked row offers the move for the whole selection.
    await tester.tap(
      find.byKey(ValueKey('player-${quad1.players[2]}')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    expect(find.text('Move 4 players to'), findsOneWidget);
    // The same words as the selection panel's button.
    expect(find.text('Remove 4 players'), findsNWidgets(2));
    expect(find.text('Byes…'), findsNothing);
    await tester.tap(find.text(quad2.name).last);
    await tester.pumpAndSettle();
    expect(c.event!.sections.last.players, hasLength(7));
    expect(find.text('Players moved'), findsOneWidget);
  });

  testWidgets('ticked players are removed at once, with Undo', (tester) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mount(tester, c);
    final quad1 = c.event!.sections.first;
    for (final id in quad1.players.take(2)) {
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('player-$id')),
          matching: find.byType(PlainCheckbox),
        ),
      );
    }
    await tester.pump();
    expect(find.byKey(const ValueKey('selection-withdraw')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('selection-remove')));
    await tester.pumpAndSettle();
    expect(c.event!.players, hasLength(6));
    expect(find.text('Players removed'), findsOneWidget);
    expect(find.textContaining('selected'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('done-undo')));
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.players, quad1.players);
    // Delete on a focused row removes that player too.
    Focus.of(
      tester.element(find.text(c.event!.player(quad1.players.last).name)),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(c.event!.players.any((p) => p.id == quad1.players.last), false);
  });

  testWidgets('the card offers Remove until the section is paired', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mount(tester, c);
    await tester.tap(find.text('Player 00'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('panel-withdraw')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('panel-remove')));
    await tester.pumpAndSettle();
    expect(find.text('Player removed'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('done-undo')));
    await tester.pumpAndSettle();
    c.post((await tester.runAsync(() => c.propose()))!);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Player 00'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('panel-remove')), findsNothing);
    expect(find.byKey(const ValueKey('panel-withdraw')), findsOneWidget);
  });

  testWidgets(
    'views keep their section scope; the report covers every section',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      await mount(tester, c);
      await tester.tap(find.text('Pairings'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          ValueKey(
            'game-${c.event!.sections.first.rounds.single.games.first.id}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey(
            'game-${c.event!.sections.last.rounds.single.games.first.id}',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pair-next-round')), findsNothing);
      // The rating report is event-wide, so Export has no section strip;
      // returning to Pairings brings the strip back.
      expect(find.byKey(const ValueKey('rating-report')), findsOneWidget);
      expect(find.byKey(const ValueKey('section-tabs')), findsNothing);
      await tester.tap(find.text('Pairings').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('section-tabs')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('All sections stays visible when scrolling many section tabs', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    for (var n = 3; n <= 24; n++) {
      c.addSection('Quad $n', Format.quad, 3);
    }
    await mount(tester, c);
    expect(find.byKey(const ValueKey('section-search')), findsNothing);
    final all = find.byKey(const ValueKey('section-chip-all'));
    final position = tester.getRect(all);
    final last = find.byKey(
      ValueKey('section-chip-${c.event!.sections.last.id}'),
    );
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(tester.getRect(all), position);
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(c.repository.readPreference('view'), '|players');
    expect(tester.takeException(), isNull);
  });

  testWidgets('New Section creates nothing until the form is submitted', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mount(tester, c);
    final count = c.event!.sections.length;
    await tester.tap(find.byKey(const ValueKey('new-section')));
    await tester.pumpAndSettle();
    expect(c.event!.sections.length, count);
    expect(find.byKey(const ValueKey('new-section-panel')), findsOneWidget);
    // Everyone already has a section and nobody is ticked: it starts empty.
    expect(find.text('Create empty section'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('new-section-rounds')),
      '4',
    );
    await tester.tap(find.byKey(const ValueKey('create-section')));
    await tester.pumpAndSettle();
    expect(c.event!.sections.length, count);
    expect(find.text('Enter the section name.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('new-section-name')),
      'Extra games',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('new-section-more')));
    await tester.tap(find.byKey(const ValueKey('new-section-more')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('new-section-side-games')),
    );
    await tester.tap(find.byKey(const ValueKey('new-section-side-games')));
    await tester.tap(find.byKey(const ValueKey('create-section')));
    await tester.pumpAndSettle();
    expect(c.event!.sections.length, count + 1);
    final created = c.event!.sections.last;
    expect(created.name, 'Extra games');
    expect(created.players, isEmpty);
    expect(created.sideGames, true);
    expect(created.plannedRounds, 4);
    expect(find.byKey(const ValueKey('new-section-panel')), findsNothing);
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pair-side-game')));
    await tester.pumpAndSettle();
    expect(find.text('Pair a side game'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-section')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('new-section-name')))
          .controller!
          .text,
      isEmpty,
    );
    expect(c.event!.sections.length, count + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section context menu deletes unplayed sections with undo', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mount(tester, c);
    final first = c.event!.sections.first;
    await tester.tap(
      find.byKey(ValueKey('section-chip-${first.id}')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete section'));
    await tester.pumpAndSettle();
    expect(c.event!.sections.any((s) => s.id == first.id), false);
    expect(c.event!.players.length, 8);
    expect(find.byKey(const ValueKey('section-chip-all')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('undo')));
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.id, first.id);
    expect(tester.takeException(), isNull);
  });
}
