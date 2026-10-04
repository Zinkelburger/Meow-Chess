import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/update_panels.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';

MemberObservation member(String id, {String? expiration = '2020-01-31'}) =>
    MemberObservation(
      id: id,
      name: 'Official Name',
      retrievedAt: '2026-10-03T12:00:00Z',
      expiration: expiration,
      status: 'Active',
      ratings: const {},
    );

Future<void> finishBatch(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Players show expired dates with a warning and refresh action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final p = c.event!.players.first;
    c.savePlayer(
      p.copy(registrationNote: 'Arriving late', notes: 'Private TD note'),
    );
    c.recordMembership(c.event!.id, p.id, member(p.memberId).toJson());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlayersView(controller: c)),
      ),
    );
    expect(find.text('USCF expires'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('Arriving late'), findsOneWidget);
    expect(find.byTooltip('Arriving late'), findsOneWidget);
    expect(find.text('Private TD note'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Note')).dx,
      greaterThan(tester.getTopLeft(find.text('USCF expires')).dx),
    );
    final date = tester.widget<Text>(find.text('2020-01-31'));
    expect(
      date.style!.color,
      Theme.of(tester.element(find.text('2020-01-31'))).colorScheme.error,
    );
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('Not checked'), findsNWidgets(3));
    await tester.tap(find.byKey(const ValueKey('player-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check memberships'));
    await tester.pumpAndSettle();
    expect(find.text('Check USCF memberships'), findsOneWidget);
    expect(find.text('Fetch memberships'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'expiry warning stays aligned and clear of notes in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = fixture(count: 4);
        addTearDown(c.dispose);
        final now = DateTime.now();
        final expiration = DateTime(
          now.year,
          now.month + 1,
          0,
        ).toIso8601String().substring(0, 10);
        final p = c.event!.players.first;
        c.savePlayer(p.copy(registrationNote: 'Arriving late'));
        final other = c.event!.players[1];
        c.recordMembership(
          c.event!.id,
          other.id,
          member(other.memberId, expiration: '2099-12-31').toJson(),
        );
        c.recordMembership(
          c.event!.id,
          p.id,
          member(p.memberId, expiration: expiration).toJson(),
        );
        final theme = meowTheme(brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(body: PlayersView(controller: c)),
          ),
        );
        expect(find.text('Expires this month'), findsOneWidget);
        expect(find.text('Expired'), findsNothing);
        final date = tester.widget<Text>(find.text(expiration));
        expect(
          date.style!.color,
          brightness == Brightness.dark
              ? const Color(0xffffd966)
              : const Color(0xff785500),
        );
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              builder: (_, child) => MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(body: PlayersView(controller: c)),
            ),
          );
          await tester.pumpAndSettle();
          final dateRect = tester.getRect(find.text(expiration));
          final normalRect = tester.getRect(find.text('2099-12-31'));
          final warningRect = tester.getRect(find.text('Expires this month'));
          final noteRect = tester.getRect(find.text('Arriving late'));
          expect(dateRect.left, normalRect.left);
          expect(
            dateRect.left,
            tester.getTopLeft(find.text('USCF expires')).dx,
          );
          expect(warningRect.left, dateRect.left);
          expect(warningRect.top, greaterThanOrEqualTo(dateRect.bottom));
          expect(warningRect.right, lessThanOrEqualTo(noteRect.left - 12));
          expect(dateRect.right, lessThan(noteRect.left));
          expect(tester.takeException(), isNull);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'membership check saves unrated and posted players, retains data on failure',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.savePlayer(c.event!.players.first.copy(rating: 0));
      c.post((await tester.runAsync(() => c.propose()))!);
      final previous = c.event!.players[1];
      c.recordMembership(
        c.event!.id,
        previous.id,
        member(previous.memberId, expiration: '2028-12-31').toJson(),
      );
      final ratings = c.event!.players.map((p) => p.rating).toList();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RatingsRefreshPanel.membership(
              controller: c,
              onClose: () {},
              lookup: (id) async {
                if (id == previous.memberId) {
                  throw const TournamentException('Lookup failed; try later.');
                }
                return member(id);
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Fetch memberships'));
      await finishBatch(tester);
      expect(
        c.repository.load()!.players.first.membershipEvidence['expiration'],
        '2020-01-31',
      );
      expect(
        c.event!.players[1].membershipEvidence['expiration'],
        '2028-12-31',
      );
      expect(c.event!.players.map((p) => p.rating), ratings);
      expect(c.event!.players.first.ratingEvidence['supplementDate'], isNull);
      expect(find.text('Lookup failed; try later.'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a roster edit during a membership request stops the batch', (
    tester,
  ) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final request = Completer<MemberObservation?>();
    final original = c.event!.players.first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RatingsRefreshPanel.membership(
            controller: c,
            onClose: () {},
            lookup: (_) => request.future,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fetch memberships'));
    await tester.pump();
    c.savePlayer(original.copy(memberId: '99999999'));
    request.complete(member(original.memberId));
    await finishBatch(tester);
    expect(c.event!.players.first.membershipEvidence, isEmpty);
    expect(
      find.text('The event changed. Fetch again to check the current roster.'),
      findsOneWidget,
    );
  });
}
