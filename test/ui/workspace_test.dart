import 'package:flutter/material.dart';
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

  testWidgets('player details use the reserved right column in both views', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await mount(tester, c);
    final player = c.event!.players.first;
    final rosterRow = find.byKey(ValueKey('player-${player.id}'));
    final before = tester.getRect(rosterRow);
    await doubleClick(
      tester,
      find.descendant(
        of: rosterRow,
        matching: find.text(player.name, findRichText: true),
      ),
    );
    final details = find.byKey(const ValueKey('player-details-area'));
    expect(tester.getRect(rosterRow), before);
    expect(tester.getTopLeft(details).dx, greaterThanOrEqualTo(before.right));
    expect(find.byKey(const ValueKey('panel-name')), findsOneWidget);
    await tester.tap(find.text('Rounds').first);
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
    expect(find.byKey(const ValueKey('section-sidebar')), findsOneWidget);
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
    expect(c.event!.games.every((g) => g.outcome == Outcome.unreported), true);
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
  });

  testWidgets('an empty event opens on Players with file import first', (
    tester,
  ) async {
    final c = TournamentController(SqliteEventRepository(':memory:'))
      ..create('Club night');
    addTearDown(c.dispose);
    await mount(tester, c);
    expect(find.text('Import players from file…'), findsOneWidget);
    expect(find.text('Paste from spreadsheet'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);
    // Nothing to post yet, and the button says why beside it.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('pair-next-round')))
          .onPressed,
      isNull,
    );
    expect(
      find.text('Create sections on the Players page first.'),
      findsOneWidget,
    );
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
    expect(find.text('8 players are not in a section yet.'), findsOneWidget);
    await tester.tap(find.text('Create sections…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('type-quad')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create 2 sections'));
    await tester.pumpAndSettle();
    expect(c.event!.sections.map((s) => s.name), ['Quad 1', 'Quad 2']);
    expect(find.text('Post round 1 · 2 sections'), findsOneWidget);
    // Players need no check-in to be paired.
    await tester.tap(find.byKey(const ValueKey('pair-next-round')));
    // Pairing runs in an isolate, outside the fake test clock.
    await tester.runAsync(() async {
      for (var i = 0; i < 200 && c.event!.games.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(c.event!.sections.every((s) => s.rounds.length == 1), true);
    expect(c.event!.games, hasLength(4));
  });

  testWidgets('ticked players move between sections in one click', (
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
    expect(find.text('2 selected'), findsOneWidget);
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
  });
  testWidgets(
    'Rounds opens one section; reports have their own scope and no pairing toolbar',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      await mount(tester, c);
      await tester.tap(find.text('Rounds'));
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
        findsNothing,
      );
      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pair-next-round')), findsNothing);
      // The sidebar stays, and choosing a section scopes the printouts.
      await tester.tap(find.byKey(const ValueKey('section-chip-all')));
      await tester.pumpAndSettle();
      expect(find.text('Print & export · All sections'), findsOneWidget);
      final last = c.event!.sections.last;
      await tester.tap(find.byKey(ValueKey('section-chip-${last.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Print & export · ${last.name}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Ctrl+J jumps by section name or number and survives a page change',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      for (var n = 3; n <= 24; n++) {
        c.addSection('Quad $n', Format.quad, 3);
      }
      await mount(tester, c);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('section-search'));
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, true);
      await tester.enterText(search, 'quad24');
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('section-chip-${c.event!.sections.last.id}')),
        findsOneWidget,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        c.repository.readPreference('view'),
        '${c.event!.sections.last.id}|players',
      );
      await tester.tap(find.text('Rounds').first);
      await tester.pumpAndSettle();
      expect(
        c.repository.readPreference('view'),
        '${c.event!.sections.last.id}|results',
      );
      await tester.enterText(search, 'section2');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        c.repository.readPreference('view'),
        '${c.event!.sections[1].id}|results',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'jump shortcut from Reports retains search focus over result autofocus',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      await mount(tester, c);
      await tester.tap(find.text('Reports').first);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('section-search')))
            .focusNode!
            .hasFocus,
        true,
      );
      await tester.enterText(
        find.byKey(const ValueKey('section-search')),
        'quad2',
      );
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      // Reports keeps its sidebar, so jumping stays on Reports.
      expect(
        c.repository.readPreference('view'),
        '${c.event!.sections.last.id}|reports',
      );
    },
  );
}
