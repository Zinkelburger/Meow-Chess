import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/team_standings.dart';

import 'prizes_test.dart'
    show cash, classPrize, fixture, place, run, trophies, under;
import 'team_standings_test.dart' show schools, team, teamEvent, twoSchools;

void main() {
  group('33D1a: a trophy with more cash ranks higher', () {
    test('33D2 Example 3: 1st Under 1800 outranks 2nd Under 2000', () {
      final e = fixture(
        [
          ('1', 1650, 10),
          ('2', 1750, 10),
          ('3', 2020, 9),
          ('4', 1675, 9),
          ('5', 1920, 9),
          ('6', 1700, 9),
          ('7', 1845, 9),
        ],
        [
          under('a1', 2000, 200, trophy: true),
          under('a2', 2000, 100, place: 2, trophy: true),
          under('b1', 1800, 200, trophy: true),
          under('b2', 1800, 100, place: 2, trophy: true),
        ],
      );
      final a = run(e);
      expect(cash(a), {'1': 200, '2': 200, '4': 50, '5': 50, '6': 50, '7': 50});
      expect(trophies(a), {
        '1': ['a1'],
        '2': ['b1'],
        '4': ['a2'],
        '6': ['b2'],
      });
    });

    test('a class trophy with more cash goes before a lower place', () {
      final e = fixture(
        [('1', 2100, 10), ('2', 1700, 8), ('3', 2000, 6)],
        [
          place(1, 200, trophy: true),
          place(2, 50, trophy: true),
          classPrize('b', 1600, 1799, 100, trophy: true),
        ],
      );
      final a = run(e);
      expect(cash(a), {'1': 200, '2': 100, '3': 50});
      expect(trophies(a), {
        '1': ['p1'],
        '2': ['b'],
        '3': ['p2'],
      });
    });

    test('trophies without cash keep place before class', () {
      final e = fixture(
        [('1', 2100, 10), ('2', 1700, 8), ('3', 2000, 6)],
        [
          place(1, 0, trophy: true),
          place(2, 0, trophy: true),
          classPrize('b', 1600, 1799, 0, trophy: true),
        ],
      );
      expect(trophies(run(e)), {
        '1': ['p1'],
        '2': ['p2'],
      });
    });
  });

  group('33F / 32B3: an unrated limit', () {
    test('never lifts a tied player above the prize they would win alone', () {
      final e = fixture(
        [('u', 0, 10), ('a', 2000, 10), ('b', 2000, 8)],
        [place(1, 200), place(2, 100)],
        unratedCapCents: 5000,
      );
      final a = run(e);
      // $150 each; the unrated keeps $50, the rated player may reach the
      // $200 first prize and no more, and $50 goes on to the next score.
      expect(cash(a), {'u': 50, 'a': 200, 'b': 50});
      expect(a.paidCents, 30000);
      expect(
        a.explanations,
        contains(
          allOf(
            contains('\$50 goes to the others in the tie'),
            contains('remaining \$50 of 1st goes to the next eligible'),
          ),
        ),
      );
    });

    test('with nobody below, the rest of the excess is not paid', () {
      final e = fixture(
        [('u', 0, 10), ('a', 2000, 10)],
        [place(1, 200), place(2, 100)],
        unratedCapCents: 5000,
      );
      expect(cash(run(e)), {'u': 50, 'a': 200});
    });
  });

  group('32C4a: based-on prizes pay the exact proportion', () {
    Event based(int entries, int basedOn, List<Json> prizes) => fixture(
      [for (var i = 0; i < entries; i++) ('$i', 2000, i == 0 ? 2 : 0)],
      prizes,
      basedOn: basedOn,
    );

    test('47 of 60 pays 78.33%, rounded up to the cent', () {
      final a = run(based(47, 60, [place(1, 1000)]));
      expect(a.lines.single.paidCents, 78334);
      expect(a.awards.single.cents, 78334);
      expect(a.payoutPercent, 78);
      expect(a.explanations.first, contains('47/60 of its amount (78.33%'));
    });

    test('a small fund below half pays the proportion, a large one half', () {
      // $400 in all: no 50% minimum. 7 of 40 of $333.33 is $58.34.
      final small = run(
        based(7, 40, [
          {'id': 'x', 'kind': 'place', 'place': 1, 'cents': 33333},
        ]),
      );
      expect(small.lines.single.paidCents, 5834);
      // Over $500: half of $777.77, rounded up.
      final large = run(
        based(7, 40, [
          {'id': 'x', 'kind': 'place', 'place': 1, 'cents': 77777},
        ]),
      );
      expect(large.lines.single.paidCents, 38889);
      expect(large.payoutPercent, 50);
    });

    test('team prizes are reduced by the same exact proportion', () {
      final e = teamEvent(
        twoSchools,
        schools,
        prizes: [
          {'id': 't1', 'kind': 'team', 'place': 1, 'cents': 10000},
        ],
      );
      final s = e.sections.single;
      final reduced = e.copy(
        sections: [
          s.copy(prizes: {...s.prizes, 'basedOn': 30}),
        ],
      );
      // 10 of 30 of $100.
      expect(allocateTeamPrizes(reduced, reduced.sections.single).teamCents, {
        'Lincoln': 3334,
      });
    });
  });

  test('a prize labelled with its award names the award once', () {
    final e = fixture(
      [('1', 2000, 2), ('2', 2000, 0)],
      [
        {
          'id': 'c',
          'label': 'Champion trophy',
          'kind': 'place',
          'place': 1,
          'trophy': true,
        },
        {'id': 'm', 'kind': 'place', 'place': 2, 'item': 'Medal'},
      ],
    );
    final a = run(e);
    expect(a.explanations, contains('Player 1 takes the Champion trophy.'));
    expect(a.explanations, contains('Player 2 takes the 2nd medal.'));
    expect(a.explanations.join(), isNot(contains('trophy trophy')));
  });

  group('team awards', () {
    test('a team trophy goes to the team in its place', () {
      final e = teamEvent(
        twoSchools,
        schools,
        prizes: [
          {'id': 't1', 'kind': 'team', 'place': 1, 'cents': 10000},
          {'id': 't2', 'kind': 'team', 'place': 2, 'trophy': true},
          {'id': 't3', 'kind': 'team', 'place': 3, 'trophy': true},
        ],
      );
      final a = allocateTeamPrizes(e, e.sections.single);
      expect(a.lines[0].trophyTeam, isNull);
      expect(a.lines[0].cash, {'Lincoln': 10000});
      expect(a.lines[1].trophyTeam, 'Grant');
      expect(a.lines[2].trophyTeam, isNull);
      expect(a.lines[2].note, 'No eligible team');
    });

    // X: A and B both score 1; B met the stronger field (Solkoff 3 to
    // 2½), though A comes first by name. Y: C 2, D 1.
    const rounds = [
      ['A-E=1', 'B-C=0', 'D-F=1'],
      ['B-D=1', 'A-C=0', 'E-F=½'],
    ];
    const labels = {'A': 'X', 'B': 'X', 'C': 'Y', 'D': 'Y'};

    test('counting players are the best by score, then tie-breaks, '
        'whether or not the standings show tie-break ranks', () {
      for (final useTiebreaks in [false, true]) {
        final e = teamEvent(
          rounds,
          labels,
          useTiebreaks: useTiebreaks,
          awards: const TeamAwards(counting: 1),
        );
        final x = team(teamStandings(e, e.sections.single), 'X');
        expect(
          x.counting.single.player.id,
          'B',
          reason: 'useTiebreaks $useTiebreaks',
        );
        expect(x.members.map((m) => m.player.id), ['B', 'A']);
      }
    });

    test('Rollins points do not change with that switch', () {
      List<(String, int)> points(bool useTiebreaks) {
        final e = teamEvent(
          rounds,
          labels,
          useTiebreaks: useTiebreaks,
          awards: const TeamAwards(counting: 2, method: TeamScoring.rollins),
        );
        return [
          for (final t in teamStandings(e, e.sections.single))
            for (final m in t.members) (m.player.id, m.points),
        ];
      }

      expect(points(false), points(true));
      // Six players: C first (5), then B ahead of A and D on tie-breaks.
      expect(points(false).firstWhere((p) => p.$1 == 'C').$2, 5);
      expect(points(false).firstWhere((p) => p.$1 == 'B').$2, 4);
    });
  });
}
