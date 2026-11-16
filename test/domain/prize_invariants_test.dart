import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/prizes.dart';

/// A seeded random prize scenario, built to produce many ties: few distinct
/// scores, a mix of rated, unrated, withdrawn and computer entrants, and
/// odd-cent prizes so equal splits leave remainders.
///
/// With [unratedCap] and [pointsPrizes] both off, money is fully conserved
/// (no 32C6 remainder can be stranded and no pooled share is given up for a
/// 33E points prize), so the scenario can be checked to the cent.
Event prizeScenario(
  int seed, {
  bool unratedCap = false,
  bool pointsPrizes = false,
}) {
  final random = Random(seed);
  T pick<T>(List<T> xs) => xs[random.nextInt(xs.length)];
  final count = 2 + random.nextInt(11);
  final rounds = 2 + random.nextInt(3);
  // Two to four distinct scores, so most score groups are ties.
  final scores = [
    for (var i = 0; i < 2 + random.nextInt(3); i++)
      random.nextInt(2 * rounds + 1),
  ];
  final players = [
    for (var i = 0; i < count; i++)
      Player(
        id: 'x$i',
        name: 'Player ${i.toString().padLeft(2, '0')}',
        rating: random.nextInt(5) == 0 ? 0 : 800 + random.nextInt(33) * 50,
        withdrawn: random.nextInt(12) == 0,
        computer: random.nextInt(25) == 0,
      ),
  ];
  final halves = {for (final p in players) p.id: pick(scores)};
  final ids = [for (final p in players) p.id];
  int cents() => pick([0, 1, 7, 33, 99, 100, 101]) + 100 * random.nextInt(400);
  final prizes = <Json>[];
  final placeCount = random.nextInt(5);
  for (var n = 1; n <= placeCount; n++) {
    prizes.add({
      'id': 'place$n',
      'kind': 'place',
      'place': n,
      'cents': cents(),
      'trophy': random.nextInt(3) == 0,
    });
  }
  for (var i = random.nextInt(5); i > 0; i--) {
    final kind = pick(['class', 'under', 'unrated', 'junior', 'computer']);
    final min = 800 + random.nextInt(12) * 100,
        width = 100 + random.nextInt(4) * 100;
    prizes.add({
      'id': 'k${prizes.length}',
      'kind': kind,
      'place': 1 + random.nextInt(2),
      if (kind == 'class') 'min': min,
      if (kind == 'class' || kind == 'under') 'max': min + width,
      'cents': cents(),
      'trophy': random.nextInt(4) == 0,
      if (kind == 'junior')
        'eligible': [
          for (final id in ids)
            if (random.nextBool()) id,
        ],
    });
  }
  if (pointsPrizes) {
    for (var i = random.nextInt(3); i > 0; i--) {
      prizes.add({
        'id': 'pts${prizes.length}',
        'kind': 'points',
        'points': 1 + random.nextInt(2 * rounds),
        'cents': cents(),
      });
    }
  }
  return Event(
    id: 'e$seed',
    name: 'Scenario $seed',
    date: '2026-10-09',
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'Open',
        players: ids,
        plannedRounds: rounds,
        rounds: [
          for (var r = 1; r <= rounds; r++)
            Round(
              number: r,
              games: const [],
              byes: [
                for (final id in ids)
                  ByeAward(id, (halves[id]! - 2 * (r - 1)).clamp(0, 2), 'test'),
              ],
            ),
        ],
        prizes: PrizeTable.fromJson({
          'basedOn': random.nextInt(4) == 0 ? count + random.nextInt(10) : 0,
          'withdrawnEligible': random.nextBool(),
          if (unratedCap) 'unratedCapCents': 100 * (1 + random.nextInt(150)),
          'list': prizes,
        }),
      ),
    ],
  );
}

/// Pools as reported: prizes linked by `pooledWith`, plus every prize paid
/// whole to a clear winner. Each pool's sharers and amounts are returned.
List<({Set<String> prizes, Map<String, int> shares, int total})> pools(
  PrizeAllocation a,
) {
  final byId = {for (final l in a.lines) l.prize.id: l};
  final seen = <String>{};
  final out = <({Set<String> prizes, Map<String, int> shares, int total})>[];
  for (final line in a.lines) {
    if (line.prize.kind == PrizeKind.points || line.cash.isEmpty) continue;
    if (!seen.add(line.prize.id)) continue;
    final group = {line.prize.id}, queue = [line.prize.id];
    while (queue.isNotEmpty) {
      for (final other in byId[queue.removeLast()]!.pooledWith) {
        if (group.add(other)) queue.add(other);
      }
    }
    seen.addAll(group);
    final shares = <String, int>{};
    for (final id in group) {
      byId[id]!.cash.forEach((player, cents) {
        expect(
          shares.putIfAbsent(player, () => cents),
          cents,
          reason: 'a sharer is listed with one amount under every pooled prize',
        );
      });
    }
    out.add((
      prizes: group,
      shares: shares,
      total: group.fold(0, (sum, id) => sum + byId[id]!.paidCents),
    ));
  }
  return out;
}

