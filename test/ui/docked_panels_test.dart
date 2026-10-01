import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/reports_view.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../support.dart';

Future<void> mountWorkspace(WidgetTester tester, TournamentController c) async {
  tester.view.physicalSize = const Size(1400, 1000);
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

Future<void> mountView(WidgetTester tester, Widget Function() child) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Builder(builder: (_) => child())),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('quads are previewed in the side panel and two clicks swap', (
    tester,
  ) async {
    final c = TournamentController(SqliteEventRepository(':memory:'))
      ..create('Club night');
    addTearDown(c.dispose);
    c.importPlayers([
      for (var i = 0; i < 8; i++)
        Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 50),
    ]);
    await mountWorkspace(tester, c);
    await tester.tap(find.text('Create sections…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('type-quad')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    // p3 tops nothing in Quad 1; p4 leads Quad 2. Swap them.
    await tester.tap(find.byKey(const ValueKey('quad-player-p3')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('quad-player-p4')));
    await tester.tap(find.byKey(const ValueKey('quad-player-p4')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('create-sections')));
    await tester.tap(find.byKey(const ValueKey('create-sections')));
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.players, ['p0', 'p1', 'p2', 'p4']);
    expect(c.event!.sections.last.players, ['p3', 'p5', 'p6', 'p7']);
    // The panel closes once the sections exist.
    expect(find.byKey(const ValueKey('type-quad')), findsNothing);
  });

  testWidgets('section settings and combine dock beside the page', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    await mountWorkspace(tester, c);
    await tester.tap(find.byKey(ValueKey('section-chip-${q1.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Manage sections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Section settings…'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('field-name')), 'Top');
    await tester.enterText(find.byKey(const ValueKey('field-rounds')), '0');
    await tester.tap(find.text('Save'));
    await tester.pump();
    // The problem stays beside the field and nothing changes.
    expect(find.text('Number of rounds must be between 1 and 32.'), findsOne);
    expect(c.event!.sections.first.name, q1.name);
    await tester.enterText(find.byKey(const ValueKey('field-rounds')), '3');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.name, 'Top');
    expect(find.byKey(const ValueKey('field-name')), findsNothing);

    await tester.tap(find.byTooltip('Manage sections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Combine sections…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('combine-into-${q2.id}')));
    await tester.pump();
    await tester.tap(find.text('Combine'));
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.players, isEmpty);
    expect(c.event!.sections.last.players, hasLength(8));
  });

  testWidgets('Edit pairings swaps two clicked players as a new revision', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    final id = c.event!.sections.first.id;
    c.post((await tester.runAsync(() => c.propose(sectionId: id)))!);
    final [a, b] = c.event!.sections.first.rounds.last.games;
    await mountView(
      tester,
      () => ListenableBuilder(
        listenable: c,
        builder: (_, _) => ResultsView(controller: c, sectionId: id),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('edit-pairings')));
    await tester.pump();
    expect(find.byKey(const ValueKey('swap-banner')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('round-player-${a.id}-${a.black}')));
    await tester.pump();
    expect(find.textContaining('Swap '), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('round-player-${b.id}-${b.white}')));
    await tester.pump();
    final round = c.event!.sections.first.rounds.last;
    expect(round.revision, 2);
    expect(round.games[0].black, b.white);
    expect(round.games[1].white, a.black);
    expect(round.note, contains('Swapped'));
    // Two on one board swap colours.
    await tester.tap(find.byKey(ValueKey('round-player-${a.id}-${a.white}')));
    await tester.tap(find.byKey(ValueKey('round-player-${a.id}-${b.white}')));
    await tester.pump();
    final again = c.event!.sections.first.rounds.last.games.first;
    expect((again.white, again.black), (b.white, a.white));
    c.undo();
    await tester.pump();
    expect(c.event!.sections.first.rounds.last.games.first.white, a.white);
    await tester.tap(find.text('Done editing'));
    await tester.pump();
    expect(find.byKey(const ValueKey('swap-banner')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pairing-only assumption is set in the side panel', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    final id = c.event!.sections.first.id;
    c.post((await tester.runAsync(() => c.propose(sectionId: id)))!);
    final g = c.event!.sections.first.rounds.last.games.first;
    await mountView(
      tester,
      () => ListenableBuilder(
        listenable: c,
        builder: (_, _) => ResultsView(controller: c, sectionId: id),
      ),
    );
    await tester.tap(find.byTooltip('Enter or clear result (M)').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assume a result for pairing only…'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('field-reason')),
      'Long endgame',
    );
    await tester.tap(find.text('Assume for pairing'));
    await tester.pumpAndSettle();
    final game = c.event!.games.firstWhere((x) => x.id == g.id);
    expect(game.pairingAssumption, Outcome.draw);
    expect(game.pairingReason, 'Long endgame');
    expect(find.byKey(const ValueKey('field-reason')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Print packet docks the preview instead of a dialog', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await mountWorkspace(tester, c);
    await tester.tap(find.text('Rounds').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('print-round')));
    await tester.pump();
    expect(find.byKey(const ValueKey('print-panel')), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    // The boards stay in view beside it.
    expect(find.byKey(const ValueKey('round-line')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pump();
    expect(find.byKey(const ValueKey('print-panel')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('submission notes are typed in place', (tester) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    await mountView(
      tester,
      () => ListenableBuilder(
        listenable: c,
        builder: (_, _) => ReportsView(controller: c),
      ),
    );
    final notes = find.byKey(const ValueKey('submission-notes'));
    await tester.ensureVisible(notes);
    await tester.enterText(notes, 'Uploaded Oct 1, ref 12345');
    await tester.pump();
    await tester.ensureVisible(find.text('Save').last);
    await tester.tap(find.text('Save').last);
    await tester.pump();
    expect(c.event!.submission, 'Uploaded Oct 1, ref 12345');
    expect(find.byType(Dialog), findsNothing);
  });
}
