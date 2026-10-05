import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/player_panel.dart';
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
  testWidgets('optional checks fetch states and retain unresolved warnings', (
    tester,
  ) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    c.savePlayer(c.event!.player('p1').copy(state: 'MA'));
    c.savePlayer(c.event!.player('p2').copy(memberId: ''));
    final called = <String>[];
    await show(
      tester,
      c,
      () => ReportsView(
        controller: c,
        memberLookup: (id) async {
          called.add(id);
          if (id == '12000003') throw const TournamentException('HTTP 500');
          return MemberObservation(
            id: id,
            name: 'Player',
            retrievedAt: '2026-10-04',
            ratings: const {},
            state: 'NH',
          );
        },
      ),
    );
    await tester.tap(find.byKey(const PageStorageKey('rating-advice-details')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fetch-states')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(called, ['12000000', '12000003']);
    expect(c.repository.load()!.player('p0').state, 'NH');
    expect(c.event!.player('p1').state, 'MA');
    expect(c.event!.player('p2').state, isEmpty);
    expect(c.event!.player('p3').state, isEmpty);
    expect(c.event!.player('p0').rating, 2000);
    expect(find.textContaining('Saved 1 missing state.'), findsOneWidget);
    expect(find.textContaining('HTTP 500'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'state fetch cannot overwrite an ID or state edited during lookup',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final pending = Completer<MemberObservation?>();
      await show(
        tester,
        c,
        () => ReportsView(controller: c, memberLookup: (id) => pending.future),
      );
      await tester.tap(
        find.byKey(const PageStorageKey('rating-advice-details')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fetch-states')));
      await tester.pump();
      c.savePlayer(
        c.event!.player('p0').copy(memberId: '99887766', state: 'MA'),
      );
      pending.complete(
        const MemberObservation(
          id: '12000000',
          name: 'Player',
          retrievedAt: '2026-10-04',
          ratings: {},
          state: 'NH',
        ),
      );
      await tester.pump();
      expect(c.event!.player('p0').state, 'MA');
      expect(c.event!.player('p0').membershipEvidence, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

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

    // Missing player states are optional advice, folded until asked for.
    final fill = find.byKey(const ValueKey('fill-states'));
    expect(fill, findsNothing);
    await tester.tap(find.byKey(const PageStorageKey('rating-advice-details')));
    await tester.pump();
    expect(find.text('Use MA for 4 players without a state'), findsOneWidget);
    await tester.tap(fill);
    await tester.pump();
    expect(c.event!.players.map((p) => p.state).toSet(), {'MA'});
    expect(c.repository.load()!.players.map((p) => p.state).toSet(), {'MA'});
    expect(fill, findsNothing);

    // Unfinished rounds still block the export.
    final create = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('generate-dbf')),
    );
    expect(create.onPressed, isNull);
    expect(find.byKey(const ValueKey('rating-blocked')), findsOneWidget);
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
          memberLookup: (memberId) async => MemberObservation(
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
