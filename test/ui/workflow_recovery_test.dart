import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/panels.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/reports_view.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../support.dart';

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

Workspace workspace(TournamentController c) =>
    Workspace(controller: c, path: ':memory:', onClose: () {}, onTheme: () {});

void main() {
  testWidgets(
    'invalid add-player draft survives Escape and database reopen without registering',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('meow-drafts-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}/event.meow';
      var c = fixture(path: path);
      final revision = c.event!.revision;
      final count = c.event!.players.length;
      bool closed = false;
      await mount(
        tester,
        PlayerPanel(controller: c, onClose: () => closed = true),
      );
      await tester.enterText(
        find.byKey(const ValueKey('panel-name')),
        'New arrival',
      );
      await tester.enterText(
        find.byKey(const ValueKey('panel-rating')),
        'not yet known',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(closed, true);
      expect(c.event!.revision, revision);
      expect(c.event!.players.length, count);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      c = TournamentController(SqliteEventRepository(path));
      await mount(tester, PlayerPanel(controller: c, onClose: () {}));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('panel-name')))
            .controller!
            .text,
        'New arrival',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('panel-rating')))
            .controller!
            .text,
        'not yet known',
      );
      expect(find.text('Draft saved · not applied'), findsOneWidget);
      expect(c.event!.revision, revision);
      await tester.ensureVisible(find.text('Discard draft'));
      await tester.tap(find.text('Discard draft'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('panel-name')))
            .controller!
            .text,
        '',
      );
      expect(c.workspaceState.read('draft-player-new'), '');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'pending player move retains its target and reason without applying it',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final player = c.event!.players.first;
      final destination = c.event!.sections.last.id;
      final revision = c.event!.revision;
      await mount(
        tester,
        ListenableBuilder(
          listenable: c.workspaceState,
          builder: (_, _) =>
              PlayerPanel(controller: c, player: player, onClose: () {}),
        ),
      );
      tester
          .state<PlayerPanelState>(find.byType(PlayerPanel))
          .pickSection(destination);
      await tester.pumpAndSettle();
      final reason = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Reason',
      );
      await tester.enterText(reason, 'Group requested by the TD');
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await mount(
        tester,
        PlayerPanel(controller: c, player: player, onClose: () {}),
      );
      final restored = tester.state<PlayerPanelState>(find.byType(PlayerPanel));
      expect(restored.moveTo, destination);
      expect(restored.reason.text, 'Group requested by the TD');
      expect(c.event!.revision, revision);
      restored.discardDraft();
      await tester.pumpAndSettle();
      expect(restored.moveTo, isNull);
      expect(restored.reason.text, '');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'player report repair focuses its field without saving other edits',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      await mount(
        tester,
        PlayerPanel(
          controller: c,
          player: c.event!.players.first,
          focusField: 'state',
          onClose: () {},
        ),
      );
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('panel-state')),
      );
      expect(field.focusNode!.hasFocus, true);
      expect(
        find.byKey(const ValueKey('panel-state')).hitTestable(),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'print retries failures and requires refresh or an explicit older revision',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      var attempts = 0;
      final pending = Completer<Uint8List>();
      await mount(
        tester,
        PrintPanel(
          event: c.event!,
          controller: c,
          kind: ReportKind.packet,
          onClose: () {},
          generate: (_) {
            attempts++;
            return attempts == 1
                ? Future.error(StateError('Try again'))
                : pending.future;
          },
        ),
      );
      expect(find.textContaining('Could not make the PDF'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      final revision = c.event!.revision;
      c.savePlayer(c.event!.players.first.copy(name: 'Updated'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('print-stale')), findsOneWidget);
      expect(find.text('Use older revision $revision'), findsOneWidget);
      await tester.tap(find.text('Use older revision $revision'));
      await tester.pumpAndSettle();
      expect(find.text('Use older revision $revision'), findsNothing);
      c.savePlayer(c.event!.players.first.copy(name: 'Updated again'));
      await tester.pumpAndSettle();
      expect(find.text('Use older revision $revision'), findsOneWidget);
      await tester.tap(find.text('Refresh preview'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('print-stale')), findsNothing);
      expect(
        find.textContaining('Revision ${c.event!.revision}'),
        findsOneWidget,
      );
      expect(attempts, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'results restore board side and historical rounds reopen locked',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      for (final g in c.event!.games.toList()) {
        c.recordResult(g.id, Outcome.draw);
      }
      c.post((await tester.runAsync(() => c.propose()))!);
      await mount(tester, workspace(c));
      await tester.tap(find.text('Pairings').first);
      await tester.pumpAndSettle();
      final game = c.event!.sections.single.rounds.last.games.last;
      await tester.ensureVisible(find.byKey(ValueKey('score-${game.id}-b')));
      await tester.tap(find.byKey(ValueKey('score-${game.id}-b')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pairings').first);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'score ${game.id} black',
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('round-selector')),
          matching: find.text('1'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('correct-round')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pairings').first);
      await tester.pumpAndSettle();
      final state = tester.state<ResultsViewState>(find.byType(ResultsView));
      expect(state.selectedRound, 1);
      expect(state.correcting, false);
      await tester.tap(find.byTooltip('Print preview…'));
      await tester.pump();
      final preview = tester.widget<PrintPanel>(find.byType(PrintPanel));
      expect(preview.roundNumber, 1);
      expect(preview.roundNumbers, {c.event!.sections.single.id: 1});
      state.showPlayer(game.white);
      await tester.pumpAndSettle();
      expect(find.byType(PrintPanel), findsNothing);
      expect(find.byType(PlayerPanel), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-details')));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPanel), findsNothing);
      state.showPlayer(game.white);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPanel), findsOneWidget);
      expect(find.byKey(const ValueKey('event-name')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'report repair opens the named player field and retains Reports',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.savePlayer(c.event!.players.first.copy(memberId: ''));
      await mount(tester, workspace(c));
      await tester.tap(find.text('Export').first);
      await tester.pumpAndSettle();
      final issues = find.byKey(
        const PageStorageKey('rating-preflight-details'),
      );
      await tester.ensureVisible(issues);
      await tester.pumpAndSettle();
      final repair = find.byKey(const ValueKey('repair-player-p0-memberId'));
      await tester.ensureVisible(repair);
      await tester.pumpAndSettle();
      await tester.tap(repair);
      await tester.pumpAndSettle();
      expect(find.byType(ReportsView), findsOneWidget);
      expect(find.byType(PlayerPanel), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('panel-memberId')))
            .focusNode!
            .hasFocus,
        true,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPanel), findsNothing);
      expect(find.byType(ReportsView), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('full workspace and one shared panel fit at 200 percent text', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await mount(tester, workspace(c), scale: 2);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.text('Player 00', findRichText: true).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Player 00', findRichText: true).first);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('event-details')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPanel), findsNothing);
    expect(find.byKey(const ValueKey('event-name')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Pairings').first);
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ResultsView), findsOneWidget);
    await tester.ensureVisible(find.text('Export').first);
    await tester.tap(find.text('Export').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ReportsView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
