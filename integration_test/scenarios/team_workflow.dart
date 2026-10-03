import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import 'package:path/path.dart' as p;

void registerTeamWorkflowTests() {
  testWidgets(
    'native team assignment, sibling request, Swiss results and independent recovery',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('meow family é ');
      final path = p.join(folder.path, "Family's tournament.meow");
      final c = TournamentController(SqliteEventRepository(path))
        ..create('Family Swiss');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        folder.deleteSync(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: meowTheme(Brightness.light),
          home: Workspace(
            controller: c,
            path: path,
            onClose: () {},
            onTheme: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Import through the actual UI, with only the native file picker omitted.
      await tester.tap(find.text('Paste from spreadsheet'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('paste-roster')),
        'Name,Rating,US Chess ID\n${List.generate(6, (i) => 'Sibling $i,${1800 - i * 50},${12000000 + i}').join('\n')}',
      );
      await tester.tap(find.text('Import').last);
      await tester.pumpAndSettle();
      expect(c.event!.players, hasLength(6));
      await tester.tap(find.text('Create sections…'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('type-swiss')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-rounds')), '3');
      await tester.ensureVisible(find.byKey(const ValueKey('create-sections')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-sections')));
      await tester.pumpAndSettle();
      expect(c.event!.sections.single.format, Format.swiss);
      // The first and fourth seeds would normally meet in round one.
      final first = c.event!.players[0].id, sibling = c.event!.players[3].id;
      for (final id in [first, sibling]) {
        await tester.tap(
          find.descendant(
            of: find.byKey(ValueKey('player-$id')),
            matching: find.byType(PlainCheckbox),
          ),
        );
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Assign team'));
      await tester.tap(find.text('Assign team'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('field-team')),
        'Mixed doubles A',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(c.event!.player(first).team, 'Mixed doubles A');
      expect(c.event!.player(first).avoid, isEmpty);
      await tester.ensureVisible(find.text('Do not pair together'));
      await tester.tap(find.text('Do not pair together'));
      await tester.pumpAndSettle();
      expect(c.event!.player(first).avoid, {sibling});
      expect(c.event!.player(sibling).avoid, {first});
      await tester.tap(find.byKey(const ValueKey('pair-next-round')));
      await tester.pumpAndSettle();
      final games = c.event!.sections.single.rounds.single.games;
      expect(games, hasLength(3));
      expect(
        games.any((g) => {g.white, g.black}.containsAll({first, sibling})),
        false,
      );
      await tester.tap(find.byKey(ValueKey('game-${games.first.id}')));
      for (var i = 0; i < games.length; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
        await tester.pumpAndSettle();
      }
      expect(c.event!.games.every((g) => g.outcome == Outcome.draw), true);
      final expected = c.event!.encode();
      final backupPath = p.join(folder.path, 'Independent backup.meow');
      c.repository.backup(backupPath);
      final backup = SqliteEventRepository(backupPath);
      try {
        expect(backup.load()!.encode(), expected);
      } finally {
        backup.close();
      }
      expect(tester.takeException(), isNull);
    },
  );
}
