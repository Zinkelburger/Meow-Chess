import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/panels.dart' show PrintPanel;
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/theme.dart';

import '../support.dart';
import 'dock_host.dart';

void main() {
  testWidgets('the print button prints the standings shown', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixture(count: 4, format: Format.roundRobin);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    for (final g in c.event!.games.toList()) {
      c.recordResult(g.id, Outcome.draw);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => DockHost(
              child: PlayersView(controller: c, standingsOnly: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<PrintPanel> printStandings() async {
      await tester.tap(find.byKey(const ValueKey('print-standings')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return tester.widget<PrintPanel>(find.byType(PrintPanel));
    }

    // The full standings print as the full standings.
    expect((await printStandings()).forPrizes, isFalse);
    final full = tester.state(find.byType(PrintPanel));
    // With Prize standings on, the prize standings print, and a fresh panel
    // opens for them rather than the full standings' panel staying.
    // (The open print panel keeps a preview spinner going, so no settling.)
    await tester.tap(find.byKey(const ValueKey('prize-standings')));
    await tester.pump();
    expect((await printStandings()).forPrizes, isTrue);
    expect(tester.state(find.byType(PrintPanel)), isNot(same(full)));
    expect(
      find.text('Excluding early round-robin withdrawals'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
