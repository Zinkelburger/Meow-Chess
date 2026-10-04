import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/ui/event_panel.dart';
import 'package:meow_chess/ui/players_view.dart';
import '../support.dart';

void main() {
  for (final rebuild in [false, true]) {
    testWidgets(
      'saving notes preserves concurrent rating and state; rebuild=$rebuild',
      (tester) async {
        final c = fixture(count: 4);
        addTearDown(c.dispose);
        final key = GlobalKey<PlayerPanelState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: c,
                builder: (_, _) => PlayerPanel(
                  key: key,
                  controller: c,
                  player: c.event!.player('p0'),
                  onClose: () {},
                ),
              ),
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const ValueKey('panel-notes')),
          'Only notes were edited',
        );
        c.savePlayer(
          c.event!
              .player('p0')
              .copy(
                rating: 2200,
                state: 'MA',
                ratingEvidence: {
                  'kind': 'monthly supplement',
                  'supplementDate': '2026-10-01',
                },
              ),
        );
        if (rebuild) await tester.pump();
        expect(key.currentState!.commit(), true);
        final saved = c.repository.load()!.player('p0');
        expect(saved.notes, 'Only notes were edited');
        expect(saved.rating, 2200);
        expect(saved.state, 'MA');
        expect(saved.ratingEvidence['kind'], 'monthly supplement');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'concurrent changes to the same field require reviewing the saved value',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final key = GlobalKey<PlayerPanelState>();
      Future<void> mount() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => PlayerPanel(
                key: key,
                controller: c,
                player: c.event!.player('p0'),
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await mount();
      await tester.enterText(
        find.byKey(const ValueKey('panel-rating')),
        '2100',
      );
      c.savePlayer(c.event!.player('p0').copy(rating: 2200));
      await tester.pump();
      expect(key.currentState!.commit(), false);
      expect(key.currentState!.error, contains('Rating changed elsewhere'));
      expect(c.event!.player('p0').rating, 2200);
      // Closing and restoring the persisted draft must not erase the conflict.
      await tester.pumpWidget(const SizedBox());
      await mount();
      expect(key.currentState!.commit(), false);
      expect(c.event!.player('p0').rating, 2200);
      key.currentState!.discardDraft();
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('panel-notes')),
        'Reviewed',
      );
      expect(key.currentState!.commit(), true);
      expect(c.event!.player('p0').rating, 2200);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'event notes preserve concurrent metadata and detect same-field conflicts',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final key = GlobalKey<EventPanelState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) =>
                  EventPanel(key: key, controller: c, onClose: () {}),
            ),
          ),
        ),
      );
      key.currentState!.text['notes']!.text = 'Local notes';
      c.change('External venue change', c.event!.copy(venue: 'New venue'));
      await tester.pump();
      expect(key.currentState!.commit(), true);
      expect(c.event!.venue, 'New venue');
      expect(c.event!.notes, 'Local notes');
      key.currentState!.text['name']!.text = 'Local name';
      c.change('External name change', c.event!.copy(name: 'Saved name'));
      expect(key.currentState!.commit(), false);
      expect(c.event!.name, 'Saved name');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
