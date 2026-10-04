import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/roster_import.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/ui/update_panels.dart';
import 'package:meow_chess/ui/help_panel.dart';
import '../support.dart';

void main() {
  testWidgets(
    'website import waits for confirmation and saves a reusable source',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebRosterPanel(
              controller: c,
              onClose: () {},
              loader: (_) async => parseRoster(
                'Name,USCF ID,Rating,Note\nNew Player,99887766,1200,Arriving late',
              ),
            ),
          ),
        ),
      );
      final urlField = tester.widget<TextField>(
        find.byKey(const ValueKey('roster-url')),
      );
      expect(urlField.controller!.text, isEmpty);
      expect(urlField.decoration!.hintText, isNull);
      expect(rosterRefreshLabel(c.event!), 'Refresh from URL');
      await tester.enterText(
        find.byKey(const ValueKey('roster-url')),
        'https://example.org/entries',
      );
      await tester.tap(find.text('Fetch updates'));
      await tester.pumpAndSettle();
      expect(c.event!.players.length, 4);
      expect(
        find.textContaining('Website note: Arriving late'),
        findsOneWidget,
      );
      final confirm = find.text('Confirm 1 changes & save source');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(c.event!.players.length, 5);
      expect(c.event!.players.last.registrationNote, 'Arriving late');
      expect(c.event!.rosterSource['url'], 'https://example.org/entries');
      expect(
        rosterRefreshLabel(c.event!),
        'Refresh from https://example.org/entries',
      );
      expect(
        c.event!.players.last.ratingEvidence['kind'],
        'self-reported registration',
      );
    },
  );
  testWidgets(
    'equal rating can be verified, bulk refresh requires explicit approval',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RatingsRefreshPanel(
              controller: c,
              onClose: () {},
              lookup: (id) async => MemberObservation(
                id: id,
                name: 'Official Name',
                retrievedAt: '2026-10-03',
                supplementDate: '2026-10-01',
                ratings: {'R': 2000},
                expiration: '2027-12-31',
                status: 'Active',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Fetch monthly supplements'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 600));
      }
      await tester.pumpAndSettle();
      expect(c.event!.players.first.ratingEvidence, isEmpty);
      expect(
        c.event!.players.first.membershipEvidence['expiration'],
        '2027-12-31',
      );
      final checkbox = find.byType(CheckboxListTile).first;
      expect(tester.widget<CheckboxListTile>(checkbox).onChanged, isNotNull);
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pump();
      final confirm = find.text('Confirm 1 rating changes');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(
        c.event!.players.first.ratingEvidence['supplementDate'],
        '2026-10-01',
      );
      expect(c.event!.players[1].rating, 1950);
    },
  );
  testWidgets('offline help searches article text and opens quad explanation', (
    tester,
  ) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HelpPanel(controller: c, onClose: () {}),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('help-search')),
      'extra black',
    );
    await tester.pumpAndSettle();
    expect(find.text('How quads are paired'), findsOneWidget);
    await tester.tap(find.text('How quads are paired'));
    await tester.pumpAndSettle();
    expect(find.text('Why did I get an extra Black?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
