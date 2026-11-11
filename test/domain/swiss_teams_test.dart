import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';

import 'swiss_rules_test.dart' show scenario;

/// Rule 28N1, team-mates kept apart by the plus-two method, in the shapes
/// a scholastic section really takes: one school a majority, two schools
/// splitting the score groups, and odd players arriving from above.
String Function() ids(String prefix) {
  var next = 0;
  return () => '$prefix${next++}';
}

Event section(int n, String Function(int i) team, {int rounds = 5}) {
  final players = [
    for (var i = 0; i < n; i++)
      Player(
        id: 'p$i',
        name: 'Player $i',
        rating: 1800 - i * 13,
        team: team(i),
      ),
  ];
  return Event(
    id: 'teams',
    name: 'Scholastic',
    date: '2026-11-10',
    colorToss: ColorToss.higherWhite,
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'K-5',
        players: [for (final p in players) p.id],
        plannedRounds: rounds,
        avoidTeammates: true,
      ),
    ],
  );
}

Event withRound(Event e, Round round) {
  final s = e.sections.single;
  return e.copy(
    sections: [
      s.copy(rounds: [...s.rounds, round]),
    ],
  );
}

/// The games of [round] between two players of one team.
List<Game> mates(Event e, Round round) => [
  for (final g in round.games)
    if (e.player(g.white).team.isNotEmpty &&
        e.player(g.white).team == e.player(g.black).team)
      g,
];

