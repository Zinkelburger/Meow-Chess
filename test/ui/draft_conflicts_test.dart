import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/ui/event_panel.dart';
import 'package:meow_chess/ui/panels.dart';
import 'package:meow_chess/ui/reports_view.dart';
import 'package:meow_chess/ui/player_panel.dart';
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
        await openPanelGroup(tester, 'notes');
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
      await openPanelGroup(tester, 'notes');
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
  for (final rebuild in [false, true]) {
    testWidgets('report city edit preserves undone ZIP; rebuild=$rebuild', (
      tester,
    ) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.change('Set ZIP', c.event!.copy(zip: '02116'));
      final key = GlobalKey<ReportDetailsState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => ReportDetails(key: key, controller: c),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('report-city')),
        'Boston',
      );
      c.undo();
      if (rebuild) await tester.pump();
      expect(key.currentState!.commit(), true);
      expect(c.repository.load()!.city, 'Boston');
      expect(c.repository.load()!.zip, '');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('section rename preserves undone first board; rebuild=$rebuild', (
      tester,
    ) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final initial = c.event!.sections.single;
      c.change(
        'Set first board',
        c.event!.copy(sections: [initial.copy(boardStart: 20)]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => sectionSettingsPanel(c, initial.id, () {}),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('field-name')),
        'Renamed section',
      );
      c.undo();
      if (rebuild) await tester.pump();
      // Invoke before the next rebuild too: save must read current state itself.
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed!();
      await tester.pump();
      final saved = c.repository.load()!.sections.single;
      expect(saved.name, 'Renamed section');
      expect(saved.boardStart, initial.boardStart);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'section conflict survives reopening until explicitly discarded',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final sectionId = c.event!.sections.single.id;
      Future<void> mount() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: sectionSettingsPanel(c, sectionId, () {})),
        ),
      );
      Future<void> save() async {
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed!();
        await tester.pump();
      }

      await mount();
      await tester.enterText(
        find.byKey(const ValueKey('field-name')),
        'Local name',
      );
      c.change(
        'Rename elsewhere',
        c.event!.copy(
          sections: [c.event!.sections.single.copy(name: 'Saved name')],
        ),
      );
      await save();
      expect(find.textContaining('Name changed elsewhere'), findsOneWidget);
      expect(c.event!.sections.single.name, 'Saved name');
      await tester.pumpWidget(const SizedBox());
      await mount();
      await save();
      expect(find.textContaining('Name changed elsewhere'), findsOneWidget);
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Discard draft'))
          .onPressed!();
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('field-name')))
            .controller!
            .text,
        'Saved name',
      );
      await tester.enterText(
        find.byKey(const ValueKey('field-name')),
        'Reviewed name',
      );
      await save();
      expect(c.event!.sections.single.name, 'Reviewed name');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('report same-field conflict blocks save and event-type changes', (
    tester,
  ) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final key = GlobalKey<ReportDetailsState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => ReportDetails(key: key, controller: c),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('report-city')),
      'Local city',
    );
    c.change('Change city elsewhere', c.event!.copy(city: 'Saved city'));
    await tester.pump();
    expect(key.currentState!.commit(), false);
    expect(key.currentState!.error, contains('City changed elsewhere'));
    final oldLevel = c.event!.level;
    key.currentState!.setLevel('A');
    expect(c.event!.level, oldLevel);
    expect(c.event!.city, 'Saved city');
    await tester.pump();
    await tester.tap(find.text('Discard draft'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('report-city')))
          .controller!
          .text,
      'Saved city',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'submission conflict cannot overwrite newer notes and discard loads current notes',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => SubmissionNotes(controller: c),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('submission-notes')),
        'Local submission',
      );
      c.change(
        'Change submission elsewhere',
        c.event!.copy(submission: 'Uploaded, reference 123'),
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(
        find.textContaining('Submission notes changed elsewhere'),
        findsOneWidget,
      );
      expect(c.event!.submission, 'Uploaded, reference 123');
      await tester.tap(find.text('Discard draft'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('submission-notes')))
            .controller!
            .text,
        'Uploaded, reference 123',
      );
      expect(
        find.textContaining('Submission notes changed elsewhere'),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('submission-notes')),
        'Reviewed submission',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(c.event!.submission, 'Reviewed submission');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
