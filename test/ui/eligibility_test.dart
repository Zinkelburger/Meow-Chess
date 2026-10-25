import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/eligibility.dart';
import 'package:meow_chess/domain/history.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/player_panel.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/section_panel.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace_pages.dart';

import '../support.dart';

Section championship({Map<String, String> exceptions = const {}}) => Section(
  id: 'champ',
  name: 'Championship',
  players: const [],
  ratingFloor: 800,
  ratingCeiling: 2000,
  rangeExceptions: exceptions,
);

Player kid(int rating, {String id = 'k', bool house = false}) =>
    Player(id: id, name: 'Kid', rating: rating, house: house);

void main() {
  test('the range reads as the announcement does', () {
    String range({int floor = 0, int cap = 0}) => ratingRangeText(
      Section(
        id: '',
        name: '',
        players: const [],
        ratingFloor: floor,
        ratingCeiling: cap,
      ),
    );
    expect(range(floor: 800, cap: 2000), '800–1999');
    expect(range(cap: 1000), 'under 1000');
    expect(range(floor: 800), '800 and over');
    expect(range(), isEmpty);
  });

  test('rule 28H / K03: floor, ceiling, unrated, exceptions', () {
    final s = championship();
    expect(ratingRangeProblem(kid(800), s), isNull);
    expect(ratingRangeProblem(kid(1999), s), isNull);
    expect(
      ratingRangeProblem(kid(2000), s),
      'Rated 2000: Championship is for players rated 800–1999.',
    );
    expect(
      ratingRangeProblem(kid(0), s),
      'Unrated: Championship is for players rated 800–1999.',
    );
    expect(ratingRangeProblem(kid(750), s), startsWith('Rated 750'));
    // An unrated player is under any ceiling.
    final u500 = Section(
      id: 'u',
      name: 'Under 500',
      players: const [],
      ratingCeiling: 500,
    );
    expect(ratingRangeProblem(kid(0), u500), isNull);
    // A TD-assigned pairing rating counts.
    expect(
      ratingRangeProblem(
        Player(id: 'k', name: 'Kid', pairingRating: 900),
        championship(),
      ),
      isNull,
    );
    expect(ratingRangeProblem(kid(0, house: true), s), isNull);
    expect(
      ratingRangeProblem(kid(0), championship(exceptions: {'k': 'Approved'})),
      isNull,
    );
  });

  test('range and exceptions survive a save', () {
    final s = championship(exceptions: {'k': 'Organizer approved'});
    final back = Section.fromJson(s.toJson());
    expect(back.ratingFloor, 800);
    expect(back.ratingCeiling, 2000);
    expect(back.rangeExceptions, {'k': 'Organizer approved'});
    final open = Section.fromJson(
      Section(id: 'o', name: 'Open', players: const []).toJson(),
    );
    expect(open.toJson().containsKey('ratingFloor'), isFalse);
    expect(open.rangeExceptions, isEmpty);
  });

  test(
    'the section form reads the lowest rating and keeps it under the cap',
    () {
      final values = sectionValues(championship());
      expect(values['ratingFloor'], '800');
      expect(readSection(values).ratingFloor, 800);
      expect(
        () => readSection({...values, 'ratingFloor': '2000'}),
        throwsA(
          isA<SectionFieldProblem>().having(
            (p) => p.field,
            'field',
            'ratingFloor',
          ),
        ),
      );
    },
  );

  test('allowing a player in is recorded with its reason and undone by '
      'flagging again', () {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    final s = c.event!.sections.single;
    c.change('Set range', c.event!.copy(sections: [s.copy(ratingFloor: 1900)]));
    // p0 2000, p1 1950, p2 1900, p3 1850.
    expect(sectionRangeProblems(c.event!, c.event!.sections.single).keys, [
      'p3',
    ]);
    expect(
      () => c.allowOutsideRange('p0', 'Already eligible'),
      throwsA(isA<TournamentException>()),
    );
    final before = c.event!;
    c.allowOutsideRange('p3', 'Organizer approved a play-up');
    expect(eventRangeProblems(c.event!), isEmpty);
    expect(
      describeChanges(before, c.event!).join('\n'),
      contains(
        'allowed Player 03 outside the rating range: '
        'Organizer approved a play-up',
      ),
    );
    c.allowOutsideRange('p3', '');
    expect(eventRangeProblems(c.event!).keys, ['p3']);
  });

  test('a rating edit that leaves the range says so', () {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    final s = c.event!.sections.single;
    c.change('Set range', c.event!.copy(sections: [s.copy(ratingFloor: 1800)]));
    c.savePlayer(c.event!.player('p3').copy(rating: 1700));
    expect(c.playerNotice, startsWith('Rated 1700:'));
    expect(c.playerNotice, contains('28H2'));
  });

  test('Create pairings notes players outside the range but stays offered', () {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    final s = c.event!.sections.single;
    c.change(
      'Set range',
      c.event!.copy(sections: [s.copy(ratingCeiling: 1900)]),
    );
    final state = postState(c.event!, null);
    expect(state.label, startsWith('Create pairings'));
    expect(
      state.why,
      contains('3 players are outside their section’s rating range'),
    );
  });

  testWidgets('the Players row and the player card flag it; Allow records '
      'the reason', (tester) async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    final s = c.event!.sections.single;
    c.change(
      'Set range',
      c.event!.copy(sections: [s.copy(ratingCeiling: 1990)]),
    );
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => Row(
              children: [
                Expanded(child: PlayersView(controller: c)),
                SizedBox(
                  width: 420,
                  child: PlayerPanel(
                    controller: c,
                    player: c.event!.player('p0'),
                    onClose: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('outside the rating range'), findsOneWidget);
    expect(find.byKey(const ValueKey('panel-range-problem')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('panel-range-allow')));
    await tester.pump();
    // A reason is required.
    expect(c.event!.sections.single.rangeExceptions, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('panel-range-reason')),
      'Plays up with the organizer’s approval',
    );
    await tester.tap(find.byKey(const ValueKey('panel-range-allow')));
    await tester.pump();
    expect(c.event!.sections.single.rangeExceptions, {
      'p0': 'Plays up with the organizer’s approval',
    });
    expect(find.byKey(const ValueKey('panel-range-allowed')), findsOneWidget);
    expect(find.textContaining('outside the rating range'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
