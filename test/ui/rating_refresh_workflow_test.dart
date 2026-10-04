import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/infrastructure/roster_import.dart';
import 'package:meow_chess/ui/workspace.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final refresh in [true, false]) {
    testWidgets(
      'website confirmation starts optional inline rating review: $refresh',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = fixture(count: 4);
        addTearDown(c.dispose);
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: meowTheme(Brightness.light),
            home: Workspace(
              controller: c,
              path: ':memory:',
              onClose: () {},
              onTheme: () {},
              rosterLoader: (_) async => parseRoster(
                'Name,Rating,USCF ID\nNew Player,UNR,99887766\nNo ID Player,UNR,',
              ),
              ratingLookup: (id) async {
                calls++;
                return MemberObservation(
                  id: id,
                  name: 'Official Name',
                  retrievedAt: '2026-10-03',
                  supplementDate: '2026-10-01',
                  ratings: {'R': 2100},
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('player-tools')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('update-event')));
        await tester.pumpAndSettle();
        final option = find.byKey(const ValueKey('import-refresh-ratings'));
        expect(tester.widget<CheckboxListTile>(option).value, true);
        if (!refresh) {
          await tester.tap(option);
          await tester.pump();
        }
        await tester.enterText(
          find.byKey(const ValueKey('roster-url')),
          'https://boylstonchess.org/events/1563/october-quads',
        );
        await tester.tap(find.text('Fetch updates'));
        await tester.pumpAndSettle();
        expect(c.event!.players, hasLength(4));
        final confirm = find.text('Confirm 2 changes & save source');
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 600));
        }
        await tester.pumpAndSettle();
        expect(c.event!.players, hasLength(6));
        expect(find.byKey(const ValueKey('roster-url')), findsNothing);
        if (!refresh) {
          expect(calls, 0);
          expect(find.byKey(const ValueKey('rating-review')), findsNothing);
        } else {
          expect(calls, 5);
          expect(
            find.text(
              'Found ratings for 5 players. 1 missing — see player rows.',
            ),
            findsOneWidget,
          );
          expect(c.event!.players.first.rating, 2000);
          await tester.drag(find.byType(ListView).first, const Offset(0, -650));
          await tester.pumpAndSettle();
          expect(find.text('UNR → 2100'), findsOneWidget);
          await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
          await tester.pumpAndSettle();
          final proposal = tester.widget<Container>(
            find.byKey(const ValueKey('rating-proposal-p0')),
          );
          expect(proposal.color, isNotNull);
          // Player editing occupies the right side while the review stays left.
          final row = find.byKey(const ValueKey('player-p0'));
          await tester.tap(row);
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tap(row);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('panel-name')), findsOneWidget);
          expect(find.byKey(const ValueKey('rating-review')), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('panel-rating')),
            '1700',
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Save'));
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(c.event!.player('p0').rating, 1700);
          expect(
            find.text(
              'Edited since lookup. Refresh again to review this player.',
            ),
            findsOneWidget,
          );
          final apply = find.text('Confirm 4 rating changes');
          await tester.ensureVisible(apply);
          await tester.tap(apply);
          await tester.pumpAndSettle();
          expect(c.event!.player('p0').rating, 1700);
          expect(c.event!.player('p1').rating, 2100);
          expect(c.event!.players.last.rating, 0);
          expect(find.byKey(const ValueKey('rating-review')), findsNothing);
          expect(find.text('Proposed USCF rating'), findsNothing);
          expect(find.byType(SnackBar), findsNothing);
          await tester.pump(const Duration(seconds: 20));
          expect(find.text('Updated 4 USCF ratings.'), findsOneWidget);
          await tester.tap(find.text('Undo'));
          await tester.pumpAndSettle();
          expect(c.event!.player('p0').rating, 1700);
          expect(c.event!.player('p1').rating, 1950);
          expect(find.text('Updated 4 USCF ratings.'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
