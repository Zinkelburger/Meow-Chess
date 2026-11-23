import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/check_panel.dart';
import 'package:meow_chess/ui/theme.dart';

import '../support.dart';

Future<void> mount(WidgetTester tester, Widget panel) async {
  tester.view.physicalSize = const Size(1200, 1600);
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

Game game(int round, int board, int white, int black) => Game(
  id: 'r$round-b$board',
  white: 'p$white',
  black: 'p$black',
  board: board,
  outcome: Outcome.whiteWin,
);

void main() {
  testWidgets('Check event lists findings, checks and pairing quality', (
    tester,
  ) async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    final s = c.event!.sections.single;
    c.change(
      'Rounds',
      c.event!.copy(
        sections: [
          s.copy(
            plannedRounds: 4,
            rounds: [
              Round(number: 1, games: [game(1, 1, 0, 1), game(1, 2, 2, 3)]),
              Round(number: 2, games: [game(2, 1, 1, 0), game(2, 2, 3, 2)]),
            ],
          ),
        ],
      ),
    );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await mount(tester, CheckPanel(controller: c, onClose: () {}));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('check-summary'))).data,
      '2 to look at',
    );
    expect(find.textContaining('meet again on board 1 in round 2'), findsOne);
    expect(find.text('Players paired against each other twice'), findsOne);
    expect(find.text('2 found: 4 pairings checked'), findsOne);
    expect(
      find.text('Not checked: no section limits half-point byes'),
      findsOne,
    );
    expect(find.text('Pairing quality · ${s.name}'), findsOne);
    expect(find.text('Round 2 · 2 boards'), findsOne);
    // One section: there is no scope to choose.
    expect(find.byKey(const ValueKey('check-scope')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('copy-check')));
    await tester.pump();
    expect(find.text('Copied'), findsOne);
    expect(copied, contains('Check of Saturday Quads'));
    expect(copied, contains('Look: '));
    expect(copied, contains('Pairing quality: ${s.name}'));
    expect(copied, contains('Repeat pairings: 2 of 2'));

    // The panel follows the event: Undo removes the rounds and the findings.
    c.undo(acceptLosses: true);
    await tester.pump();
    expect(find.text('Nothing found.'), findsOne);
    expect(find.text('Copy report'), findsOne);
    expect(find.textContaining('Pairing quality'), findsNothing);
  });

  testWidgets('with several sections the check can be narrowed to one', (
    tester,
  ) async {
    final c = fixture(count: 8, format: Format.swiss);
    addTearDown(c.dispose);
    final second = c.event!.sections[1];
    await mount(
      tester,
      CheckPanel(controller: c, sectionId: second.id, onClose: () {}),
    );
    expect(find.byKey(const ValueKey('check-scope')), findsOne);
    // A single section leaves out the event-wide checks.
    expect(find.text('Players in no section'), findsNothing);
    expect(find.text('Do-not-pair requests'), findsOne);
  });
}
