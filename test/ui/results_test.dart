import 'package:meow_chess/ui/result_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';

void main() {
  testWidgets('add and paste players in the side panel, no dialogs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture();
    addTearDown(c.dispose);
    final before = c.event!.players.length;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => PlayersView(controller: c),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add player'));
    await tester.pump();
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('panel-name')), 'New One');
    await tester.enterText(find.byKey(const ValueKey('panel-rating')), 'UNR');
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(c.event!.players.length, before + 1);
    expect(c.event!.players.last.rating, 0);
    // The form clears for the next player.
    expect(
      find.text('Added New One. Enter the next player, or close.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('player-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('paste-roster')),
      'Pasted Person,,1500',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review import'));
    await tester.pump();
    expect(c.event!.players.length, before + 1);
    await tester.tap(find.byKey(const ValueKey('confirm-roster-import')));
    await tester.pump();
    expect(c.event!.players.any((p) => p.name == 'Pasted Person'), true);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('Imported 1 players'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(c.event!.players.any((p) => p.name == 'Pasted Person'), false);
    expect(find.text('Imported 1 players'), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
  testWidgets(
    '1/0/D commit and advance once; key repeat and search cannot enter results',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixture(count: 12);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final games = c.event!.games.toList();
      await tester.pumpWidget(
        MaterialApp(
          theme: meowTheme(Brightness.dark),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => ResultsView(controller: c),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(ValueKey('game-${games[0].id}')));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit1);
      await tester.pump();
      expect(c.event!.games.where((g) => g.outcome.resolved).length, 1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pump();
      expect(c.event!.games.take(3).map((g) => g.outcome), [
        Outcome.whiteWin,
        Outcome.blackWin,
        Outcome.draw,
      ]);
      await tester.tap(find.byKey(const ValueKey('board-search')));
      await tester.enterText(find.byKey(const ValueKey('board-search')), '1');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.pump();
      expect(c.event!.games.where((g) => g.outcome.resolved).length, 3);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
  testWidgets(
    'missing-only traversal does not skip rows and one undo restores one board',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixture();
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final games = c.event!.games.toList();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => ResultsView(controller: c),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Missing only'));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('game-${games.first.id}')));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pump();
      expect(c.event!.games.take(2).map((g) => g.outcome), [
        Outcome.blackWin,
        Outcome.draw,
      ]);
      c.undo();
      await tester.pump();
      expect(c.event!.games.take(2).map((g) => g.outcome), [
        Outcome.blackWin,
        Outcome.unreported,
      ]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
  testWidgets('player name input never dispatches a result shortcut', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlayersView(controller: c)),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('player-search')), 'W015');
    await tester.pump();
    expect(c.event!.games.every((g) => !g.outcome.resolved), true);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
  testWidgets('players and results remain usable at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture(count: 22);
    addTearDown(c.dispose);
    Widget host(Widget child) => MaterialApp(
      theme: meowTheme(Brightness.dark),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(1280, 900),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(body: child),
      ),
    );
    await tester.pumpWidget(
      host(PlayersView(controller: c, onAddSections: () {})),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    c.post((await tester.runAsync(() => c.propose()))!);
    await tester.pumpWidget(host(ResultsView(controller: c)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
  Future<void> mountPlayers(WidgetTester tester, c) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => PlayersView(controller: c, standingsOnly: true),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'round cells are read-only; byes can be cleared in player details',
    (tester) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      await mountPlayers(tester, c);
      await tester.tap(find.byKey(const ValueKey('round-p0-2')));
      await tester.pumpAndSettle();
      // A row opens player details; the grid itself cannot accept scores.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      expect(c.event!.player('p0').byes, isEmpty);
      await toggleBye(tester, 2, 1);
      expect(c.event!.player('p0').byes[2], 1);
      // Choosing the same round again clears it.
      await toggleBye(tester, 2, 1);
      expect(c.event!.player('p0').byes[2], isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'crosstable shows numeric results with opponent context and accepts typing',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final g = c.event!.games.first;
      c.recordResult(g.id, Outcome.blackWin);
      await mountPlayers(tester, c);
      final winner = find.byKey(ValueKey('round-${g.black}-1'));
      final loser = find.byKey(ValueKey('round-${g.white}-1'));
      expect(
        find.descendant(of: winner, matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: loser, matching: find.text('0')),
        findsOneWidget,
      );
      expect(find.text('W'), findsNothing);
      expect(find.text('L'), findsNothing);
      final tip = tester.widget<Tooltip>(
        find.descendant(of: winner, matching: find.byType(Tooltip)).first,
      );
      expect(tip.message, contains(c.event!.player(g.white).name));
      // The same typing contract applies to the standings table.
      await tester.tap(loser);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pump();
      expect(c.event!.games.first.outcome, Outcome.whiteWin);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
  testWidgets('crosstable ranks by points once play starts', (tester) async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final section = c.event!.sections.first;
    final g = section.rounds.single.games.first;
    c.recordResult(g.id, Outcome.blackWin);
    await mountPlayers(tester, c);
    expect(find.text('Pts'), findsOneWidget);
    // The winner, seeded lower, is now listed first in the section.
    final top = tester.getTopLeft(find.byKey(ValueKey('player-${g.black}')));
    final seed1 = tester.getTopLeft(
      find.byKey(ValueKey('player-${section.players.first}')),
    );
    expect(top.dy, lessThan(seed1.dy));
    expect(
      find.descendant(
        of: find.byKey(ValueKey('number-${g.black}')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(find.text('Rank'), findsNothing);
    expect(find.text('Seed order'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
  testWidgets('clicking a player opens a side panel, not a dialog', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mountPlayers(tester, c);
    final [a, b] = c.event!.sections.first.players.take(2).toList();
    await tester.tap(find.text(c.event!.player(a).name));
    await tester.pump();
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('panel-rating')), '1777');
    // Saving is explicit; opening another player only preserves a draft.
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.tap(find.text(c.event!.player(b).name));
    await tester.pump();
    expect(c.event!.player(a).rating, 1777);
    await tester.enterText(find.byKey(const ValueKey('panel-name')), 'Renamed');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.event!.player(b).name, 'Renamed');
    // UNR is accepted for unrated; byes apply without a dialog.
    await tester.enterText(find.byKey(const ValueKey('panel-rating')), 'unr');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.event!.player(b).rating, 0);
    expect(find.text('UNR'), findsWidgets);
    await toggleBye(tester, 2, 1);
    expect(c.event!.player(b).byes[2], 1);
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pump();
    expect(find.byKey(const ValueKey('panel-name')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
  testWidgets(
    'each player has a score box; typing fills in the opponent and replaces',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixture();
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => ResultsView(controller: c),
            ),
          ),
        ),
      );
      final g = c.event!.games.first;
      Finder box(String side) => find.byKey(ValueKey('score-${g.id}-$side'));
      // 1 in Black's box: Black wins and White's box shows 0.
      await tester.tap(box('b'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pump();
      expect(c.event!.games.first.outcome, Outcome.blackWin);
      expect(
        find.descendant(of: box('w'), matching: find.text('0')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: box('b'), matching: find.text('1')),
        findsOneWidget,
      );
      // Typing over a result replaces it, like a text box.
      await tester.tap(box('w'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pump();
      expect(c.event!.games.first.outcome, Outcome.draw);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('game-${g.id}')),
          matching: find.text('½'),
        ),
        findsNWidgets(2),
      );
      // The cursor moved on to the next board, White's box.
      final next = c.event!.games.elementAt(1);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pump();
      expect(c.event!.games.elementAt(1).id, next.id);
      expect(c.event!.games.elementAt(1).outcome, Outcome.blackWin);
      // Delete clears.
      await tester.tap(box('w'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(c.event!.games.first.outcome, Outcome.unreported);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
  testWidgets(
    'typing Delete clears both scores and search finds names or boards',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixture();
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final g = c.event!.games.first;
      c.recordResult(g.id, Outcome.whiteWin);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => ResultsView(controller: c),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('board-search')),
        c.event!.player(g.white).name,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('game-${g.id}')), findsOneWidget);
      expect(find.byTooltip('Enter or clear result (M)'), findsNothing);
      await tester.tap(find.byKey(ValueKey('score-${g.id}-w')));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(c.event!.games.first.outcome, Outcome.unreported);
      for (final side in ['w', 'b']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('score-${g.id}-$side')),
            matching: find.text(''),
          ),
          findsOneWidget,
        );
      }
      expect(scoreMark(Outcome.unfinished, white: true), '');
      await tester.enterText(
        find.byKey(const ValueKey('board-search')),
        '${g.board}',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('game-${g.id}')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('two selected players can share a team and request not to meet', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mountPlayers(tester, c);
    for (final id in ['p0', 'p1']) {
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('player-$id')),
          matching: find.byType(PlainCheckbox),
        ),
      );
      await tester.pump();
    }
    await tester.tap(find.text('Assign team'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Team'),
      'Mixed doubles A',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.event!.player('p0').team, 'Mixed doubles A');
    expect(c.event!.player('p1').team, 'Mixed doubles A');
    await tester.ensureVisible(find.text('Do not pair together'));
    await tester.tap(find.text('Do not pair together'));
    await tester.pumpAndSettle();
    expect(c.event!.player('p0').avoid, {'p1'});
    expect(c.event!.player('p1').avoid, {'p0'});
    await tester.pumpWidget(const SizedBox());
  });
}
