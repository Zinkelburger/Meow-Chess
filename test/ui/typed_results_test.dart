import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/result_keys.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../support.dart';

KeyEvent key(LogicalKeyboardKey value, [String? character]) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: value,
  timeStamp: Duration.zero,
  character: character,
);

void main() {
  test('1/W and 0/L have the focused player perspective; only D draws', () {
    for (final white in [true, false]) {
      for (final value in [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.numpad1,
        LogicalKeyboardKey.keyW,
      ]) {
        expect(
          resultFromKey(key(value), white: white),
          white ? Outcome.whiteWin : Outcome.blackWin,
        );
      }
      for (final value in [
        LogicalKeyboardKey.digit0,
        LogicalKeyboardKey.numpad0,
        LogicalKeyboardKey.keyL,
      ]) {
        expect(
          resultFromKey(key(value), white: white),
          white ? Outcome.blackWin : Outcome.whiteWin,
        );
      }
      expect(
        resultFromKey(key(LogicalKeyboardKey.keyD), white: white),
        Outcome.draw,
      );
      for (final value in [
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.numpad5,
        LogicalKeyboardKey.equal,
        LogicalKeyboardKey.period,
        LogicalKeyboardKey.slash,
      ]) {
        expect(resultFromKey(key(value, '½'), white: white), isNull);
      }
    }
  });

  testWidgets(
    'standings typing saves reciprocal numeric scores, freezes rows and skips the opponent',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      await tester.pumpWidget(
        MaterialApp(
          theme: meowTheme(Brightness.light),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) =>
                  PlayersView(controller: c, standingsOnly: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final g = c.event!.games.first;
      final cells = find.byKey(ValueKey('standing-score-${g.id}-${g.black}'));
      final original = tester.getRect(
        find.byKey(ValueKey('player-${g.black}')),
      );
      final revision = c.event!.revision;
      await tester.tap(cells);
      await tester.pump();
      expect(c.event!.revision, revision);
      expect(find.byType(PopupMenuItem<Outcome>), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pump();
      expect(c.event!.revision, revision);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.pump();
      expect(c.event!.games.first.outcome, Outcome.blackWin);
      expect(
        tester.getRect(find.byKey(ValueKey('player-${g.black}'))),
        original,
      );
      expect(
        find.descendant(of: cells, matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey('standing-score-${g.id}-${g.white}')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pump();
      expect(c.event!.games.map((g) => g.outcome).toList(), [
        Outcome.blackWin,
        Outcome.draw,
      ]);
      final drawn = c.event!.games.last;
      for (final id in [drawn.white, drawn.black]) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('standing-score-${drawn.id}-$id')),
            matching: find.text('½'),
          ),
          findsOneWidget,
        );
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('section and results cursor survive view switching', (
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
    final section = c.event!.sections.last;
    await tester.tap(find.byKey(ValueKey('section-chip-${section.id}')));
    await tester.tap(find.text('Pairings'));
    await tester.pumpAndSettle();
    final g = section.rounds.single.games.last;
    await tester.tap(find.byKey(ValueKey('score-${g.id}-b')));
    await tester.pump();
    await tester.tap(find.text('Players'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PlayersView>(find.byType(PlayersView)).sectionId,
      section.id,
    );
    await tester.tap(find.text('Pairings'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ResultsView>(find.byType(ResultsView)).sectionId,
      section.id,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pump();
    expect(
      c.event!.games.firstWhere((x) => x.id == g.id).outcome,
      Outcome.blackWin,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
