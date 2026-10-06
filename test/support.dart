import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

TournamentController fixture({
  int count = 8,
  Format format = Format.quad,
  bool practice = false,
  String path = ':memory:',
}) {
  final c = TournamentController(SqliteEventRepository(path));
  c.create('Saturday Quads', practice: practice);
  c.importPlayers([
    for (var i = 0; i < count; i++)
      Player(
        id: 'p$i',
        name: 'Player ${i.toString().padLeft(2, '0')}',
        rating: 2000 - i * 50,
        memberId: '${12000000 + i}',
        checkedIn: true,
      ),
  ]);
  c.applyQuads(c.quadPreview(), c.event!.revision);
  if (format != Format.quad) {
    c.change(
      'Use requested test format',
      c.event!.copy(
        sections: [
          for (final section in c.event!.sections) section.copy(format: format),
        ],
      ),
    );
  }
  return c;
}

// Legacy practice-file fixture; practice creation is no longer exposed.
Future<void> markPracticeCopy(String path) async {
  final repository = SqliteEventRepository(path);
  try {
    final event = repository.load()!;
    repository.commit(
      event.copy(practice: true, backupFolder: ''),
      expectedRevision: event.revision,
      action: 'Mark practice copy',
    );
  } finally {
    repository.close();
  }
}

/// Opens a collapsed group in the player panel, such as `byes` or `notes`.
Future<void> openPanelGroup(WidgetTester tester, String id) async {
  final group = find.byKey(ValueKey('group-$id'));
  final open = find.descendant(
    of: group,
    matching: find.byIcon(Icons.expand_more),
  );
  if (open.evaluate().isNotEmpty) return;
  await tester.ensureVisible(group);
  await tester.tap(group);
  await tester.pump();
}

/// Requests (or, if already chosen, clears) a bye in the player panel.
/// [points] is in half points: 1 = ½, 0 = zero, 2 = full.
Future<void> toggleBye(WidgetTester tester, int round, int points) async {
  final bye = find.byKey(ValueKey('bye-$round-$points'));
  if (bye.evaluate().isEmpty) await openPanelGroup(tester, 'byes');
  await tester.ensureVisible(bye);
  await tester.tap(bye);
  await tester.pump();
}

/// Opens a [PlainSelect] and picks the option labelled [label].
Future<void> chooseOption(
  WidgetTester tester,
  Finder field,
  String label,
) async {
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, label).last);
  await tester.pumpAndSettle();
}
