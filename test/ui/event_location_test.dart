import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';
import 'package:meow_chess/ui/event_panel.dart';
import '../support.dart';

void main() {
  testWidgets(
    'Event details hold the venue and the city, state and ZIP the report needs',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final key = GlobalKey<EventPanelState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventPanel(
              key: key,
              controller: c,
              onClose: () {},
              memberSearch: (_) async => const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The venue is the hall; the city is asked for by name, once.
      expect(find.text('Venue'), findsOneWidget);
      expect(find.text('Venue or city'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('event-venue')),
        'Boylston Chess Club',
      );
      await tester.enterText(
        find.byKey(const ValueKey('event-city')),
        ' Cambridge ',
      );
      await tester.enterText(find.byKey(const ValueKey('event-state')), 'ma');
      await tester.enterText(find.byKey(const ValueKey('event-zip')), '02139');
      expect(key.currentState!.commit(), isTrue);
      final e = c.event!;
      expect(e.venue, 'Boylston Chess Club');
      expect((e.city, e.state, e.zip), ('Cambridge', 'MA', '02139'));
      // The rating report no longer asks for the site.
      final issues = ratingPreflight(e).join('\n');
      expect(issues, isNot(contains('City')));
      expect(issues, isNot(contains('ZIP')));
      expect(issues, isNot(contains('two-letter state')));
      // One undoable step.
      c.undo();
      expect(c.event!.city, isEmpty);
    },
  );
}
