import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';

void main() {
  testWidgets('compact crosstable and boards share live results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => ResultsView(controller: c),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final game = c.event!.games.first;
    final header = find.byKey(const ValueKey('player-column-header'));
    final board = find.byKey(ValueKey('game-${game.id}'));
    expect(tester.getRect(header).right, lessThan(tester.getRect(board).left));
    expect(tester.getSize(header).width, lessThan(600));
    expect(tester.getSize(board).width, lessThan(760));
    expect(tester.getSize(header).width, tester.getSize(board).width);
    final headerBefore = tester.getRect(header);
    final boardBefore = tester.getRect(board);
    // A wide gutter with a hairline separates the crosstable and boards.
    expect(boardBefore.left - headerBefore.right, 64);
    expect(tester.getSize(board).height, lessThanOrEqualTo(36));
    expect(
      tester.getSize(find.byKey(ValueKey('player-${game.white}'))).height,
      lessThanOrEqualTo(36),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('board-search'))).top,
      tester.getRect(find.byKey(const ValueKey('player-search'))).top,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('board-column-header'))).top,
      headerBefore.top,
    );
    expect(find.text('Rating'), findsNothing);
    expect(find.text('USCF ID'), findsNothing);
    Finder score(String side) => find.byKey(ValueKey('score-${game.id}-$side'));
    Finder standing(String player) =>
        find.byKey(ValueKey('standing-score-${game.id}-$player'));
    await tester.tap(score('w'));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: standing(game.white), matching: find.text('1')),
      findsOneWidget,
    );
    await tester.tap(standing(game.black));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    for (final side in ['w', 'b']) {
      expect(
        find.descendant(of: score(side), matching: find.text('½')),
        findsOneWidget,
      );
    }
    await tester.tap(find.byKey(ValueKey('player-${game.white}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('panel-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('pairings-split')), findsOneWidget);
    expect(tester.getRect(header), headerBefore);
    expect(tester.getRect(board), boardBefore);
    expect(
      tester.getRect(find.byKey(const ValueKey('player-details-area'))).left,
      greaterThan(boardBefore.right),
    );
    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pairings-split')), findsOneWidget);
    tester.view.physicalSize = const Size(960, 700);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pairings-split')), findsNothing);
    expect(board, findsOneWidget);
    expect(find.byKey(const ValueKey('pairings-stacked')), findsOneWidget);
    for (final key in ['show-both', 'show-boards', 'show-crosstable']) {
      expect(find.byKey(ValueKey(key)), findsNothing);
    }
    expect(
      tester.getRect(header).top,
      greaterThan(tester.getRect(board).bottom),
    );
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    expect(header, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Missing only follows section navigation and returning to a section',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = fixture(count: 8);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      for (final section in c.event!.sections) {
        c.recordResult(section.rounds.single.games.first.id, Outcome.draw);
      }
      final sectionId = ValueNotifier<String?>(c.event!.sections.first.id);
      addTearDown(sectionId.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: meowTheme(Brightness.light),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: sectionId,
              builder: (_, id, _) =>
                  ResultsView(key: ValueKey(id), controller: c, sectionId: id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('1 of 6 results in', findRichText: true),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pairings-locked')), findsNothing);
      final firstGame = c.event!.sections.first.rounds.single.games.first;
      final firstBoard = c.event!.sections.first.rounds.single.games.reduce(
        (a, b) => a.board < b.board ? a : b,
      );
      final roundHeading = find.byKey(
        ValueKey('board-round-heading-${c.event!.sections.first.id}-1'),
      );
      // Full quad schedules label each round between the columns and boards.
      expect(
        tester.getRect(roundHeading).top,
        tester
            .getRect(find.byKey(const ValueKey('board-column-header')))
            .bottom,
      );
      expect(
        tester.getRect(find.byKey(ValueKey('game-${firstBoard.id}'))).top,
        tester.getRect(roundHeading).bottom,
      );
      expect(
        tester
            .getRect(find.byKey(const ValueKey('player-column-header')))
            .bottom,
        tester
            .getRect(find.byKey(const ValueKey('board-column-header')))
            .bottom,
      );
      expect(find.text(c.event!.sections.first.name), findsNothing);
      await tester.tap(find.text('Missing only'));
      await tester.pumpAndSettle();
      for (final id in [
        c.event!.sections.last.id,
        null,
        c.event!.sections.first.id,
      ]) {
        sectionId.value = id;
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilterChip>(
                find.widgetWithText(FilterChip, 'Missing only'),
              )
              .selected,
          isTrue,
        );
        for (final section in c.event!.sections.where(
          (s) => id == null || s.id == id,
        )) {
          final games = section.rounds.single.games;
          expect(find.byKey(ValueKey('game-${games.first.id}')), findsNothing);
          expect(find.byKey(ValueKey('game-${games.last.id}')), findsOneWidget);
        }
      }
      expect(c.workspaceState.read('pairings-missing-only'), 'true');
      await tester.tap(find.text('Missing only'));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('game-${firstGame.id}')), findsOneWidget);
      expect(c.workspaceState.read('pairings-missing-only'), 'false');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('narrow Pairings scrolls from all boards to the crosstable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixture(count: 24);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(body: ResultsView(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    final header = find.byKey(const ValueKey('player-column-header'));
    final boardHeader = find.byKey(const ValueKey('board-column-header'));
    expect(tester.getRect(header).top, greaterThan(500));
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    expect(tester.getRect(header).top, greaterThanOrEqualTo(0));
    expect(tester.getRect(header).bottom, lessThanOrEqualTo(500));
    expect(tester.getRect(boardHeader).top, lessThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('roster shows USCF ID, rating and expiry in adjacent columns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlayersView(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('USCF ID')).left,
      lessThan(tester.getRect(find.text('Rating')).left),
    );
    expect(
      tester.getRect(find.text('Rating')).left,
      lessThan(tester.getRect(find.text('USCF expires')).left),
    );
    expect(find.text(c.event!.players.first.memberId), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an earlier round keeps both tables on one line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    for (final g in c.event!.games) {
      c.recordResult(g.id, Outcome.whiteWin);
    }
    c.post((await tester.runAsync(() => c.propose()))!);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => ResultsView(
              controller: c,
              sectionId: c.event!.sections.first.id,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('round-selector')),
        matching: find.text('1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('past-round-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('correct-round')), findsOneWidget);
    double top(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
    expect(top('board-column-header'), top('player-column-header'));
    expect(
      tester.getCenter(find.text('Crosstable')).dy,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('round-line'))).dy,
        1,
      ),
    );
  });
}