void expectNoNegativeAmounts(PrizeAllocation a) {
  for (final award in a.awards) {
    expect(award.cents, greaterThanOrEqualTo(0));
  }
  for (final line in a.lines) {
    expect(line.paidCents, greaterThanOrEqualTo(0));
    for (final cents in line.cash.values) {
      expect(cents, greaterThan(0), reason: 'a cash entry is a positive share');
    }
  }
}

void main() {
  const seeds = 400;

  test('an uneven split gives the odd cents to the first in standings', () {
    final players = [
      for (final id in ['a', 'b', 'c']) Player(id: id, name: id, rating: 1500),
    ];
    final e = Event(
      id: 'e',
      name: 'Split',
      date: '2026-10-09',
      players: players,
      sections: [
        Section(
          id: 's',
          name: 'Open',
          players: const ['a', 'b', 'c'],
          rounds: [
            Round(
              number: 1,
              games: const [],
              byes: [for (final p in players) ByeAward(p.id, 2, 'test')],
            ),
          ],
          prizes: PrizeTable.fromJson({
            'list': [
              {'id': '1', 'kind': 'place', 'place': 1, 'cents': 10000},
              {'id': '2', 'kind': 'place', 'place': 2, 'cents': 1},
            ],
          }),
        ),
      ],
    );
    final a = allocatePrizes(e, e.sections.single);
    expect(
      {for (final w in a.awards) w.player.id: w.cents},
      {'a': 3334, 'b': 3334, 'c': 3333},
    );
    expect(a.paidCents, 10001);
  });

  test('every pool is split to the cent and paid in full', () {
    for (var seed = 0; seed < seeds; seed++) {
      final e = prizeScenario(seed);
      final a = allocatePrizes(e, e.sections.single);
      final reason = 'seed $seed: ${jsonEncode(a.toJson())}';
      expectNoNegativeAmounts(a);
      // Each player's take-home is their share of exactly one pool (32B1);
      // the shares of a pool sum to its prizes, to the cent.
      final held = <String, int>{};
      for (final pool in pools(a)) {
        expect(
          pool.shares.values.fold(0, (s, c) => s + c),
          pool.total,
          reason: 'pool ${pool.prizes} — $reason',
        );
        pool.shares.forEach((player, cents) {
          expect(held.containsKey(player), isFalse, reason: reason);
          held[player] = cents;
        });
      }
      expect(
        {
          for (final w in a.awards)
            if (w.cents > 0) w.player.id: w.cents,
        },
        held,
        reason: reason,
      );
    }
  });

  test('unrated limits and points prizes never create money', () {
    for (var seed = 0; seed < seeds; seed++) {
      final e = prizeScenario(seed, unratedCap: true, pointsPrizes: true);
      final section = e.sections.single;
      final a = allocatePrizes(e, section);
      final reason = 'seed $seed: ${jsonEncode(a.toJson())}';
      expectNoNegativeAmounts(a);
      final cap = section.prizes.unratedCapCents;
      final cashPrizes = a.lines.where((l) => l.prize.kind != PrizeKind.points);
      final pointsPaid = a.lines
          .where((l) => l.prize.kind == PrizeKind.points)
          .fold(0, (s, l) => s + l.cash.values.fold(0, (t, c) => t + c));
      expect(
        a.paidCents,
        lessThanOrEqualTo(
          cashPrizes.fold(0, (s, l) => s + l.paidCents) + pointsPaid,
        ),
        reason: reason,
      );
      for (final award in a.awards) {
        if (award.player.effectivePrizeRating == 0 &&
            !a.lines.any(
              (l) =>
                  l.prize.kind == PrizeKind.points &&
                  l.cash.containsKey(award.player.id),
            )) {
          expect(award.cents, lessThanOrEqualTo(cap), reason: reason);
        }
      }
    }
  });

  test('the allocation is deterministic', () {
    for (var seed = 0; seed < seeds; seed++) {
      final e = prizeScenario(seed, unratedCap: seed.isOdd, pointsPrizes: true);
      final first = jsonEncode(allocatePrizes(e, e.sections.single).toJson());
      expect(
        jsonEncode(allocatePrizes(e, e.sections.single).toJson()),
        first,
        reason: 'seed $seed',
      );
      // A saved and reloaded event allocates identically.
      final reloaded = Event.decode(e.encode());
      expect(
        jsonEncode(allocatePrizes(reloaded, reloaded.sections.single).toJson()),
        first,
        reason: 'seed $seed after a save and reload',
      );
    }
  });
}
