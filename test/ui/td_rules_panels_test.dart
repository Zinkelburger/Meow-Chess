import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/event_panel.dart';
import 'package:meow_chess/ui/player_panel.dart';
import 'package:meow_chess/ui/rulings_panel.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';

Future<void> mount(WidgetTester tester, Widget panel) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: Align(alignment: Alignment.topRight, child: panel),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('Rulings panel logs an entry that undo removes', (tester) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    await mount(tester, RulingsPanel(controller: c, onClose: () {}));
    expect(find.textContaining('one-half hour'), findsOneWidget);
    expect(find.textContaining('ten days'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('ruling-text')),
      'Touch-move enforced on board 2.',
    );
    await tester.enterText(find.byKey(const ValueKey('ruling-round')), '1');
    await tester.tap(find.byKey(const ValueKey('log-ruling')));
    await tester.pump();
    expect(c.event!.rulings.single['text'], 'Touch-move enforced on board 2.');
    expect(c.event!.rulings.single['round'], 1);
    expect(find.text('Touch-move enforced on board 2.'), findsOneWidget);
    c.undo();
    await tester.pump();
    expect(find.text('Nothing logged yet.'), findsOneWidget);
  });

  testWidgets('Event panel marks an online event and hints at 5E2', (
    tester,
  ) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    c.change('G/60', c.event!.copy(timeControl: 'G/60'));
    await mount(tester, EventPanel(controller: c, onClose: () {}));
    expect(find.byKey(const ValueKey('event-time-hint')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('event-time')), 'G/60 d5');
    await tester.pump();
    expect(find.byKey(const ValueKey('event-time-hint')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('event-online')));
    await tester.tap(find.byKey(const ValueKey('event-online')));
    await tester.pump();
    expect(c.event!.online, isTrue);
  });

  testWidgets('Player panel declares an irrevocable bye and assigns ratings', (
    tester,
  ) async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    c.change(
      'Policy',
      c.event!.copy(
        sections: [
          for (final s in c.event!.sections)
            s.copy(
              plannedRounds: 3,
              byeRules: const {'irrevocableFromRound': 3},
            ),
        ],
      ),
    );
    await mount(
      tester,
      PlayerPanel(controller: c, player: c.event!.player('p0'), onClose: () {}),
    );
    await openPanelGroup(tester, 'byes');
    expect(find.byKey(const ValueKey('bye-policy')), findsOneWidget);
    await toggleBye(tester, 3, 1);
    // Refused until declared irrevocable; the panel says why.
    expect(find.textContaining('rule 22C4'), findsOneWidget);
    await toggleBye(tester, 2, 1);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: PlayerPanel(
            controller: c,
            player: c.event!.player('p0'),
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await openPanelGroup(tester, 'byes');
    await tester.ensureVisible(find.byKey(const ValueKey('irrevocable-2')));
    await tester.tap(find.byKey(const ValueKey('irrevocable-2')));
    await tester.pump();
    expect(c.event!.player('p0').irrevocableByes, {2});

    await openPanelGroup(tester, 'assigned');
    await tester.enterText(
      find.byKey(const ValueKey('panel-foreignRating')),
      '2400',
    );
    await tester.pump();
    await chooseOption(
      tester,
      find.byKey(const ValueKey('panel-foreignFederation')),
      'FIDE',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('foreign-conversion')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('use-converted-rating')),
    );
    await tester.tap(find.byKey(const ValueKey('use-converted-rating')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('panel-pairingRating')))
          .controller!
          .text,
      '2468',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(c.event!.player('p0').pairingRating, 2468);
    expect(c.event!.player('p0').foreignFederation, 'FIDE');
  });
}
