import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/prizes.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/new_section_panel.dart';
import 'package:meow_chess/ui/section_panel.dart';
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

Future<void> openGroup(WidgetTester tester, String id) async {
  final group = find.byKey(ValueKey('section-group-$id'));
  await tester.ensureVisible(group);
  await tester.tap(group);
  await tester.pumpAndSettle();
}

String summaryOf(WidgetTester tester, String id) =>
    tester.getSemantics(find.byKey(ValueKey('section-group-$id'))).value;

void main() {
  testWidgets('groups read US Chess default until a rule changes, and save', (
    tester,
  ) async {
    final c = fixture(count: 8, format: Format.swiss);
    addTearDown(c.dispose);
    final q1 = c.event!.sections.first;
    await mountWorkspace(tester, c);
    await openSettings(tester, q1.id);
    expect(find.byKey(ValueKey('section-settings-${q1.id}')), findsOneWidget);
    // The context menu no longer has a separate Prizes… item.
    expect(find.text('Prizes…'), findsNothing);
    expect(summaryOf(tester, 'byes'), 'US Chess default');
    expect(summaryOf(tester, 'pairing'), 'US Chess default');
    expect(summaryOf(tester, 'prizes'), 'None');
    expect(summaryOf(tester, 'players'), 'Boards from 1');
    expect(find.text('Games per round'), findsOneWidget);

    await openGroup(tester, 'byes');
    await tester.enterText(
      find.byKey(const ValueKey('field-lastHalfByeRound')),
      '2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('field-maxHalfByes')),
      '1',
    );
    await tester.pumpAndSettle();
    await openGroup(tester, 'byes');
    expect(summaryOf(tester, 'byes'), 'Through round 2 · 1 per player');

    await openGroup(tester, 'pairing');
    await tester.ensureVisible(
      find.byKey(const ValueKey('field-avoidTeammates')),
    );
    await tester.tap(find.byKey(const ValueKey('field-avoidTeammates')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('field-variation-29E4a')),
    );
    await tester.tap(find.byKey(const ValueKey('field-variation-29E4a')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tie-breaks:'), findsOneWidget);
    await openGroup(tester, 'pairing');
    expect(summaryOf(tester, 'pairing'), 'Team-mates apart · 29E4a');

    await tester.ensureVisible(find.byKey(const ValueKey('save-section')));
    await tester.tap(find.byKey(const ValueKey('save-section')));
    await tester.pumpAndSettle();
    final saved = c.event!.sections.first;
    expect(saved.byeRules, {'lastHalfByeRound': 2, 'maxHalfByes': 1});
    expect(saved.avoidTeammates, isTrue);
    expect(saved.variations, {'29E4a'});
    expect(find.byKey(ValueKey('section-settings-${q1.id}')), findsNothing);
  });

  testWidgets('a problem inside a closed group opens it beside the field', (
    tester,
  ) async {
    final c = fixture(count: 8, format: Format.swiss);
    addTearDown(c.dispose);
    final q1 = c.event!.sections.first;
    await mountWorkspace(tester, c);
    await openSettings(tester, q1.id);
    await openGroup(tester, 'byes');
    await tester.enterText(
      find.byKey(const ValueKey('field-irrevocableFromRound')),
      '9',
    );
    await openGroup(tester, 'byes');
    expect(
      find.byKey(const ValueKey('field-irrevocableFromRound')),
      findsNothing,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('save-section')));
    await tester.tap(find.byKey(const ValueKey('save-section')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('field-irrevocableFromRound')),
      findsOneWidget,
    );
    expect(
      find.text('Bye policy rounds cannot exceed the 3 planned rounds.'),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
    expect(c.event!.sections.first.byeRules, isEmpty);
  });

  testWidgets('after round 1 the format is locked, byes and prizes are not', (
    tester,
  ) async {
    final c = fixture(count: 8, format: Format.swiss);
    addTearDown(c.dispose);
    final q1 = c.event!.sections.first;
    c.post((await tester.runAsync(() => c.propose(sectionId: q1.id)))!);
    await mountWorkspace(tester, c);
    await openSettings(tester, q1.id);
    expect(find.byKey(const ValueKey('field-format')), findsNothing);
    expect(find.byKey(const ValueKey('field-format-locked')), findsOneWidget);
    expect(find.byKey(const ValueKey('field-doubleGames')), findsNothing);
    expect(find.byKey(const ValueKey('field-double-locked')), findsOneWidget);
    expect(summaryOf(tester, 'pairing'), 'Set before round 1');
    expect(find.byIcon(Icons.lock_outline), findsWidgets);
    await openGroup(tester, 'pairing');
    expect(find.byKey(const ValueKey('field-accelerated')), findsNothing);
    expect(find.textContaining('Accelerated pairings'), findsOneWidget);
    // Byes still edit and save.
    await openGroup(tester, 'byes');
    await tester.enterText(
      find.byKey(const ValueKey('field-maxHalfByes')),
      '2',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('save-section')));
    await tester.tap(find.byKey(const ValueKey('save-section')));
    await tester.pumpAndSettle();
    expect(c.event!.sections.first.byeRules, {'maxHalfByes': 2});
    expect(c.event!.sections.first.rounds, hasLength(1));
  });

  testWidgets('prizes are edited inside the Prizes group', (tester) async {
    final c = fixture(count: 8, format: Format.swiss);
    addTearDown(c.dispose);
    final q1 = c.event!.sections.first;
    await mountWorkspace(tester, c);
    await openSettings(tester, q1.id);
    await openGroup(tester, 'prizes');
    await tester.ensureVisible(find.byKey(const ValueKey('add-prize')));
    await tester.tap(find.byKey(const ValueKey('add-prize')));
    await tester.pumpAndSettle();
    final id = PrizeTable.fromJson(
      c.event!.sections.first.prizes,
    ).list.single.id;
    await tester.enterText(find.byKey(ValueKey('prize-cents-$id')), '100');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await openGroup(tester, 'prizes');
    expect(summaryOf(tester, 'prizes'), '\$100 · 1 prize');
  });

  group('New section', () {
    Future<List<List<String>>> open(
      WidgetTester tester,
      TournamentController c,
    ) async {
      final created = <List<String>>[];
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: meowTheme(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 360,
                child: ListenableBuilder(
                  listenable: c,
                  builder: (_, _) => NewSectionPanel(
                    controller: c,
                    ticked: const {},
                    onCreated: created.add,
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return created;
    }

    testWidgets('Other format… lists every rare format and Holland', (
      tester,
    ) async {
      final c = TournamentController(SqliteEventRepository(':memory:'))
        ..create('Club night');
      addTearDown(c.dispose);
      c.importPlayers([
        for (var i = 0; i < 8; i++)
          Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 50),
      ]);
      await open(tester, c);
      await tester.tap(find.byKey(const ValueKey('new-section-other-format')));
      await tester.pumpAndSettle();
      // One press: the select is showing with its list open.
      for (final f in Format.values.where((f) => !f.common)) {
        expect(find.text(f.label), findsWidgets);
      }
      expect(find.text('Holland system (30H)'), findsOneWidget);
      await tester.tap(find.text('Knockout').last);
      await tester.pumpAndSettle();
      final segments = tester.widget<SegmentedButton<Format>>(
        find.byKey(const ValueKey('new-section-format')),
      );
      expect(segments.selected, isEmpty);
      expect(find.text('A bracket of mini-matches; losers are out.'), findsOne);
      expect(find.text('Games per round'), findsOneWidget);
      // Back to a common format from the segments.
      await tester.tap(find.text('Swiss'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('new-section-other-format-select')),
        findsNothing,
      );
      expect(
        find.text('Players meet others on the same score each round.'),
        findsOne,
      );
    });

    testWidgets('announced rules travel into the created section', (
      tester,
    ) async {
      final c = TournamentController(SqliteEventRepository(':memory:'))
        ..create('Club night');
      addTearDown(c.dispose);
      c.importPlayers([
        for (var i = 0; i < 6; i++)
          Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 50),
      ]);
      final created = await open(tester, c);
      await tester.enterText(
        find.byKey(const ValueKey('new-section-name')),
        'Open',
      );
      await tester.enterText(
        find.byKey(const ValueKey('new-section-rounds')),
        '4',
      );
      await tester.enterText(
        find.byKey(const ValueKey('new-section-timeControl')),
        'G/25',
      );
      await tester.pumpAndSettle();
      // The band says what the control rates as and what 5E2 adds.
      expect(find.textContaining('Quick'), findsOneWidget);
      expect(find.textContaining('rule 5E2'), findsOneWidget);
      await tester.tap(find.text('Two'));
      await openGroup(tester, 'players');
      await tester.enterText(
        find.byKey(const ValueKey('new-section-ratingCeiling')),
        '1900',
      );
      await openGroup(tester, 'byes');
      await tester.enterText(
        find.byKey(const ValueKey('new-section-maxHalfByes')),
        '1',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('create-section')));
      await tester.tap(find.byKey(const ValueKey('create-section')));
      await tester.pumpAndSettle();
      final s = c.event!.sections.single;
      expect(created.single, [s.id]);
      expect(s.name, 'Open');
      expect(s.plannedRounds, 4);
      expect(s.timeControl, 'G/25');
      expect(s.doubleGames, isTrue);
      expect(s.ratingCeiling, 1900);
      expect(s.byeRules, {'maxHalfByes': 1});
      expect(s.players, hasLength(6));
      // Group state is remembered across panels.
      expect(c.workspaceState.read(sectionGroupPref('byes')), 'open');
    });
  });
}
