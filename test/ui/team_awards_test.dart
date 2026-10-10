import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/team_standings.dart';
import 'package:meow_chess/ui/players_view.dart';
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

Future<void> openSettings(WidgetTester tester, String sectionId) async {
  await tester.tap(find.byKey(ValueKey('section-chip-$sectionId')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(ValueKey('section-chip-$sectionId')),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Rename / section settings…'));
  await tester.pumpAndSettle();
}

String summaryOf(WidgetTester tester, String id) =>
    tester.getSemantics(find.byKey(ValueKey('section-group-$id'))).value;

/// Labels the first section's players with two schools.
void labelSchools(TournamentController c) {
  final ids = c.event!.sections.first.players;
  c.change(
    'Label schools',
    c.event!.copy(
      players: [
        for (final p in c.event!.players)
          ids.contains(p.id)
              ? p.copy(team: ids.indexOf(p.id).isEven ? 'Lincoln' : 'Grant')
              : p,
      ],
    ),
  );
}

void main() {
  testWidgets('Team awards appear with two schools and save top N', (
    tester,
  ) async {
    final c = fixture(count: 8, format: Format.swiss);
    addTearDown(c.dispose);
    final s = c.event!.sections.first;
    await mountWorkspace(tester, c);
    await openSettings(tester, s.id);
    // No team labels: no fifth group.
    expect(find.byKey(const ValueKey('section-group-teams')), findsNothing);

    // The open panel follows the roster: two schools offer the group.
    labelSchools(c);
    await tester.pumpAndSettle();
    final header = find.byKey(const ValueKey('section-group-teams'));
    expect(header, findsOneWidget);
    expect(summaryOf(tester, 'teams'), 'Off');
    await tester.ensureVisible(header);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.textContaining('2 teams: Lincoln, Grant'), findsOneWidget);
    // Off shows no count field.
    expect(find.byKey(const ValueKey('field-teamCounting')), findsNothing);
    await chooseOption(
      tester,
      find.byKey(const ValueKey('field-teamMethod')),
      'Top N scores',
    );
    await tester.enterText(
      find.byKey(const ValueKey('field-teamCounting')),
      '3',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-section')));
    await tester.pumpAndSettle();
    final saved = TeamAwards.of(c.event!.sections.first)!;
    expect(saved.counting, 3);
    expect(saved.method, TeamScoring.topN);

    // Closed, the group states the announced method.
    await openSettings(tester, s.id);
    await tester.ensureVisible(header);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(summaryOf(tester, 'teams'), 'Top 3 scores count');

    // A bad count is reported beside the field, which opens its group.
    await tester.tap(header);
    await tester.pumpAndSettle();
    await chooseOption(
      tester,
      find.byKey(const ValueKey('field-teamMethod')),
      'Rollins (31A1)',
    );
    await tester.enterText(
      find.byKey(const ValueKey('field-teamCounting')),
      'four',
    );
    await tester.tap(find.byKey(const ValueKey('save-section')));
    await tester.pumpAndSettle();
    expect(
      find.text('Scores that count is a number of players, like 4 or 3.'),
      findsOneWidget,
    );
    expect(TeamAwards.of(c.event!.sections.first)!.method, TeamScoring.topN);
    await tester.pumpWidget(const SizedBox());
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the Teams table sits under the standings at ${scale}x', (
      tester,
    ) async {
      final c = fixture(count: 8, format: Format.swiss);
      addTearDown(c.dispose);
      labelSchools(c);
      final s = c.event!.sections.first;
      c.change(
        'Team awards',
        c.event!.copy(
          sections: [
            for (final x in c.event!.sections)
              x.id == s.id
                  ? withTeamAwards(x, const TeamAwards(counting: 2))
                  : x,
          ],
        ),
      );
      c.post((await tester.runAsync(() => c.propose()))!);
      for (final g in c.event!.games) {
        c.recordResult(g.id, Outcome.whiteWin);
      }
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: ListenableBuilder(
                  listenable: c,
                  builder: (_, _) => PlayersView(
                    controller: c,
                    sectionId: s.id,
                    standingsOnly: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final table = find.byKey(ValueKey('team-standings-${s.id}'));
      await tester.dragUntilVisible(
        table,
        find.byType(ListView).first,
        const Offset(0, -200),
      );
      expect(table, findsOneWidget);
      expect(
        find.descendant(of: table, matching: find.text('Lincoln')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: table, matching: find.text('Grant')),
        findsOneWidget,
      );
      final rows = teamStandings(c.event!, c.event!.sections.first);
      expect(rows.map((t) => t.rank), [1, 2]);
      // The leader's row comes first and shows its score.
      final first = find.byKey(ValueKey('team-row-${rows.first.team}'));
      final second = find.byKey(ValueKey('team-row-${rows.last.team}'));
      expect(
        tester.getTopLeft(first).dy,
        lessThan(tester.getTopLeft(second).dy),
      );
      expect(
        find.descendant(of: first, matching: find.text(rows.first.scoreText)),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
