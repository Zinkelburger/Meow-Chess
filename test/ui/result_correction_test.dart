import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/history_panel.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/result_correction_dialog.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';

Future<void> prepare(WidgetTester tester, TournamentController c) async {
  final id = c.event!.sections.first.id;
  c.post((await tester.runAsync(() => c.propose(sectionId: id)))!);
  for (final g in c.event!.sections.first.rounds.first.games) {
    c.recordResult(g.id, Outcome.whiteWin);
  }
  c.post((await tester.runAsync(() => c.propose(sectionId: id)))!);
}

Future<void> mount(
  WidgetTester tester,
  TournamentController c,
  Widget Function() view,
) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: ListenableBuilder(listenable: c, builder: (_, _) => view()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('all rounds groups boards correctly and cancel changes nothing', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    await prepare(tester, c);
    final section = c.event!.sections.first;
    await mount(
      tester,
      c,
      () => ResultsView(controller: c, sectionId: section.id),
    );
    await tester.tap(find.byKey(const ValueKey('all-rounds')));
    await tester.pumpAndSettle();
    for (final r in section.rounds) {
      for (final g in r.games) {
        expect(find.byKey(ValueKey('game-${g.id}')), findsOneWidget);
      }
    }
    final first = section.rounds.first.games.first;
    final second = section.rounds.last.games.first;
    expect(
      tester.getTopLeft(find.byKey(ValueKey('game-${first.id}'))).dy,
      lessThan(tester.getTopLeft(find.byKey(ValueKey('game-${second.id}'))).dy),
    );
    final before = c.event!.encode();
    await tester.tap(find.byKey(const ValueKey('correct-round')));
    await tester.tap(find.byKey(ValueKey('score-${first.id}-w')));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('result-correction-review')),
      findsOneWidget,
    );
    expect(c.event!.encode(), before);
    await tester.tap(find.byKey(const ValueKey('reopen-round-2')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('result-reason')));
    await tester.enterText(
      find.byKey(const ValueKey('result-reason')),
      'Changed mind',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('apply-correction')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.event!.encode(), before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reopening from correction requires explicit unstarted confirmation',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      await prepare(tester, c);
      final game = c.event!.games.first;
      await mount(
        tester,
        c,
        () => Builder(
          builder: (context) => TextButton(
            onPressed: () => reviewResultCorrection(
              context,
              c,
              game.id,
              outcome: Outcome.draw,
            ),
            child: const Text('Review'),
          ),
        ),
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reopen-round-2')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('result-reason')));
      await tester.enterText(
        find.byKey(const ValueKey('result-reason')),
        'Signed draw',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('apply-correction')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('confirm-unstarted')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-unstarted')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apply-correction')));
      await tester.pumpAndSettle();
      expect(c.event!.sections.first.rounds.length, 1);
      expect(c.event!.games.first.outcome, Outcome.draw);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'entry result opens a review; result keys do not write behind it',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      await prepare(tester, c);
      final game = c.event!.games.first;
      await mount(
        tester,
        c,
        () => PlayersView(
          controller: c,
          sectionId: c.event!.sections.first.id,
          standingsOnly: true,
        ),
      );
      final before = c.event!.encode();
      await tester.tap(
        find.byKey(ValueKey('standing-score-${game.id}-${game.black}')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('result-correction-review')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      expect(c.event!.encode(), before);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('result-correction-review')),
          matching: find.textContaining('Board ${game.board}'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.event!.encode(), before);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'history reverses a selected result without undoing later player edits',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final game = c.event!.games.first;
      c.recordResult(game.id, Outcome.whiteWin);
      final resultNode = c.graph.head!;
      c.savePlayer(c.event!.player('p0').copy(notes: 'Retain this'));
      await mount(tester, c, () => HistoryPanel(controller: c, onClose: () {}));
      await tester.tap(find.byKey(ValueKey('history-$resultNode')));
      await tester.pumpAndSettle();
      expect(find.textContaining('→'), findsWidgets);
      await tester.ensureVisible(
        find.byKey(const ValueKey('history-undo-result')),
      );
      await tester.tap(find.byKey(const ValueKey('history-undo-result')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apply-correction')));
      await tester.pumpAndSettle();
      expect(c.event!.games.first.outcome, Outcome.unreported);
      expect(c.event!.player('p0').notes, 'Retain this');
      expect(c.graph.nodes.containsKey(resultNode), true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('correction review fits narrow windows at double text size', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    await prepare(tester, c);
    tester.view.physicalSize = const Size(680, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: meowTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => reviewResultCorrection(
                  context,
                  c,
                  c.event!.games.first.id,
                  outcome: Outcome.draw,
                ),
                child: const Text('Review'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('result-reason')));
      await tester.enterText(
        find.byKey(const ValueKey('result-reason')),
        'Scoresheet checked',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('apply-correction')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    }
  });
}
