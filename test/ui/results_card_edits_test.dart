// On the Pairings page a player card's pending edits are applied before
// the card is closed or replaced; a card that cannot save them stays open
// on its error.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';
import 'dock_host.dart';

void main() {
  testWidgets('showing another player or another panel applies the open '
      'card first, and stops on an edit that cannot be saved', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final g = c.event!.games.first, other = c.event!.games.last;
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: DockHost(
            child: ListenableBuilder(
              listenable: c,
              builder: (_, _) => ResultsView(controller: c),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<ResultsViewState>(find.byType(ResultsView));
    final name = find.byKey(const ValueKey('panel-name'));

    state.showPlayer(g.white);
    await tester.pumpAndSettle();
    await tester.enterText(name, 'Renamed Player');
    await tester.pump();
    state.showPlayer(g.black);
    await tester.pumpAndSettle();
    expect(c.event!.player(g.white).name, 'Renamed Player');
    expect(state.openPlayerId, g.black);

    // A name is required: the card stays, with the reason in it.
    final kept = c.event!.player(g.black).name;
    await tester.enterText(name, '');
    await tester.pump();
    state.showPlayer(g.white);
    await tester.pumpAndSettle();
    expect(state.openPlayerId, g.black);
    expect(find.byKey(const ValueKey('panel-error')), findsOneWidget);
    expect(c.event!.player(g.black).name, kept);
    state.assume(other.id);
    await tester.pumpAndSettle();
    expect(state.assumeFor, isNull);
    expect(state.openPlayerId, g.black);
    state.showPlayer(null);
    await tester.pumpAndSettle();
    expect(state.openPlayerId, g.black, reason: 'closing is refused too');

    // Once the edit is valid again the card gives way.
    await tester.enterText(name, kept);
    await tester.pump();
    state.assume(other.id);
    await tester.pumpAndSettle();
    expect(state.assumeFor, other.id);
    expect(state.openPlayerId, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
