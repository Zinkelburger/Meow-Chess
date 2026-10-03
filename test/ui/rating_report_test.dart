import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/reports_view.dart';
import '../support.dart';

Future<void> show(
  WidgetTester tester,
  TournamentController c,
  Widget Function() child,
) {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(listenable: c, builder: (_, _) => child()),
      ),
    ),
  );
}

void main() {
  testWidgets('report details save inline and fill missing states on request', (
    tester,
  ) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    await show(tester, c, () => ReportsView(controller: c));
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('report-city')), 'Boston');
    await tester.enterText(find.byKey(const ValueKey('report-state')), 'ma');
    await tester.enterText(find.byKey(const ValueKey('report-zip')), '02116');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      (c.event!.city, c.event!.state, c.event!.zip),
      ('Boston', 'MA', '02116'),
    );
    expect(find.byKey(const ValueKey('rating-summary')), findsOneWidget);
    expect(find.textContaining('Regular'), findsWidgets);

    final fill = find.byKey(const ValueKey('fill-states'));
    expect(find.text('Use MA for 4 players without a state'), findsOneWidget);
    await tester.tap(fill);
    await tester.pump();
    expect(c.event!.players.map((p) => p.state).toSet(), {'MA'});
    expect(c.repository.load()!.players.map((p) => p.state).toSet(), {'MA'});
    expect(fill, findsNothing);

    // Unfinished rounds still block the export.
    final create = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Generate DBF files'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      ),
    );
    expect(create.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'player state is checked and lookups fill state and report name',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final key = GlobalKey<PlayerPanelState>();
      final id = c.event!.players[0].id;
      await show(
        tester,
        c,
        () => PlayerPanel(
          key: key,
          controller: c,
          player: c.event!.player(id),
          onClose: () {},
          memberLookup: (_, memberId) async => MemberObservation(
            id: memberId,
            name: 'Morgan Lee',
            retrievedAt: '2026-09-30',
            ratings: const {},
            state: 'NH',
            reportName: 'LEE, MORGAN',
          ),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('panel-state')), 'M1');
      expect(key.currentState!.commit(), false);
      await tester.pump();
      expect(find.textContaining('two letters'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('panel-state')), 'ma');
      expect(key.currentState!.commit(), true);
      expect(c.event!.player(id).state, 'MA');
      await tester.pump();
      expect(key.currentState!.text['state']!.text, 'MA');
      expect(key.currentState!.dirty, false);

      await key.currentState!.lookup();
      await tester.pump();
      await tester.tap(find.text('Use state NH'));
      await tester.pump();
      expect(c.event!.player(id).state, 'NH');
      await tester.tap(find.text('Report as LEE, MORGAN'));
      await tester.pump();
      expect(c.event!.player(id).reportName, 'LEE, MORGAN');
      expect(find.text('Report as LEE, MORGAN'), findsNothing);
    },
  );
}
