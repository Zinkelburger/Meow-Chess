import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/ui/player_panel.dart';
import '../support.dart';

MemberObservation observation(String id, String name) => MemberObservation(
  id: id,
  name: name,
  retrievedAt: '2026-09-30',
  ratings: {'Regular': 1800},
  expiration: '2027-12-31',
  status: 'Active',
);

void main() {
  testWidgets('lookup survives saving an edited ID and applies its result', (
    tester,
  ) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final key = GlobalKey<PlayerPanelState>();
    final request = Completer<MemberObservation?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => PlayerPanel(
              key: key,
              controller: c,
              player: c.event!.players[0],
              onClose: () {},
              memberLookup: (id) {
                expect(id, '99999999');
                return request.future;
              },
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('panel-memberId')),
      '99999999',
    );
    final pending = key.currentState!.lookup();
    await tester.pump();
    request.complete(observation('99999999', 'Updated Name'));
    await pending;
    await tester.pump();
    expect(key.currentState!.member, isNotNull);
    expect(
      c.repository.load()!.players[0].membershipEvidence['expiration'],
      '2027-12-31',
    );
    expect(c.event!.players[0].rating, 2000);
    final useName = tester.widget<ActionChip>(
      find.widgetWithText(ActionChip, 'Use name Updated Name'),
    );
    useName.onPressed!();
    await tester.pump();
    expect(c.event!.players[0].name, 'Updated Name');
    expect(c.repository.load()!.players[0].name, 'Updated Name');
    // A previously rendered chip is also inert after the identity changes.
    await tester.enterText(
      find.byKey(const ValueKey('panel-memberId')),
      '88888888',
    );
    final before = c.event!.revision;
    useName.onPressed!();
    expect(c.event!.revision, before);
    await tester.pump();
  });
  for (final rating in [0, 5000]) {
    testWidgets('single-player approval rejects unavailable rating $rating', (
      tester,
    ) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final key = GlobalKey<PlayerPanelState>();
      final player = c.event!.players.first;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerPanel(
              key: key,
              controller: c,
              player: player,
              onClose: () {},
              memberLookup: (_) async => MemberObservation(
                id: player.memberId,
                name: player.name,
                retrievedAt: '2026-10-02',
                supplementDate: '2026-10-01',
                ratings: {'R': rating},
              ),
            ),
          ),
        ),
      );
      await key.currentState!.lookup();
      await tester.pump();
      tester
          .widget<ActionChip>(find.widgetWithText(ActionChip, 'R $rating'))
          .onPressed!();
      await tester.pump();
      final before = c.event!.encode();
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm rating change'),
          )
          .onPressed!();
      await tester.pump();
      expect(c.event!.encode(), before);
      expect(c.repository.load()!.players.first.rating, player.rating);
      expect(key.currentState!.error, contains('Current rating kept'));
    });
  }

  testWidgets(
    'single-player approval keeps unrelated edits and newer membership',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final key = GlobalKey<PlayerPanelState>();
      final player = c.event!.players.first;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => PlayerPanel(
                key: key,
                controller: c,
                player: c.event!.players.first,
                onClose: () {},
                memberLookup: (_) async => MemberObservation(
                  id: player.memberId,
                  name: player.name,
                  retrievedAt: '2026-10-02',
                  supplementDate: '2026-10-01',
                  ratings: {'R': 1800},
                  expiration: '2027-12-31',
                ),
              ),
            ),
          ),
        ),
      );
      await key.currentState!.lookup();
      await tester.pump();
      tester
          .widget<ActionChip>(find.widgetWithText(ActionChip, 'R 1800'))
          .onPressed!();
      await tester.pump();
      final confirm = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm rating change'),
          )
          .onPressed!;
      c.savePlayer(
        c.event!.players.first.copy(
          notes: 'Keep this note',
          membershipEvidence: {
            'id': player.memberId,
            'retrievedAt': '2026-10-04',
            'expiration': '2028-12-31',
          },
        ),
      );
      await tester.pump();
      confirm();
      await tester.pump();
      final saved = c.event!.players.first;
      expect(saved.rating, 1800);
      expect(saved.ratingEvidence['category'], 'R');
      expect(saved.notes, 'Keep this note');
      expect(saved.membershipEvidence['expiration'], '2028-12-31');
      c.undo();
      expect(c.event!.players.first.rating, player.rating);
      await tester.pump();
      c.savePlayer(c.event!.players.first.copy(rating: 1700));
      await tester.pump();
      final before = c.event!.encode();
      confirm();
      await tester.pump();
      expect(c.event!.encode(), before);
      expect(key.currentState!.error, contains('Edited since lookup'));
    },
  );

  testWidgets('late success and failure cannot affect another player lookup', (
    tester,
  ) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final requests = <Completer<MemberObservation?>>[];
    final key = GlobalKey<PlayerPanelState>();
    Future<void> show(int index) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerPanel(
            key: key,
            controller: c,
            player: c.event!.players[index],
            onClose: () {},
            memberLookup: (_) {
              final request = Completer<MemberObservation?>();
              requests.add(request);
              return request.future;
            },
          ),
        ),
      ),
    );
    await show(0);
    final first = key.currentState!.lookup();
    await show(1);
    expect(key.currentState!.looking, false);
    final second = key.currentState!.lookup();
    requests[0].complete(
      observation(c.event!.players[0].memberId, 'Wrong Player'),
    );
    await first;
    expect(key.currentState!.member, isNull);
    expect(c.event!.players[0].membershipEvidence, isEmpty);
    expect(key.currentState!.looking, true);
    requests[1].complete(
      observation(c.event!.players[1].memberId, 'Right Player'),
    );
    await second;
    await tester.pump();
    expect(key.currentState!.member!.name, 'Right Player');
    final third = key.currentState!.lookup();
    await show(2);
    final fourth = key.currentState!.lookup();
    requests[2].completeError(Exception('stale failure'));
    await third;
    expect(key.currentState!.lookupError, isNull);
    expect(key.currentState!.looking, true);
    requests[3].complete(null);
    await fourth;
    await tester.pump();
  });

  testWidgets('editing member ID invalidates pending and displayed results', (
    tester,
  ) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final key = GlobalKey<PlayerPanelState>();
    var request = Completer<MemberObservation?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerPanel(
            key: key,
            controller: c,
            player: c.event!.players[0],
            onClose: () {},
            memberLookup: (_) => request.future,
          ),
        ),
      ),
    );
    final id = c.event!.players[0].memberId;
    final pending = key.currentState!.lookup();
    await tester.enterText(
      find.byKey(const ValueKey('panel-memberId')),
      '99999999',
    );
    // Even changing back cannot revive an old request.
    await tester.enterText(find.byKey(const ValueKey('panel-memberId')), id);
    request.complete(observation(id, 'Old Result'));
    await pending;
    expect(key.currentState!.member, isNull);
    expect(key.currentState!.looking, false);
    request = Completer<MemberObservation?>();
    final current = key.currentState!.lookup();
    request.complete(observation(id, 'Current Result'));
    await current;
    await tester.pump();
    expect(key.currentState!.member, isNotNull);
    await tester.enterText(
      find.byKey(const ValueKey('panel-memberId')),
      '99999999',
    );
    expect(key.currentState!.member, isNull);
    await tester.pump();
    expect(find.text('Use name Current Result'), findsNothing);
  });
}
