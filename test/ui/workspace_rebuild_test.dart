import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/workspace.dart';

import 'workspace_host.dart';

/// Counts what the workspace asks of the event file.
class _Counting extends SqliteEventRepository {
  _Counting() : super(':memory:');
  final writes = <String>[];
  final reads = <String>[];
  bool refuseDrafts = false;

  @override
  void writePreference(String key, String value) {
    if (refuseDrafts && key.startsWith('draft-')) {
      throw const TournamentException('The disk is full.');
    }
    writes.add(key);
    super.writePreference(key, value);
  }

  @override
  String? readPreference(String key) {
    reads.add(key);
    return super.readPreference(key);
  }
}

void main() {
  late _Counting file;
  late TournamentController c;

  setUp(() {
    file = _Counting();
    c = TournamentController(file);
    c.create('Saturday Swiss');
    c.importPlayers([
      for (var i = 0; i < 8; i++)
        Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 50),
    ]);
    c.applyQuads(c.quadPreview(), c.event!.revision);
  });
  tearDown(() => c.dispose());

  /// Workspace rebuilds from here on.
  int Function() countBuilds() {
    var builds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is Workspace) builds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    return () => builds;
  }

  testWidgets('typing in a panel does not rebuild the workspace', (
    tester,
  ) async {
    final id = c.event!.sections.first.id;
    await mountWorkspace(tester, c);
    await tabMenu(tester, id, 'Rename / section settings…');
    final builds = countBuilds();
    file.writes.clear();
    file.reads.clear();
    const typed = ['O', 'Op', 'Ope', 'Open', 'Open A'];
    for (final text in typed) {
      await tester.enterText(find.byKey(const ValueKey('field-name')), text);
      await tester.pump();
    }
    // The draft is written as it is typed, and that is all that happens.
    expect(builds(), 0);
    expect(file.writes, List.filled(typed.length, 'draft-section-$id'));
    expect(file.reads.where((key) => key == 'lastBackup'), isEmpty);
    // The typing is all there, on screen and in the file.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('field-name')))
          .controller!
          .text,
      'Open A',
    );
    expect(c.workspaceState.read('draft-section-$id'), contains('Open A'));
    debugOnRebuildDirtyWidget = null;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the last backup is read again only when the event changes', (
    tester,
  ) async {
    await mountWorkspace(tester, c);
    int backupReads() => file.reads.where((k) => k == 'lastBackup').length;
    final before = backupReads();
    // Redraws for other reasons, such as opening and closing panels.
    await tester.tap(find.byKey(const ValueKey('event-details')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('event-details')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();
    expect(backupReads(), before);
    c.savePlayer(c.event!.players.first.copy(name: 'Renamed'));
    await tester.pumpAndSettle();
    expect(backupReads(), before + 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a draft that cannot be written is still reported', (
    tester,
  ) async {
    final id = c.event!.sections.first.id;
    await mountWorkspace(tester, c);
    await tabMenu(tester, id, 'Rename / section settings…');
    final failed = find.textContaining('Draft or workspace state not saved');
    expect(failed, findsNothing);
    file.refuseDrafts = true;
    await tester.enterText(find.byKey(const ValueKey('field-name')), 'Open');
    await tester.pumpAndSettle();
    expect(failed, findsOneWidget);
    file.refuseDrafts = false;
    final retry = find.descendant(
      of: find.byKey(const ValueKey('status-bar')),
      matching: find.text('Retry'),
    );
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(failed, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
