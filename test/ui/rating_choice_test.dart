import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../support.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('after a review each player switches between the entered and '
      'the US Chess rating in the table', (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Workspace(
          controller: c,
          path: ':memory:',
          onClose: () {},
          onTheme: () {},
          ratingLookup: (id) async => MemberObservation(
            id: id,
            name: 'Player',
            retrievedAt: '2026-10-03',
            supplementDate: '2026-10-01',
            ratings: {'R': 2100},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    bool? ticked(String key) =>
        tester.widget<PlainCheckbox>(find.byKey(ValueKey(key))).value;
    List<int> ratings() => [for (final p in c.event!.players) p.rating];

    // With only entered ratings there is nothing to choose between.
    expect(find.text('Rating'), findsOneWidget);
    expect(find.byKey(const ValueKey('use-supplement-all')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('refresh-uscf')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }
    await tester.pumpAndSettle();
    // The review keeps its own tick boxes.
    expect(find.byKey(const ValueKey('use-supplement-all')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('approve-rating-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm 3 rating changes'));
    await tester.pumpAndSettle();
    expect(ratings(), [2100, 1950, 2100, 2100]);

    // Both ratings stay in the table: the entered one, and the US Chess
    // one ticked where it is in use.
    expect(find.text('Entered'), findsOneWidget);
    expect(find.text('US Chess 2026-10-01'), findsOneWidget);
    expect(find.text('Rating'), findsNothing);
    expect(ticked('use-supplement-p0'), true);
    expect(ticked('use-supplement-p1'), false);
    expect(ticked('use-supplement-all'), isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('player-p0')),
        matching: find.text('2000'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('2100  +100', findRichText: true),
      findsOneWidget,
    );
    final height = tester
        .getSize(find.byKey(const ValueKey('player-column-header')))
        .height;

    // One click puts a player back on the entered rating, and another on
    // the supplement the review left unticked.
    await tester.tap(find.byKey(const ValueKey('use-supplement-p0')));
    await tester.pumpAndSettle();
    expect(ratings(), [2000, 1950, 2100, 2100]);
    expect(ticked('use-supplement-p0'), false);
    await tester.tap(find.byKey(const ValueKey('use-supplement-p1')));
    await tester.pumpAndSettle();
    expect(ratings(), [2000, 2100, 2100, 2100]);
    expect(find.byKey(const ValueKey('undo-notice')), findsNothing);

    // The heading's box switches everyone listed, with Undo.
    await tester.tap(find.byKey(const ValueKey('use-supplement-all')));
    await tester.pumpAndSettle();
    expect(ratings(), [2100, 2100, 2100, 2100]);
    expect(ticked('use-supplement-all'), true);
    expect(find.text('Using US Chess ratings for 1 player.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('use-supplement-all')));
    await tester.pumpAndSettle();
    expect(ratings(), [2000, 1950, 1900, 1850]);
    expect(ticked('use-supplement-all'), false);
    expect(find.text('Using entered ratings for 4 players.'), findsOneWidget);
    // The column stays, so nothing moves as ratings are switched.
    expect(find.text('US Chess 2026-10-01'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('player-column-header'))).height,
      height,
    );
    c.undo();
    await tester.pumpAndSettle();
    expect(ratings(), [2100, 2100, 2100, 2100]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a paired section shows no rating choice', (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    for (final p in c.event!.players) {
      c.recordMembership(c.event!.id, p.id, {
        'id': p.memberId,
        'name': p.name,
        'retrievedAt': '2026-10-03T12:00:00Z',
        'supplementDate': '2026-10-01',
        'ratings': {'R': 2100},
      });
    }
    c.post((await tester.runAsync(() => c.propose()))!);
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
    expect(find.byKey(const ValueKey('use-supplement-all')), findsNothing);
    expect(find.byKey(const ValueKey('use-supplement-p0')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
