import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/ui/players_view.dart';
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
        home: Scaffold(
          body: PlayersView(controller: c, onRefreshRatings: () {}),
        ),
      ),
    );
    expect(find.text('USCF expires'), findsOneWidget);
    expect(find.text('Registration note'), findsOneWidget);
    expect(find.text('Arriving late'), findsOneWidget);
    expect(find.byTooltip('Arriving late'), findsOneWidget);
    expect(find.text('Private TD note'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Registration note')).dx,
      greaterThan(tester.getTopLeft(find.text('USCF expires')).dx),
    );
    // Date and warning share one line so the row height never changes.
    final expired = find.text('2020-01-31  Expired');
    expect(
      tester.widget<Text>(expired).textSpan!.style!.color,
      Theme.of(tester.element(expired)).colorScheme.error,
    );
    expect(find.text('Not checked'), findsNWidgets(3));
    // One USCF refresh fetches ratings and membership expiry together.
    expect(find.byKey(const ValueKey('refresh-uscf')), findsOneWidget);
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
        final warning = find.text('$expiration  Expires this month');
        expect(warning, findsOneWidget);
        expect(find.textContaining('Expired'), findsNothing);
        expect(
          tester.widget<Text>(warning).textSpan!.style!.color,
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
          final dateRect = tester.getRect(warning);
          final normalRect = tester.getRect(find.text('2099-12-31'));
          final noteRect = tester.getRect(find.text('Arriving late'));
          expect(dateRect.left, normalRect.left);
          expect(
            dateRect.left,
            tester.getTopLeft(find.text('USCF expires')).dx,
          );
          expect(dateRect.height, normalRect.height);
          expect(dateRect.right, lessThanOrEqualTo(noteRect.left - 12));
          expect(tester.takeException(), isNull);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
