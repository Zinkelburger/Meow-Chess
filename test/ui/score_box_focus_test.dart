import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/focus_pool.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';

import '../support.dart';

void main() {
  testWidgets('score box focus nodes are freed as rounds are posted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    final section = c.event!.sections.single;
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) =>
                ResultsView(controller: c, sectionId: section.id),
          ),
        ),
      ),
    );
    FocusNodePool boxes() =>
        tester.state<ResultsViewState>(find.byType(ResultsView)).boxes;
    // The crosstable's state is private to its library.
    FocusNodePool crosstable() =>
        (tester.state(find.byType(PlayersView)) as dynamic).resultFocus
            as FocusNodePool;
    for (var round = 1; round <= section.plannedRounds; round++) {
      c.post((await tester.runAsync(() => c.propose()))!);
      await tester.pumpAndSettle();
      for (final g in c.event!.sections.single.rounds.last.games) {
        c.recordResult(g.id, Outcome.whiteWin);
      }
      await tester.pumpAndSettle();
      // Two boards on screen, a box for each player: earlier rounds' boxes
      // used to stay until the view closed.
      final shown = c.event!.sections.single.rounds.last.games;
      expect(boxes().keys.toSet(), {
        for (final g in shown) ...['${g.id}-w', '${g.id}-b'],
      }, reason: 'round $round');
      // The crosstable beside the boards shows every round's score boxes,
      // one per player per game, and keeps no others.
      final played = c.event!.sections.single.rounds.expand((r) => r.games);
      expect(
        crosstable().keys.toSet(),
        everyElement(
          isIn({
            for (final g in played) ...[
              '${g.id}-${g.white}',
              '${g.id}-${g.black}',
            ],
          }),
        ),
      );
    }
    // A board the search filters out frees its boxes too.
    await tester.enterText(
      find.byKey(const ValueKey('board-search')),
      c.event!
          .player(c.event!.sections.single.rounds.last.games.first.white)
          .name,
    );
    await tester.pumpAndSettle();
    expect(boxes().keys, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a freed node is disposed after the frame that drops it', (
    tester,
  ) async {
    final pool = FocusNodePool((key) => FocusNode(debugLabel: key));
    final a = pool.node('a'), b = pool.node('b');
    var disposed = false;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, _) {
          pool.retainOnly({'a'});
          return const SizedBox();
        },
      ),
    );
    expect(pool.keys, ['a']);
    expect(identical(pool.node('a'), a), isTrue);
    // A disposed node refuses new listeners.
    try {
      b.addListener(() {});
    } on FlutterError {
      disposed = true;
    }
    expect(disposed, isTrue);
    expect(identical(pool.node('b'), b), isFalse);
    pool.dispose();
  });
}
