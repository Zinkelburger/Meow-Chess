import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/ui/event_panel.dart';
import 'package:meow_chess/ui/player_panel.dart';
import '../support.dart';

const candidate = MemberObservation(
  id: '00123456',
  name: 'Test Member',
  state: 'MA',
  retrievedAt: '2026-10-03',
  ratings: {'R': 1500},
);

void main() {
  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'chief and assistant TD names resolve to IDs and save with event',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final key = GlobalKey<EventPanelState>();
      await show(
        tester,
        EventPanel(
          key: key,
          controller: c,
          onClose: () {},
          memberSearch: (name) async {
            expect(name, 'Test Member');
            return [candidate];
          },
        ),
      );
      for (final field in ['td', 'atd']) {
        await tester.enterText(
          find.byKey(ValueKey('event-$field')),
          'Test Member',
        );
        final scope = find.byKey(ValueKey('event-identity-$field'));
        await tester.tap(
          find.descendant(of: scope, matching: find.text('Find by name')),
        );
        await tester.pumpAndSettle();
        expect(c.event!.tdId, field == 'td' ? '' : candidate.id);
        await tester.tap(
          find.descendant(of: scope, matching: find.text('Use 00123456')),
        );
        await tester.pumpAndSettle();
        expect(key.currentState!.text[field]!.text, candidate.id);
        expect(key.currentState!.commit(), isTrue);
        await tester.pumpAndSettle();
      }
      final saved = c.repository.load()!;
      expect(saved.tdId, candidate.id);
      expect(saved.assistantTdId, candidate.id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'player correction persists only after Save and keeps pairing rating',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.savePlayer(c.event!.player('p0').copy(name: candidate.name));
      final key = GlobalKey<PlayerPanelState>();
      final original = c.event!.player('p0');
      await show(
        tester,
        PlayerPanel(
          key: key,
          controller: c,
          player: original,
          onClose: () {},
          identityLookup: (_) async => throw const MemberNotFound(),
          memberSearch: (_) async => [candidate],
        ),
      );
      await tester.tap(find.text('Check ID'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use 00123456'));
      await tester.pumpAndSettle();
      expect(c.event!.player('p0').memberId, original.memberId);
      expect(key.currentState!.commit(), isTrue);
      final saved = c.repository.load()!.player('p0');
      expect(saved.memberId, candidate.id);
      expect(saved.name, original.name);
      expect(saved.rating, original.rating);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('add player supports name search without an ID', (tester) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final key = GlobalKey<PlayerPanelState>();
    await show(
      tester,
      PlayerPanel(
        key: key,
        controller: c,
        onClose: () {},
        memberSearch: (_) async => [candidate],
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('panel-name')),
      candidate.name,
    );
    await tester.enterText(find.byKey(const ValueKey('panel-rating')), 'UNR');
    await tester.tap(find.text('Find by name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use 00123456'));
    await tester.pumpAndSettle();
    expect(c.event!.players.length, 4);
    expect(key.currentState!.commit(), isTrue);
    await tester.pumpAndSettle();
    expect(c.event!.players.last.memberId, candidate.id);
    expect(c.event!.players.last.rating, 0);
    expect(tester.takeException(), isNull);
  });
}
