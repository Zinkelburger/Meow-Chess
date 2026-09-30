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
    expect(find.text('Pair next round'), findsOneWidget);
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
    // Players need no check-in to be paired.
    await tester.tap(find.text('Pair next round'));
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
      expect(find.byKey(const ValueKey('section-chip-all')), findsNothing);
      expect(find.text('Include sections'), findsOneWidget);
      await tester.tap(find.text('All sections'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(c.event!.sections.last.name).last);
      await tester.pumpAndSettle();
      expect(find.text(c.event!.sections.last.name), findsOneWidget);
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
      expect(
        c.repository.readPreference('view'),
        '${c.event!.sections.last.id}|results',
      );
    },
  );
}
