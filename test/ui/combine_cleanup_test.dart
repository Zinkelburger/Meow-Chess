import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/panels.dart';

import '../support.dart';
import 'workspace_host.dart';

void main() {
  final confirm = find.byKey(const ValueKey('combine-confirm'));
  String preview(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('combine-preview')),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data)
      .join('\n');

  testWidgets('combining an unpaired section removes its emptied tab', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    await mountWorkspace(tester, c);
    await tabMenu(tester, q1.id, 'Combine sections…');
    await tester.tap(find.byKey(ValueKey('combine-into-${q2.id}')));
    await tester.pump();
    expect(
      preview(tester),
      contains(
        'Moves all 4 players of ${q1.name} into ${q2.name} and removes '
        'the ${q1.name} tab',
      ),
    );
    // The button says what it will do.
    expect(find.text('Combine into ${q2.name} · 8 players'), findsOneWidget);
    // Nothing has been played, so no reason is asked for.
    expect(find.byKey(const ValueKey('combine-reason')), findsNothing);
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(c.event!.sections.single.id, q2.id);
    expect(c.event!.sections.single.players, hasLength(8));
    expect(find.byType(CombinePanel), findsNothing);
    expect(find.byKey(ValueKey('section-chip-${q1.id}')), findsNothing);
    // The players' new section is the one shown.
    expect(find.byKey(ValueKey('section-menu-${q2.id}')), findsOneWidget);
    // The usual toast says what happened.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('undo-notice')),
        matching: find.textContaining(
          'Combined ${q1.name} into ${q2.name} and removed the empty '
          '${q1.name} tab',
        ),
      ),
      findsOneWidget,
    );
    // One step: Undo brings the tab back with its players in it.
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(c.event!.sections.map((s) => s.id), [q1.id, q2.id]);
    expect(c.event!.sections.first.players, q1.players);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a played section stays, and the preview says what follows', (
    tester,
  ) async {
    final c = fixture(format: Format.roundRobin);
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    c.post((await tester.runAsync(() => c.propose()))!);
    for (final g in c.event!.games.toList()) {
      c.recordResult(g.id, Outcome.draw);
    }
    await mountWorkspace(tester, c);
    await tabMenu(tester, q1.id, 'Combine sections…');
    await tester.tap(find.byKey(ValueKey('combine-into-${q2.id}')));
    await tester.pump();
    final words = preview(tester);
    expect(
      words,
      contains('${q1.name} keeps its played rounds and stays as an empty tab.'),
    );
    expect(words, contains('${q2.name}, which pairs as a Swiss'));
    expect(words, contains('the US Chess rating report cannot be made'));
    // A consequence in plain words, not a rule citation.
    expect(words, isNot(contains('Rule')));
    expect(words.toLowerCase(), isNot(contains('transition')));

    await tester.enterText(
      find.byKey(const ValueKey('combine-reason')),
      'Too few players',
    );
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    final after = {for (final s in c.event!.sections) s.id: s};
    expect(after.keys, [q1.id, q2.id]);
    expect(after[q1.id]!.players, isEmpty);
    expect(after[q1.id]!.rounds, hasLength(1));
    expect(after[q2.id]!.players, hasLength(8));
    expect(after[q2.id]!.format, Format.swiss);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('undo-notice')),
        matching: find.text('Combined ${q1.name} into ${q2.name}.'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pairings nobody has played are discarded and made again', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    // Round 1 is up in both four-player sections; no result is in.
    c.post((await tester.runAsync(() => c.propose()))!);
    expect(c.event!.sections.map((s) => s.rounds.length), [1, 1]);
    await mountWorkspace(tester, c);
    await tabMenu(tester, q1.id, 'Combine sections…');
    // One other section: already chosen.
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      q2.id,
    );
    expect(
      preview(tester),
      contains(
        'Round 1 is paired but no result is in, so those pairings are '
        'discarded and ${q2.name} is paired again with everyone.',
      ),
    );
    expect(find.byKey(const ValueKey('combine-reason')), findsNothing);
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 300 &&
            (c.event!.sections.length != 1 ||
                c.event!.sections.single.rounds.isEmpty);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    final combined = c.event!.sections.single;
    expect(combined.id, q2.id);
    expect(combined.players, hasLength(8));
    // One round 1, with all eight players on four boards.
    expect(combined.rounds, hasLength(1));
    expect(combined.rounds.single.games, hasLength(4));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('undo-notice')),
        matching: find.textContaining('Round 1 is paired again with everyone'),
      ),
      findsOneWidget,
    );
    // Undo once for the pairings, again for the combine.
    c.undo();
    expect(c.event!.sections.single.rounds, isEmpty);
    c.undo();
    expect(c.event!.sections.map((s) => s.rounds.length), [1, 1]);
    expect(c.event!.sections.first.players, q1.players);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the preview counts players too low to play up into the section', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    // p4–p7 (1800–1650) under 1900. Playing up into the Open takes 1700.
    c.change(
      'Name the sections',
      c.event!.copy(
        playUpLimit: 200,
        sections: [
          c.event!.sections[0].copy(name: 'Open'),
          c.event!.sections[1].copy(name: 'U1900', ratingCeiling: 1900),
        ],
      ),
    );
    final [open, u1900] = c.event!.sections;
    await mountWorkspace(tester, c);
    await tabMenu(tester, u1900.id, 'Combine sections…');
    await tester.tap(find.byKey(ValueKey('combine-into-${open.id}')));
    await tester.pump();
    expect(
      preview(tester),
      contains(
        '1 of them is rated outside what Open takes (1700 or more to play up)',
      ),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('either section can be the one that stays', (tester) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    // p0–p3 (2000–1850) in the Open, p4–p7 under them in a capped section.
    c.change(
      'Name the sections',
      c.event!.copy(
        sections: [
          c.event!.sections[0].copy(name: 'Open'),
          c.event!.sections[1].copy(name: 'U1850', ratingCeiling: 1850),
        ],
      ),
    );
    final [open, u1850] = c.event!.sections;
    await mountWorkspace(tester, c);
    // Opened from the Open's tab, yet nothing says the Open is the one to go.
    await tabMenu(tester, open.id, 'Combine sections…');
    expect(find.text('Combine sections'), findsOneWidget);
    // Two sections: nothing to tick, only which way.
    expect(find.byKey(ValueKey('combine-pick-${open.id}')), findsNothing);
    expect(find.text('U1850 into Open'), findsOneWidget);
    expect(find.text('Open into U1850'), findsOneWidget);
    // The section whose rating range takes everyone is offered first.
    RadioGroup<String> group() =>
        tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>));
    expect(group().groupValue, open.id);
    expect(find.text('Combine into Open · 8 players'), findsOneWidget);
    expect(preview(tester), contains('Moves all 4 players of U1850 into Open'));
    expect(preview(tester), isNot(contains('rated outside')));

    // The other way round is one click.
    await tester.tap(find.byKey(ValueKey('combine-into-${u1850.id}')));
    await tester.pump();
    expect(group().groupValue, u1850.id);
    expect(find.text('Combine into U1850 · 8 players'), findsOneWidget);
    expect(
      preview(tester),
      allOf(
        contains(
          'Moves all 4 players of Open into U1850 and removes the '
          'Open tab',
        ),
        contains('U1850 keeps its own name, format, rounds and settings.'),
        contains('4 of them are rated outside what U1850 takes (under 1850)'),
      ),
    );
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(c.event!.sections.single.id, u1850.id);
    expect(c.event!.sections.single.players, hasLength(8));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('undo-notice')),
        matching: find.textContaining(
          'Combined Open into U1850 and removed the empty Open tab',
        ),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with more sections, the ones to combine are ticked', (
    tester,
  ) async {
    final c = fixture(count: 12, format: Format.swiss);
    addTearDown(c.dispose);
    final [q1, q2, q3] = c.event!.sections;
    await mountWorkspace(tester, c);
    await tabMenu(tester, q1.id, 'Combine sections…');
    // The tab it was opened from is ticked; the direction waits for another.
    bool ticked(Section s) => tester
        .widget<CheckboxListTile>(find.byKey(ValueKey('combine-pick-${s.id}')))
        .value!;
    expect([ticked(q1), ticked(q2), ticked(q3)], [true, false, false]);
    expect(find.byType(RadioGroup<String>), findsNothing);
    expect(
      find.text('Tick the section to combine with ${q1.name}.'),
      findsOneWidget,
    );
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    expect(
      find.text('Tick the sections to combine: at least two.'),
      findsOneWidget,
    );
    expect(c.event!.sections, hasLength(3));

    // All three become one, in whichever of them is chosen.
    await tester.tap(find.byKey(ValueKey('combine-pick-${q2.id}')));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('combine-pick-${q3.id}')));
    await tester.pump();
    expect(
      find.text('${q1.name} and ${q2.name} into ${q3.name}'),
      findsOneWidget,
    );
    expect(
      find.text('${q2.name} and ${q3.name} into ${q1.name}'),
      findsOneWidget,
    );
    final first = find.byKey(ValueKey('combine-into-${q1.id}'));
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pump();
    expect(
      preview(tester),
      contains(
        'Moves all 8 players of ${q2.name} and ${q3.name} into ${q1.name} '
        'and removes the ${q2.name} and ${q3.name} tabs',
      ),
    );
    await tester.ensureVisible(confirm);
    expect(find.text('Combine into ${q1.name} · 12 players'), findsOneWidget);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(c.event!.sections.single.id, q1.id);
    expect(c.event!.sections.single.players, hasLength(12));
    // One step to undo, however many sections went.
    c.undo();
    expect(c.event!.sections.map((s) => s.id), [q1.id, q2.id, q3.id]);
    expect(c.event!.sections.map((s) => s.players.length), [4, 4, 4]);
    await tester.pumpWidget(const SizedBox());
  });

  test('a round with a result in still has to be finished first', () {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    c.change(
      'Pair',
      c.event!.copy(
        sections: [
          for (final s in c.event!.sections)
            s.copy(
              rounds: [
                Round(
                  number: 1,
                  games: [
                    Game(
                      id: 'g-${s.id}',
                      white: s.players[0],
                      black: s.players[1],
                      board: s.boardStart,
                    ),
                    Game(
                      id: 'h-${s.id}',
                      white: s.players[2],
                      black: s.players[3],
                      board: s.boardStart + 1,
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
    c.recordResult('g-${q1.id}', Outcome.whiteWin);
    expect(
      () => c.combineSections([q1.id], q2.id),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('Enter the results of the round being played'),
        ),
      ),
    );
    // Nothing was discarded by the refused attempt.
    expect(c.event!.sections.map((s) => s.rounds.length), [1, 1]);
  });
}
