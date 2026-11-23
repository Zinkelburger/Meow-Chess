// A change redraws the regions of the workspace that show it and leaves the
// others alone: a typed result does not rebuild the top bar, and opening a
// panel does not rebuild the tabs or the page row.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/section_tabs.dart';
import 'package:meow_chess/ui/workspace_pages.dart';
import 'package:meow_chess/ui/workspace_status.dart';
import 'package:meow_chess/ui/workspace_toolbar.dart';
import 'workspace_host.dart';

class _Direct extends TournamentController {
  _Direct(super.repository);
  @override
  Future<PairingBatch> runProposal(
    Event snapshot,
    String? sectionId,
    bool onlyReady,
  ) async => proposeRounds(snapshot, sectionId, onlyReady);
}

/// Sixteen players in one Swiss section with round 1 posted, on Pairings.
Future<TournamentController> onPairings(WidgetTester tester) async {
  final c = _Direct(SqliteEventRepository(':memory:'));
  addTearDown(c.dispose);
  c.create('Club Open');
  c.importPlayers([
    for (var i = 0; i < 16; i++)
      Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 50),
  ]);
  c.addSection('Open', Format.swiss, 4);
  c.post(await c.propose());
  await mountWorkspace(tester, c);
  await tester.tap(find.text('Pairings'));
  await tester.pumpAndSettle();
  return c;
}

/// The widgets rebuilt while [act] runs and the next frame is drawn.
Future<Set<Type>> rebuiltBy(
  WidgetTester tester,
  Future<void> Function() act,
) async {
  final rebuilt = <Type>{};
  debugOnRebuildDirtyWidget = (e, _) => rebuilt.add(e.widget.runtimeType);
  try {
    await act();
    await tester.pump();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return rebuilt;
}

String? undoTip(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(const ValueKey('undo'))).tooltip;

void main() {
  testWidgets('a result leaves the top bar alone and renames Undo', (
    tester,
  ) async {
    final c = await onPairings(tester);
    final games = c.event!.sections.single.rounds.last.games;
    final before = undoTip(tester);
    final rebuilt = await rebuiltBy(
      tester,
      () async => c.recordResult(games[0].id, Outcome.whiteWin),
    );
    expect(rebuilt, isNot(contains(WorkspaceTopBar)));
    expect(rebuilt, contains(UndoRedoButtons));
    // What the result changed is redrawn: its tab's progress, the pairing
    // action, the save time.
    expect(
      rebuilt,
      containsAll([SectionTabs, WorkspacePageRow, WorkspaceStatusBar]),
    );
    expect(undoTip(tester), isNot(before));
    expect(undoTip(tester), contains(c.undoLabel!));
  });

  testWidgets('opening a panel leaves the tabs and the page row alone', (
    tester,
  ) async {
    await onPairings(tester);
    final rebuilt = await rebuiltBy(
      tester,
      () => tester.tap(find.byKey(const ValueKey('help'))),
    );
    expect(rebuilt, contains(WorkspaceTopBar));
    expect(rebuilt, isNot(contains(SectionTabs)));
    expect(rebuilt, isNot(contains(WorkspacePageRow)));
    expect(rebuilt, isNot(contains(WorkspaceStatusBar)));
    await tester.pumpAndSettle();
    expect(
      tester.widget<IconButton>(find.byKey(const ValueKey('help'))).isSelected,
      true,
    );
  });

  testWidgets('a kept region still follows the event', (tester) async {
    final c = await onPairings(tester);
    c.change('Rename event', c.event!.copy(name: 'Winter Open'));
    c.addSection('Reserve', Format.swiss, 4);
    await tester.pump();
    expect(find.text('Winter Open'), findsOneWidget);
    expect(
      find.byKey(ValueKey('section-chip-${c.event!.sections.last.id}')),
      findsOneWidget,
    );
    c.undo();
    await tester.pump();
    expect(find.byKey(const ValueKey('section-chip-all')), findsOneWidget);
    expect(find.text('Reserve'), findsNothing);
    expect(
      tester.widget<IconButton>(find.byKey(const ValueKey('redo'))).onPressed,
      isNotNull,
    );
  });
}