void main() {
  test('a majority team pairs at once, with the fewest team-mate games', () {
    for (final (n, own) in [(30, 16), (40, 26), (24, 13), (300, 170)]) {
      // The host school's players are spread through the rating list.
      final rng = Random(n);
      final host = ([
        for (var i = 0; i < n; i++) i,
      ]..shuffle(rng)).take(own).toSet();
      final e = section(n, (i) => host.contains(i) ? 'Host' : 'School $i');
      final watch = Stopwatch()..start();
      final round = proposeRound(e, e.sections.single, ids('x'));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(round.games.length, n ~/ 2);
      expect(
        mates(e, round).length,
        (own - (n - own)) ~/ 2,
        reason: '$own of $n from one school',
      );
      final note = round.explanations.firstWhere((x) => x.contains('28N1'));
      expect(note, contains('Team-mates meet'));
      for (final g in mates(e, round)) {
        expect(note, contains(e.player(g.white).name));
      }
    }
  });

  test('a section mostly from one team pairs every round', () {
    for (var seed = 0; seed < 12; seed++) {
      final rng = Random(seed);
      final n = 8 + rng.nextInt(9);
      var e = section(n, (i) => i % 10 < 7 ? 'Host' : '');
      final next = ids('g$seed-');
      for (var r = 1; r <= 5; r++) {
        final round = proposeRound(e, e.sections.single, next);
        final seen = [
          for (final g in round.games) ...[g.white, g.black],
          for (final b in round.byes) b.player,
        ]..sort();
        expect(seen, [...e.sections.single.players]..sort());
        e = withRound(
          e,
          round.copy(
            games: [
              for (final g in round.games)
                g.copy(
                  outcome: const [
                    Outcome.whiteWin,
                    Outcome.blackWin,
                    Outcome.draw,
                  ][rng.nextInt(3)],
                ),
            ],
          ),
        );
      }
    }
  });

  test('28N1b: team-mates who would meet move down instead', () {
    // Two schools of twelve. Round 1 crosses them; school A wins on eight
    // boards and school B on four, so the 1-point group is 8 A and 4 B and
    // the 0-point group 4 A and 8 B.
    var e = section(24, (i) => i < 12 ? 'A' : 'B');
    e = withRound(
      e,
      Round(
        number: 1,
        games: [
          for (var i = 0; i < 12; i++)
            Game(
              id: 'r1-$i',
              white: 'p$i',
              black: 'p${12 + i}',
              board: i + 1,
              outcome: i < 8 ? Outcome.whiteWin : Outcome.blackWin,
            ),
        ],
      ),
    );
    final round = proposeRound(e, e.sections.single, ids('x'));
    printOnFailure(round.explanations.join('\n'));
    expect(mates(e, round), isEmpty);
    expect(round.explanations.join('\n'), contains('28N1b'));
    // Nobody leaves a score group who did not have to: four 1-pointers
    // meet four 0-pointers.
    final scores = {for (var i = 0; i < 24; i++) 'p$i': i < 8 || i >= 20};
    final cross = round.games
        .where((g) => scores[g.white] != scores[g.black])
        .length;
    expect(cross, 4);
  });

  test('28N1b: a group below supplies opponents from the group above', () {
    // The 1-point group is 2 from school A and 6 unattached; the 0-point
    // group is 6 from A and 2 from B. Four of the unattached players come
    // down so that no two of A's 0-pointers have to meet.
    var e = section(
      16,
      (i) => i < 2
          ? 'A'
          : i < 8
          ? ''
          : i < 14
          ? 'A'
          : 'B',
    );
    // Round 1 against opponents who have since withdrawn.
    final gone = [
      for (var i = 0; i < 16; i++)
        Player(id: 'x$i', name: 'Gone $i', rating: 1000, withdrawn: true),
    ];
    e = e.copy(
      players: [...e.players, ...gone],
      sections: [
        e.sections.single.copy(
          players: [...e.sections.single.players, for (final g in gone) g.id],
          rounds: [
            Round(
              number: 1,
              games: [
                for (var i = 0; i < 16; i++)
                  Game(
                    id: 'r1-$i',
                    white: i.isEven ? 'p$i' : 'x$i',
                    black: i.isEven ? 'x$i' : 'p$i',
                    board: i + 1,
                    outcome: (i < 8) == i.isEven
                        ? Outcome.whiteWin
                        : Outcome.blackWin,
                  ),
              ],
            ),
          ],
        ),
      ],
    );
    final round = proposeRound(e, e.sections.single, ids('x'));
    printOnFailure(round.explanations.join('\n'));
    expect(mates(e, round), isEmpty);
    expect(round.explanations.join('\n'), contains('28N1b'));
  });

  test('28N1a: an odd player from above meets a team-mate last', () {
    // The 4-0 leader drops into the 3-1 group, whose top player is a
    // team-mate: the next-highest is the opponent.
    final e = scenario(
      [
        (id: 'f', rating: 2300, colors: 'WBWB', points: 8),
        (id: 'm1', rating: 2250, colors: 'BWBW', points: 6),
        (id: 'm2', rating: 2200, colors: 'WBWB', points: 6),
        (id: 'm3', rating: 2100, colors: 'BWBW', points: 6),
        (id: 'm4', rating: 2000, colors: 'WBWB', points: 6),
        (id: 'l1', rating: 1900, colors: 'BWBW', points: 4),
        (id: 'l2', rating: 1800, colors: 'WBWB', points: 4),
        (id: 'l3', rating: 1700, colors: 'BWBW', points: 4),
      ],
      adjust: {
        'f': (p) => p.copy(team: 'T'),
        'm1': (p) => p.copy(team: 'T'),
      },
    );
    final s = e.sections.single.copy(avoidTeammates: true);
    final round = proposeRound(e.copy(sections: [s]), s, ids('x'));
    final game = round.games.firstWhere(
      (g) => g.white == 'f' || g.black == 'f',
    );
    expect({game.white, game.black}, {'f', 'm2'});
  });

  test('28N1c: with only team-mates to play, the odd player meets one', () {
    final e = scenario(
      [
        (id: 'f', rating: 2300, colors: 'WBWB', points: 8),
        (id: 'm1', rating: 2250, colors: 'BWBW', points: 6),
        (id: 'm2', rating: 2200, colors: 'WBWB', points: 6),
        (id: 'm3', rating: 2100, colors: 'BWBW', points: 6),
      ],
      adjust: {
        for (final id in ['f', 'm1', 'm2', 'm3']) id: (p) => p.copy(team: 'T'),
      },
    );
    final s = e.sections.single.copy(avoidTeammates: true);
    final round = proposeRound(e.copy(sections: [s]), s, ids('x'));
    expect(round.games.length, 2);
    expect(round.explanations.join('\n'), contains('28N1'));
  });
}
