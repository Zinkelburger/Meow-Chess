import 'package:flutter/gestures.dart';
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
import 'package:meow_chess/ui/select.dart';

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

void expectFieldFocus(WidgetTester tester, String key) {
  final field = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(EditableText),
    ),
  );
  expect(field.focusNode.hasFocus, true, reason: key);
}

void main() {
  testWidgets('New section previews rating quads before creating them', (
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
    // There is one way to make sections, and it is not a filled button.
    expect(find.text('Create sections…'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('new-section')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    // Nobody is ticked, so everyone not in a section goes in.
    expect(
      tester.getSemantics(find.byKey(const ValueKey('pool-unassigned'))),
      isSemantics(
        label: 'Everyone not in a section, 8 players',
        isChecked: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.text('Quads'));
    await tester.pumpAndSettle();
    // Every player is listed under the quad they will play in.
    expect(find.text('Goes in · 2 sections'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      expect(find.text('Player $i'), findsWidgets);
    }
    expect(c.event!.sections, isEmpty);
    await tester.tap(find.byKey(const ValueKey('create-section')));
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.players, ['p0', 'p1', 'p2', 'p3']);
    expect(c.event!.sections.last.players, ['p4', 'p5', 'p6', 'p7']);
    // The panel closes once the sections exist.
    expect(find.byKey(const ValueKey('new-section-panel')), findsNothing);
  });

  testWidgets(
    'right-click player and section menus offer explicit roster actions',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      await mountWorkspace(tester, c);
      final first = c.event!.sections.first;
      final revision = c.event!.revision;
      expect(find.byTooltip('Actions for ${first.name}'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('player-p0')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      // Nobody has played, so the status action removes rather than withdraws.
      expect(find.text('Remove from event'), findsOneWidget);
      expect(find.textContaining('Withdraw'), findsNothing);
      expect(find.textContaining('Swap'), findsNothing);
      // One Move action; a quad asks who takes the player's place.
      await tester.tap(find.text('Move…'));
      await tester.pumpAndSettle();
      expect(c.event!.revision, revision);
      await chooseOption(
        tester,
        find.byType(PlainSelect<String?>).at(1),
        'Quad 2',
      );
      final apply = find.byKey(const ValueKey('apply-player-operation'));
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);
      await chooseOption(
        tester,
        find.byType(PlainSelect<String?>).last,
        'Player 04 · 1800',
      );
      await tester.tap(find.byKey(const ValueKey('apply-player-operation')));
      await tester.pumpAndSettle();
      expect(c.event!.sections.first.players, ['p4', 'p1', 'p2', 'p3']);
      expect(c.event!.sections.last.players, ['p0', 'p5', 'p6', 'p7']);
      // Player actions live on the player, not on the section tab.
      await tester.tap(
        find.byKey(ValueKey('section-chip-${first.id}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      expect(find.text('Print player list'), findsNWidgets(2));
      expect(find.text('Move player…'), findsNothing);
      expect(find.text('Withdraw / reinstate player…'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('player-p4')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await tester.tap(find.text('Remove from event'));
      await tester.pumpAndSettle();
      expect(c.event!.players.any((p) => p.id == 'p4'), false);
      expect(
        find.text(
          'Removed Player 04 from the event. '
          '${first.name} now has 3 players. A quad needs four.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('done-undo')));
      await tester.pumpAndSettle();
      expect(c.event!.sections.first.players, ['p4', 'p1', 'p2', 'p3']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('section settings and combine dock beside the page', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    await mountWorkspace(tester, c);
    await tester.tap(find.byKey(ValueKey('section-chip-${q1.id}')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('section-chip-${q1.id}')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename / section settings…'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expectFieldFocus(tester, 'field-name');
    await tester.enterText(find.byKey(const ValueKey('field-name')), 'Top');
    // Quads play their fixed three rounds and show no rounds field (design
    // brief §5.2), so the bad value goes in the first board number, which
    // lives in the closed Players group.
    expect(find.byKey(const ValueKey('field-rounds')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('section-group-players')),
    );
    await tester.tap(find.byKey(const ValueKey('section-group-players')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-board')), '0');
    // The settings panel is taller than the window; Save is below the fold.
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // The problem stays beside the field and nothing changes.
    expect(find.text('The first board number must be 1 or more.'), findsOne);
    expect(c.event!.sections.first.name, q1.name);
    await tester.enterText(find.byKey(const ValueKey('field-board')), '1');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.name, 'Top');
    expect(find.byKey(const ValueKey('field-name')), findsNothing);

    await tester.tap(
      find.byKey(ValueKey('section-chip-${q1.id}')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Combine sections…'));
    await tester.pumpAndSettle();
    expectFieldFocus(tester, 'combine-reason');
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
    final c = fixture(format: Format.swiss);
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
    expect(round.games.map((g) => g.id), isNot(contains(a.id)));
    expect(round.games.map((g) => g.id), isNot(contains(b.id)));
    expect(round.note, contains('Swapped'));
    final saved = c.event!.encode();
    expect(
      () => c.recordResult(a.id, Outcome.whiteWin),
      throwsA(isA<TournamentException>()),
    );
    expect(c.event!.encode(), saved);
    // Two on one board swap colours.
    final replacement = round.games.first;
    await tester.tap(
      find.byKey(ValueKey('round-player-${replacement.id}-${a.white}')),
    );
    await tester.tap(
      find.byKey(ValueKey('round-player-${replacement.id}-${b.white}')),
    );
    await tester.pump();
    final again = c.event!.sections.first.rounds.last.games.first;
    expect((again.white, again.black), (b.white, a.white));
    expect(again.id, isNot(replacement.id));
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
    await tester.tap(find.byKey(ValueKey('score-${g.id}-w')));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expectFieldFocus(tester, 'field-reason');
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

  testWidgets('Print packet always opens a preview beside the boards', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await mountWorkspace(tester, c);
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Print preview…'), findsNothing);
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
    await tester.ensureVisible(find.text('Save').last);
    await tester.tap(find.text('Save').last);
    await tester.pump();
    expect(c.event!.submission, 'Uploaded Oct 1, ref 12345');
    expect(find.byType(Dialog), findsNothing);
  });
}
