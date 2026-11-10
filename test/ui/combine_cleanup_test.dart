import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/panels.dart';

import '../support.dart';
import 'workspace_host.dart';

void main() {
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
    await tester.ensureVisible(find.text('Combine'));
    await tester.tap(find.text('Combine'));
    await tester.pumpAndSettle();
    expect(c.event!.sections.single.id, q2.id);
    expect(c.event!.sections.single.players, hasLength(8));
    expect(find.byType(CombinePanel), findsNothing);
    expect(find.byKey(ValueKey('section-chip-${q1.id}')), findsNothing);
    // The players' new section is the one shown.
    expect(find.byKey(ValueKey('section-menu-${q2.id}')), findsOneWidget);
    // The usual toast says what happened, including that it was two steps.
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
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(c.event!.sections.map((s) => s.id), [q1.id, q2.id]);
    expect(c.event!.sections.first.players, isEmpty);
    c.undo();
    await tester.pumpAndSettle();
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
    await tester.ensureVisible(find.text('Combine'));
    await tester.tap(find.text('Combine'));
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
}
