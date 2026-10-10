import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/fide.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/event_panel.dart';
import 'package:meow_chess/ui/player_panel.dart';
import 'package:meow_chess/ui/theme.dart';

import '../support.dart';
import 'section_panel_test.dart'
    show mountWorkspace, openGroup, openSettings, summaryOf;

void main() {
  testWidgets('a section becomes dual rated from its settings', (tester) async {
    final c = fixture(count: 8, format: Format.swiss);
    addTearDown(c.dispose);
    final s = c.event!.sections.first;
    await mountWorkspace(tester, c);
    await openSettings(tester, s.id);
    // US Chess only: no FIDE note, US Chess pairing rules.
    expect(find.byKey(const ValueKey('field-fide-note')), findsNothing);
    await chooseOption(
      tester,
      find.byKey(const ValueKey('field-ratedBy')),
      'US Chess and FIDE',
    );
    expect(
      find.textContaining('FIDE standard · FIDE Dutch pairings'),
      findsOneWidget,
      reason: 'G/65 d10 is 75 minutes: standard',
    );
    expect(find.byKey(const ValueKey('field-fide-note')), findsOneWidget);
    expect(summaryOf(tester, 'pairing'), 'FIDE Dutch');
    await openGroup(tester, 'pairing');
    // FIDE's own options replace US Chess acceleration (28R): the Baku
    // method and the pairing-allocated bye's value.
    expect(find.byKey(const ValueKey('field-accelerated')), findsOneWidget);
    expect(find.text('Added score, rounds 1–2'), findsNothing);
    expect(find.byKey(const ValueKey('field-pabPoints')), findsOneWidget);
    expect(find.byKey(const ValueKey('field-fideRanking')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('save-section')));
    await tester.tap(find.byKey(const ValueKey('save-section')));
    await tester.pumpAndSettle();
    final saved = c.event!.sections.first;
    expect(saved.fideRated, isTrue);
    expect(saved.unrated, isFalse);
    expect(RatedBy.of(saved), RatedBy.dual);

    // Reports gains the FIDE region, blocked until FIDE details exist.
    await tester.tap(find.text('Export').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fide-report')), findsOneWidget);
    expect(find.byKey(const ValueKey('fide-blocked')), findsOneWidget);
    expect(find.textContaining('FIDE ID missing'), findsOneWidget);
    expect(find.textContaining('chief arbiter'), findsWidgets);
  });

  testWidgets('the player panel asks for a FIDE ID in a FIDE section', (
    tester,
  ) async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    final s = c.event!.sections.single;
    c.change('FIDE', c.event!.copy(sections: [s.copy(fideRated: true)]));
    final key = GlobalKey<State>();
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
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
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-fide')), findsOneWidget);
    expect(
      find.text('FIDE ID needed'),
      findsNothing,
      reason: 'the group opens itself, so the summary is hidden',
    );
    await tester.enterText(
      find.byKey(const ValueKey('panel-fideId')),
      '2016192',
    );
    await tester.enterText(
      find.byKey(const ValueKey('panel-fideStandard')),
      '2780',
    );
    await tester.enterText(
      find.byKey(const ValueKey('panel-federation')),
      'usa',
    );
    await chooseOption(tester, find.byKey(const ValueKey('panel-title')), 'GM');
    await tester.pumpAndSettle();
    expect((key.currentState as dynamic).commit(), isTrue);
    final p = c.event!.player('p0');
    expect(p.fideId, '2016192');
    expect(p.fideStandard, 2780);
    expect(p.federation, 'USA');
    expect(p.title, 'GM');

    await tester.enterText(
      find.byKey(const ValueKey('panel-birthDate')),
      '1987-13-40',
    );
    await tester.pump();
    expect((key.currentState as dynamic).commit(), isFalse);
    await tester.pump();
    expect(find.textContaining('YYYY or YYYY-MM-DD'), findsOneWidget);
  });

  testWidgets('tie-breaks stay folded and edit as an ordered list', (
    tester,
  ) async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    c.change(
      'FIDE',
      c.event!.copy(sections: [c.event!.sections.single.copy(fideRated: true)]),
    );
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => EventPanel(controller: c, onClose: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Closed: one line of summary, no editors.
    expect(find.byKey(const ValueKey('event-fide-tiebreaks')), findsNothing);
    final header = find.byKey(const ValueKey('event-group-tiebreaks'));
    expect(tester.getSemantics(header).value, 'FIDE: Suggested order');
    await tester.ensureVisible(header);
    await tester.tap(header);
    await tester.pumpAndSettle();
    // Only FIDE sections: no US Chess switch.
    expect(find.byKey(const ValueKey('event-use-tiebreaks')), findsNothing);
    expect(
      find.textContaining('Buchholz Cut-1', findRichText: true),
      findsOneWidget,
    );
    // Move Buchholz (2nd) up, remove the last, add Buchholz Cut-2.
    await tester.tap(find.byKey(const ValueKey('event-fide-tiebreak-1-up')));
    await tester.pumpAndSettle();
    expect(c.event!.fideTiebreaks.take(2), ['BH', 'BH/C1']);
    await tester.tap(
      find.byKey(const ValueKey('event-fide-tiebreak-4-remove')),
    );
    await tester.pumpAndSettle();
    expect(c.event!.fideTiebreaks, ['BH', 'BH/C1', 'SB', 'DE']);
    // The add menu lists each method once; adding Buchholz again takes
    // its first variant not yet listed, and the row picks another.
    await chooseOption(
      tester,
      find.byKey(const ValueKey('event-fide-tiebreak-add')),
      'Buchholz · BH',
    );
    expect(c.event!.fideTiebreaks.last, 'BH/C2');
    await chooseOption(
      tester,
      find.byKey(const ValueKey('event-fide-tiebreak-4-variant')),
      'Buchholz Cut-2, forfeits as played · BH-C2-P',
    );
    expect(c.event!.fideTiebreaks.last, 'BH/C2/P');
    await tester.ensureVisible(
      find.byKey(const ValueKey('event-fide-tiebreak-default')),
    );
    await tester.tap(find.byKey(const ValueKey('event-fide-tiebreak-default')));
    await tester.pumpAndSettle();
    expect(c.event!.fideTiebreaks, isEmpty);
  });

  testWidgets('a FIDE Swiss sets Baku and the bye value before round 1', (
    tester,
  ) async {
    final c = fixture(count: 8, format: Format.swiss);
    addTearDown(c.dispose);
    final s = c.event!.sections.first;
    c.change('FIDE', c.event!.copy(sections: [s.copy(fideRated: true)]));
    await mountWorkspace(tester, c);
    await openSettings(tester, s.id);
    await openGroup(tester, 'pairing');
    await chooseOption(
      tester,
      find.byKey(const ValueKey('field-accelerated')),
      'Baku acceleration',
    );
    await chooseOption(
      tester,
      find.byKey(const ValueKey('field-pabPoints')),
      'A draw',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('save-section')));
    await tester.tap(find.byKey(const ValueKey('save-section')));
    await tester.pumpAndSettle();
    final saved = c.event!.sections.first;
    expect(saved.accelerated, 'baku');
    expect(saved.pabPoints, 1);
  });

  testWidgets('a full-point bye in a FIDE section says FIDE deprecates it', (
    tester,
  ) async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    c.change(
      'FIDE',
      c.event!.copy(sections: [c.event!.sections.single.copy(fideRated: true)]),
    );
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => PlayerPanel(
              controller: c,
              player: c.event!.player('p0'),
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openPanelGroup(tester, 'byes');
    expect(find.byKey(const ValueKey('fide-full-bye-warning')), findsNothing);
    await toggleBye(tester, 2, 2);
    expect(c.event!.player('p0').byes, {2: 2});
    expect(find.byKey(const ValueKey('fide-full-bye-warning')), findsOneWidget);
  });

  testWidgets('a FIDE-only event shows FIDE columns, not US Chess ones', (
    tester,
  ) async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    final e = c.event!;
    c.change(
      'FIDE only',
      e.copy(
        players: [
          for (final p in e.players)
            p.copy(fideId: '1${p.memberId}', fideStandard: 1800),
        ],
        sections: [e.sections.single.copy(fideRated: true, unrated: true)],
      ),
    );
    await mountWorkspace(tester, c);
    expect(find.text('FIDE ID'), findsOneWidget);
    expect(find.text('USCF expires'), findsNothing);
    expect(find.text('USCF ID'), findsNothing);
    expect(find.byKey(const ValueKey('refresh-fide')), findsOneWidget);
    expect(find.byKey(const ValueKey('refresh-uscf')), findsNothing);
  });
}
