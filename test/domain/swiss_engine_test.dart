import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';

/// Engine behaviour beyond the rulebook's worked examples: repeat games
/// kept to the fewest boards, accelerated round 2, the search fallback,
/// explanations that say what happened, and large fields.
String Function() ids(String prefix) {
  var next = 0;
  return () => '$prefix${next++}';
}

/// [n] players p0..p(n-1), rated 2200 downwards in steps of 20.
Event field(
  int n, {
  int rounds = 5,
  String accelerated = '',
  bool avoidTeammates = false,
  String Function(int i)? team,
  int Function(int i)? rating,
}) {
  final players = [
    for (var i = 0; i < n; i++)
      Player(
        id: 'p$i',
        name: 'Player $i',
        rating: rating?.call(i) ?? 2200 - i * 20,
        team: team?.call(i) ?? '',
      ),
  ];
  return Event(
    id: 'e',
    name: 'Engine',
    date: '2026-11-10',
    colorToss: ColorToss.higherWhite,
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'Open',
        players: [for (final p in players) p.id],
        plannedRounds: rounds,
        accelerated: Acceleration.parse(accelerated),
        avoidTeammates: avoidTeammates,
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

/// [round] with every game won by the higher-rated player, or decided by
/// [outcome].
Round played(Event e, Round round, {Outcome? Function(Game g)? outcome}) =>
    round.copy(
      games: [
        for (final g in round.games)
          g.copy(
            outcome:
                outcome?.call(g) ??
                (e.player(g.white).rating >= e.player(g.black).rating
                    ? Outcome.whiteWin
                    : Outcome.blackWin),
          ),
      ],
    );

/// A posted round of [pairs] (white, black), all drawn.
Round drawn(int number, List<(String, String)> pairs) => Round(
  number: number,
  games: [
    for (final (i, (w, b)) in pairs.indexed)
      Game(
        id: 'r$number-$i',
        white: w,
        black: b,
        board: i + 1,
        outcome: Outcome.draw,
      ),
  ],
);

String pair(String a, String b) => a.compareTo(b) < 0 ? '$a-$b' : '$b-$a';

Set<String> pairsOf(Round r) => {
  for (final g in r.games) pair(g.white, g.black),
};

Set<String> metBefore(Event e) => {
  for (final g in e.games.where((g) => g.outcome.played))
    pair(g.white, g.black),
};

void main() {
  group('27A1 repeat games', () {
    /// Seven repeat-free rounds for ten players that leave the unplayed
    /// games as two five-player rings (0-1-2-3-4 and 5-6-7-8-9), which no
    /// round can be made of: each ring always leaves one player over.
    Event twoRings({Outcome Function(int round, String white)? outcome}) {
      var e = field(10, rounds: 9);
      Round round(int n, List<(String, String)> pairs) {
        final r = drawn(n, pairs);
        return outcome == null
            ? r
            : r.copy(
                games: [
                  for (final g in r.games) g.copy(outcome: outcome(n, g.white)),
                ],
              );
      }

      String a(int i) => 'p${i % 5}';
      String b(int i) => 'p${5 + i % 5}';
      for (var r = 0; r < 5; r++) {
        e = withRound(
          e,
          round(r + 1, [
            (a(r), a(r + 2)),
            (b(r), b(r + 2)),
            (a(r + 1), b(r + 1)),
            (a(r + 3), b(r + 4)),
            (a(r + 4), b(r + 3)),
          ]),
        );
      }
      for (final shift in [2, 3]) {
        e = withRound(
          e,
          round(e.sections.single.rounds.length + 1, [
            for (var i = 0; i < 5; i++) (a(i), b(i + shift)),
          ]),
        );
      }
      validateEvent(e);
      expect(metBefore(e).length, 35, reason: 'seven repeat-free rounds');
      return e;
    }

    test('ten players in round 8 repeat on one board only, and name it', () {
      for (final e in [
        twoRings(),
        // The first five players win everything they can.
        twoRings(
          outcome: (round, white) => int.parse(white.substring(1)) < 5
              ? Outcome.whiteWin
              : Outcome.draw,
        ),
      ]) {
        final before = metBefore(e);
        final round = proposeRound(e, e.sections.single, ids('x'));
        final repeats = [
          for (final g in round.games)
            if (before.contains(pair(g.white, g.black))) g,
        ];
        expect(repeats.length, 1, reason: 'one repeat is the fewest');
        final note = round.explanations.firstWhere((x) => x.contains('27A1'));
        expect(note, contains('board ${repeats.single.board}'));
        expect(RegExp('board ').allMatches(note).length, 1);
      }
    });

    test('a large field also repeats on the fewest boards', () {
      // 42 players in two halves of 21 who have played only across the
      // halves, for 21 rounds: each half is odd, so one game must repeat.
      var e = field(42, rounds: 30, rating: (i) => 2400 - i * 9);
      for (var r = 0; r < 21; r++) {
        e = withRound(
          e,
          drawn(r + 1, [
            for (var i = 0; i < 21; i++) ('p$i', 'p${21 + (i + r) % 21}'),
          ]),
        );
      }
      final before = metBefore(e);
      final round = proposeRound(e, e.sections.single, ids('x'));
      final repeats = pairsOf(round).where(before.contains);
      expect(repeats.length, 1);
      expect(round.explanations.join('\n'), contains('27A1'));
    });

    test('two odd rings of unplayed games cost exactly one repeat', () {
      // Six players whose unplayed games are two triangles (0,1,2) and
      // (3,4,5): every earlier game crossed the two halves.
      var e = field(6, rounds: 5);
      for (var r = 0; r < 3; r++) {
        e = withRound(
          e,
          drawn(r + 1, [
            for (var i = 0; i < 3; i++) ('p$i', 'p${3 + (i + r) % 3}'),
          ]),
        );
      }
      final before = metBefore(e);
      final round = proposeRound(e, e.sections.single, ids('x'));
      final repeats = [
        for (final g in round.games)
          if (before.contains(pair(g.white, g.black))) g,
      ];
      expect(repeats.length, 1);
      final note = round.explanations.firstWhere((x) => x.contains('27A1'));
      expect(note, contains('meeting is allowed where unavoidable (27A1)'));
      final g = repeats.single;
      expect(note, contains('board ${g.board}'));
      expect(note, contains(e.player(g.white).name));
      expect(note, contains(e.player(g.black).name));
      // Nobody else is named as meeting again.
      expect(RegExp('board ').allMatches(note).length, 1);
    });

    test('the repeat goes to the lowest scores, not the leaders', () {
      // The same two triangles, but 0-2 beat 3-5 every time: the leaders
      // 0, 1, 2 can meet each other, so the repeat joins a leader's half
      // to the other only at the lowest scores available.
      var e = field(6, rounds: 5);
      for (var r = 0; r < 3; r++) {
        final round = drawn(r + 1, [
          for (var i = 0; i < 3; i++) ('p$i', 'p${3 + (i + r) % 3}'),
        ]);
        e = withRound(
          e,
          round.copy(
            games: [
              // p0 wins all three, p1 two, p2 one.
              for (final g in round.games)
                g.copy(
                  outcome: g.white == 'p0' || (g.white == 'p1' && r < 2)
                      ? Outcome.whiteWin
                      : g.white == 'p2' && r < 1
                      ? Outcome.whiteWin
                      : Outcome.blackWin,
                ),
            ],
          ),
        );
      }
      final before = metBefore(e);
      final round = proposeRound(e, e.sections.single, ids('x'));
      final repeat = round.games.singleWhere(
        (g) => before.contains(pair(g.white, g.black)),
      );
      expect({repeat.white, repeat.black}.contains('p0'), isFalse);
    });

    test('four players who have all met pair again without a third game', () {
      var e = field(4, rounds: 6);
      final rr = [
        [('p0', 'p3'), ('p1', 'p2')],
        [('p2', 'p0'), ('p3', 'p1')],
        [('p0', 'p1'), ('p2', 'p3')],
      ];
      for (var r = 0; r < 3; r++) {
        e = withRound(e, drawn(r + 1, rr[r]));
      }
      final seen = <String, int>{};
      for (var r = 4; r <= 6; r++) {
        final round = proposeRound(e, e.sections.single, ids('r$r'));
        expect(round.explanations.join('\n'), contains('27A1'));
        for (final p in pairsOf(round)) {
          seen[p] = (seen[p] ?? 0) + 1;
        }
        e = withRound(e, played(e, round, outcome: (_) => Outcome.draw));
      }
      // Rounds 4-6 are a second round robin: nobody meets a third time.
      expect(seen.values.toSet(), {1});
    });
  });

  group('28R1 added score', () {
    test('round 2 keeps the round-1 halves whatever the results', () {
      var e = field(16, accelerated: 'addedScore');
      final r1 = proposeRound(e, e.sections.single, ids('a'));
      expect(pairsOf(r1), {
        for (var i = 0; i < 4; i++) ...{
          pair('p$i', 'p${i + 4}'),
          pair('p${i + 8}', 'p${i + 12}'),
        },
      });
      e = withRound(e, played(e, r1));
      final r2 = proposeRound(e, e.sections.single, ids('b'));
      int number(String id) => int.parse(id.substring(1));
      for (final g in r2.games) {
        final a = number(g.white), b = number(g.black);
        final low = min(a, b), high = max(a, b);
        if (low < 4) {
          expect(high, lessThan(4), reason: 'winners of the top half');
        } else if (low < 8) {
          expect(high, inInclusiveRange(8, 11), reason: '5-8 v 9-12');
        } else {
          expect(low, greaterThanOrEqualTo(12), reason: 'bottom-half losers');
        }
      }
      expect(r2.explanations.join('\n'), contains('28R1'));
    });

    test('two top-half players who drew stay in one group', () {
      var e = field(16, accelerated: 'addedScore');
      final r1 = proposeRound(e, e.sections.single, ids('a'));
      e = withRound(
        e,
        played(
          e,
          r1,
          outcome: (g) =>
              {g.white, g.black}.contains('p0') ? Outcome.draw : null,
        ),
      );
      final r2 = proposeRound(e, e.sections.single, ids('b'));
      // p0 and p4 drew: each has 1/2 + 1 and they cannot meet again, so
      // each plays someone on a full point of pairing score.
      for (final id in ['p0', 'p4']) {
        final g = r2.games.firstWhere((g) => g.white == id || g.black == id);
        final other = g.white == id ? g.black : g.white;
        expect(
          int.parse(other.substring(1)),
          lessThan(12),
          reason: '$id is not paired with the bottom-half losers',
        );
      }
    });
  });

  group('explanations', () {
    test('a lone leader adds no "re-paired from the top" note', () {
      // p0 alone on 2, then four on 1 who pair naturally.
      var e = field(6, rounds: 4);
      final r1 = proposeRound(e, e.sections.single, ids('a'));
      e = withRound(e, played(e, r1));
      final r2 = proposeRound(e, e.sections.single, ids('b'));
      e = withRound(e, played(e, r2));
      final r3 = proposeRound(e, e.sections.single, ids('c'));
      expect(r3.explanations.join('\n'), isNot(contains('re-paired')));
    });
  });

  group('large fields', () {
    Event simulate(int n, int rounds, int seed, {bool check = true}) {
      final rng = Random(seed);
      var e = field(n, rounds: rounds, rating: (i) => 2400 - i * 7);
      final next = ids('g');
      for (var r = 1; r <= rounds; r++) {
        final watch = Stopwatch()..start();
        final round = proposeRound(e, e.sections.single, next);
        expect(
          watch.elapsed,
          lessThan(const Duration(seconds: 10)),
          reason: 'round $r of $n players',
        );
        e = withRound(
          e,
          played(
            e,
            round,
            outcome: (g) {
              // The higher-rated player usually wins.
              final d = e.player(g.white).rating - e.player(g.black).rating;
              final x = rng.nextDouble();
              final white = 1 / (1 + pow(10, -d / 400));
              return x < white * 0.85
                  ? Outcome.whiteWin
                  : x < white * 0.85 + 0.15
                  ? Outcome.draw
                  : Outcome.blackWin;
            },
          ),
        );
      }
      return e;
    }

    test('300 players pair every round of seven within seconds', () {
      final e = simulate(300, 7, 1);
      expect(e.sections.single.rounds.length, 7);
      expect(metBefore(e).length, 150 * 7, reason: 'no repeat game');
    });

    test('colors stay within one of equal through seven rounds', () {
      for (final (n, seed) in [(150, 2), (200, 3), (201, 4)]) {
        final e = simulate(n, 7, seed);
        final worst = <String, int>{};
        for (final g in e.games) {
          worst[g.white] = (worst[g.white] ?? 0) + 1;
          worst[g.black] = (worst[g.black] ?? 0) - 1;
        }
        final off = worst.entries.where((x) => x.value.abs() > 2).toList();
        expect(off, isEmpty, reason: '$n players, seed $seed');
      }
    });
  });
}
