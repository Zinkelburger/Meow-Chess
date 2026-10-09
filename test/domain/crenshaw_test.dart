import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/standings.dart';

Event roundRobinEvent(
  int n, {
  String table = crenshawTable,
  bool doubleCycle = false,
  int? plannedRounds,
  List<Round> rounds = const [],
  Set<String> withdrawn = const {},
}) {
  final ids = List.generate(n, (i) => 'p${i + 1}');
  return Event(
    id: 'event',
    name: 'Club RR',
    date: '2026-01-01',
    players: [
      for (final (i, id) in ids.indexed)
        Player(
          id: id,
          name: 'Player ${i + 1}',
          rating: 1500,
          withdrawn: withdrawn.contains(id),
        ),
    ],
    sections: [
      Section(
        id: 'rr',
        name: 'Round robin',
        format: Format.roundRobin,
        players: ids,
        plannedRounds: plannedRounds ?? (n.isOdd ? n : n - 1),
        rrTable: table,
        doubleCycle: doubleCycle,
        rounds: rounds,
      ),
    ],
  );
}

void main() {
  test('every tabulated size meets every other number exactly once', () {
    for (var n = 3; n <= crenshawMaxPlayers; n++) {
      final rounds = crenshawPairings(n);
      final size = n.isOdd ? n + 1 : n;
      expect(rounds, hasLength(size - 1), reason: '$n players');
      final met = <String>{};
      final whites = <int, int>{}, blacks = <int, int>{};
      for (final round in rounds) {
        final used = <int>{};
        expect(round, hasLength(size ~/ 2));
        for (final (w, b) in round) {
          expect(used.add(w), true, reason: '$n players: $w twice');
          expect(used.add(b), true, reason: '$n players: $b twice');
          expect(w, inInclusiveRange(1, size));
          expect(b, inInclusiveRange(1, size));
          final key = w < b ? '$w-$b' : '$b-$w';
          expect(met.add(key), true, reason: '$n players: $key twice');
          whites[w] = (whites[w] ?? 0) + 1;
          blacks[b] = (blacks[b] ?? 0) + 1;
        }
      }
      expect(met, hasLength(size * (size - 1) ~/ 2));
      for (var p = 1; p <= size; p++) {
        expect(
          ((whites[p] ?? 0) - (blacks[p] ?? 0)).abs(),
          lessThanOrEqualTo(1),
          reason: '$n players: colors of $p',
        );
      }
    }
    expect(() => crenshawPairings(2), throwsA(isA<TournamentException>()));
    expect(
      () => crenshawPairings(crenshawMaxPlayers + 1),
      throwsA(isA<TournamentException>()),
    );
  });

  test('the 3–4 table is the quad table printed under rule 30G', () {
    expect(crenshawPairings(4), [
      [(1, 4), (2, 3)],
      [(3, 1), (4, 2)],
      [(1, 2), (3, 4)],
    ]);
    expect(crenshawPairings(3), crenshawPairings(4));
  });

  test('the 5–6 table pairs and colors each round as printed', () {
    expect(crenshawPairings(6), [
      [(3, 6), (5, 4), (1, 2)],
      [(2, 6), (4, 1), (3, 5)],
      [(6, 5), (1, 3), (4, 2)],
      [(6, 4), (5, 1), (2, 3)],
      [(1, 6), (2, 5), (3, 4)],
    ]);
    // Rule 29L TD TIP reads round 1 of Table B as 1 v 2, 3 v 6, 5 v 4.
    final first = crenshawPairings(6).first.map((p) => '${p.$1}-${p.$2}');
    expect(first, containsAll(['1-2', '3-6', '5-4']));
  });

  test('the 7–8 table pairs and colors each round as printed', () {
    expect(crenshawPairings(8), [
      [(4, 8), (5, 3), (6, 2), (7, 1)],
      [(8, 7), (1, 6), (2, 5), (3, 4)],
      [(3, 8), (4, 2), (5, 1), (6, 7)],
      [(8, 6), (7, 5), (1, 4), (2, 3)],
      [(2, 8), (3, 1), (4, 7), (5, 6)],
      [(8, 5), (6, 4), (7, 3), (1, 2)],
      [(1, 8), (2, 7), (3, 6), (4, 5)],
    ]);
    expect(crenshawPairings(7), crenshawPairings(8));
  });

  test('larger tables match the rulebook errata for their first round', () {
    // 5th edition errata: 13–14 round 1 board 1 is 7-14; 15–16 round 1 has
    // 15 with White against 1.
    expect(crenshawPairings(14).first.first, (7, 14));
    expect(crenshawPairings(16).first, contains((15, 1)));
    expect(crenshawPairings(12).first, [
      (6, 12),
      (7, 5),
      (8, 4),
      (9, 3),
      (10, 2),
      (11, 1),
    ]);
    expect(crenshawPairings(10).last, [
      (1, 10),
      (2, 9),
      (3, 8),
      (4, 7),
      (5, 6),
    ]);
  });

  test('an odd field sits out the highest number each round', () {
    final schedule = roundRobinSchedule([
      'a',
      'b',
      'c',
      'd',
      'e',
    ], table: crenshawTable);
    expect(schedule, hasLength(5));
    // Round 1 pairs 3-6, so player 3 (c) sits out.
    expect(schedule.first, [('c', null), ('e', 'd'), ('a', 'b')]);
    final sitOuts = [
      for (final round in schedule)
        round.firstWhere((p) => p.$1 == null || p.$2 == null),
    ];
    expect(sitOuts.map((p) => p.$1 ?? p.$2).toSet(), hasLength(5));
  });

  test('the circle method stays the default policy; the table is named', () {
    final circle = roundRobinEvent(6, table: '');
    final crenshaw = roundRobinEvent(6);
    expect(paperRound(circle.sections.single, 1).policy, 'circle-rr-v1');
    expect(paperRound(crenshaw.sections.single, 1).policy, 'crenshaw-rr-v1');
    expect(
      scheduledRound(
        crenshaw,
        crenshaw.sections.single,
        1,
        (r, w, b) => '$r-$w-$b',
      ).games.map((g) => '${g.white}-${g.black}'),
      ['p3-p6', 'p5-p4', 'p1-p2'],
    );
    expect(
      () => roundRobinSchedule(
        List.generate(crenshawMaxPlayers + 1, (i) => '$i'),
        table: crenshawTable,
      ),
      throwsA(isA<TournamentException>()),
    );
  });

  test('a double round robin repeats the cycle with colors reversed', () {
    for (final table in ['', crenshawTable]) {
      for (final n in [4, 5, 8]) {
        final section = roundRobinEvent(
          n,
          table: table,
          doubleCycle: true,
          plannedRounds: 2 * (n.isOdd ? n : n - 1),
        ).sections.single;
        final schedule = sectionSchedule(section);
        final cycle = n.isOdd ? n : n - 1;
        expect(schedule, hasLength(2 * cycle));
        for (var r = 0; r < cycle; r++) {
          expect(schedule[r + cycle], [
            for (final (w, b) in schedule[r]) (b, w),
          ]);
        }
        expect(doubleCycleProblem(section), isNull);
        expect(
          doubleCycleProblem(section.copy(plannedRounds: cycle)),
          contains('is ${2 * cycle} rounds'),
        );
        expect(doubleCycleProblem(section.copy(doubleCycle: false)), isNull);
      }
    }
  });

  test('rule 30B counts both cycles when excluding an early withdrawal', () {
    final base = roundRobinEvent(
      4,
      doubleCycle: true,
      plannedRounds: 6,
      withdrawn: {'p1'},
    );
    final section = base.sections.single;
    // Paper rounds list everyone, so the withdrawn player's games exist.
    final played = [
      for (var n = 1; n <= 3; n++)
        paperRound(section, n).copy(
          games: [
            for (final g in paperRound(section, n).games)
              g.copy(outcome: Outcome.draw),
          ],
        ),
    ];
    // Two of six scheduled games played: not half, so out of the prize list.
    final two = base.copy(
      sections: [section.copy(rounds: played.take(2).toList())],
    );
    expect(
      standings(
        two,
        two.sections.single,
        forPrizes: true,
      ).map((r) => r.player.id),
      isNot(contains('p1')),
    );
    // Three of six: half their games, so they stay.
    final three = base.copy(sections: [section.copy(rounds: played)]);
    expect(
      standings(
        three,
        three.sections.single,
        forPrizes: true,
      ).map((r) => r.player.id),
      contains('p1'),
    );
  });
}
