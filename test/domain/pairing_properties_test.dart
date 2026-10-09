import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/standings.dart';

/// Pure-domain simulations: no storage, seeded randomness, every intermediate
/// event checked against [validateEvent] and the pairing invariants below.
String Function() ids(String prefix) {
  var next = 0;
  return () => '$prefix${next++}';
}

Event field(int n, {int rounds = 5, Format format = Format.swiss}) {
  final players = [
    for (var i = 0; i < n; i++)
      Player(
        id: 'p$i',
        name: 'Player $i',
        rating: 2200 - i * 17,
        checkedIn: true,
      ),
  ];
  return Event(
    id: 'e',
    name: 'Property event',
    date: '2026-09-29',
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'Open',
        players: [for (final p in players) p.id],
        format: format,
        plannedRounds: rounds,
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

Round decide(Round round, Random rng) => round.copy(
  games: [
    for (final g in round.games)
      g.copy(
        outcome: const [
          Outcome.whiteWin,
          Outcome.blackWin,
          Outcome.draw,
          Outcome.whiteForfeit,
          Outcome.blackForfeit,
          Outcome.doubleForfeit,
        ][rng.nextInt(20) < 17 ? rng.nextInt(3) : 3 + rng.nextInt(3)],
      ),
  ],
);

void main() {
  test('simulated Swiss events keep every pairing invariant', () {
    for (var seed = 0; seed < 40; seed++) {
      final rng = Random(seed);
      final n = 2 + rng.nextInt(30), rounds = 3 + rng.nextInt(4);
      var e = field(n, rounds: rounds);
      final next = ids('g$seed-');
      final opponents = <String>{};
      final allocated = <String>{};
      for (var r = 1; r <= rounds; r++) {
        // Occasionally withdraw someone or reserve a half-point bye ahead.
        if (rng.nextInt(4) == 0) {
          final victim = e.players[rng.nextInt(n)];
          e = e.copy(
            players: [
              for (final p in e.players)
                p.id != victim.id
                    ? p
                    : rng.nextBool()
                    ? p.copy(withdrawn: true)
                    : p.copy(byes: {...p.byes, r: 1}),
            ],
          );
        }
        final round = proposeRound(e, e.sections.single, next);
        // Small fields legitimately run out of non-repeat pairings; a
        // second meeting is then allowed, but only with an explicit
        // explanation (27A1), never silently.
        final repeatsAllowed = round.explanations.any(
          (x) => x.contains('meeting is allowed where unavoidable (27A1)'),
        );
        final seen = <String>[
          for (final g in round.games) ...[g.white, g.black],
          for (final b in round.byes) b.player,
        ];
        expect(
          seen..sort(),
          [...e.sections.single.players]..sort(),
          reason: 'seed $seed round $r: everyone exactly once',
        );
        for (final g in round.games) {
          final pair = ([g.white, g.black]..sort()).join('/');
          expect(
            opponents.contains(pair) && !repeatsAllowed,
            false,
            reason: 'seed $seed repeats played pair $pair',
          );
          for (final id in [g.white, g.black]) {
            final p = e.player(id);
            expect(p.withdrawn || p.byes.containsKey(r), false);
          }
        }
        for (final b in round.byes.where((b) => b.allocated)) {
          // 28L3: a second full-point bye only when nobody is eligible,
          // and then only with an explanation.
          expect(
            allocated.add(b.player) || b.reason.contains('28L3 could not'),
            true,
            reason: 'second full bye',
          );
        }
        final decided = decide(round, rng);
        // Only a played game makes two players prior opponents; a forfeited
        // pairing may be paired again.
        for (final g in decided.games.where((g) => g.outcome.played)) {
          opponents.add(([g.white, g.black]..sort()).join('/'));
        }
        e = withRound(e, decided);
        validateEvent(e);
      }
    }
  });

  test('colors equalize first and then alternate', () {
    for (var seed = 0; seed < 20; seed++) {
      final rng = Random(seed);
      var e = field(10 + rng.nextInt(20), rounds: 5);
      final next = ids('c$seed-');
      final balance = <String, int>{}, last = <String, int>{};
      for (var r = 1; r <= 5; r++) {
        final round = proposeRound(e, e.sections.single, next);
        for (final g in round.games) {
          final w = balance[g.white] ?? 0, b = balance[g.black] ?? 0;
          expect(w <= b, true, reason: 'white had more whites (seed $seed)');
          if (w == b) {
            expect(
              (last[g.white] ?? 0) <= (last[g.black] ?? 0),
              true,
              reason: 'white had white more recently (seed $seed)',
            );
          }
        }
        final decided = decide(round, rng);
        for (final g in decided.games.where((g) => g.outcome.played)) {
          balance[g.white] = (balance[g.white] ?? 0) + 1;
          balance[g.black] = (balance[g.black] ?? 0) - 1;
          last[g.white] = 1;
          last[g.black] = -1;
        }
        e = withRound(e, decided);
      }
    }
  });

  test('proposals are deterministic for the same event and IDs', () {
    var e = field(17);
    final rng = Random(7);
    for (var r = 0; r < 3; r++) {
      e = withRound(
        e,
        decide(proposeRound(e, e.sections.single, ids('a')), rng),
      );
    }
    String shape(Round round) => [
      for (final g in round.games) '${g.board}:${g.white}-${g.black}',
      for (final b in round.byes) 'bye:${b.player}:${b.points}',
    ].join(',');
    expect(
      shape(proposeRound(e, e.sections.single, ids('x'))),
      shape(proposeRound(e, e.sections.single, ids('y'))),
    );
  });

  test('points are conserved: games award two halves, byes their value', () {
    final rng = Random(3);
    var e = field(13, rounds: 4).copy(useTiebreaks: true);
    for (var r = 0; r < 4; r++) {
      e = withRound(
        e,
        decide(proposeRound(e, e.sections.single, ids('k$r')), rng),
      );
    }
    final table = standings(e, e.sections.single);
    final games = e.games.where((g) => g.outcome != Outcome.doubleForfeit);
    final byes = e.sections.single.rounds.expand((r) => r.byes);
    expect(
      table.fold<int>(0, (sum, row) => sum + row.points),
      games.length * 2 + byes.fold<int>(0, (sum, b) => sum + b.points),
    );
    // Ranks are 1-based, non-decreasing, and only shared by identical keys.
    for (var i = 1; i < table.length; i++) {
      final a = table[i - 1], b = table[i];
      expect(b.rank >= a.rank, true);
      final tied = sharePlace(a, b, tiebreaks: true);
      expect(b.rank == a.rank, tied);
    }
  });

  test('round robin names the unavailable player and the reason', () {
    final e = field(4, rounds: 3, format: Format.quad);
    final absent = e.copy(
      players: [
        e.players.first.copy(byes: {1: 1}),
        ...e.players.skip(1),
      ],
    );
    expect(
      () => proposeRound(absent, absent.sections.single, ids('r')),
      throwsA(
        isA<TournamentException>().having(
          (x) => x.message,
          'message',
          allOf(contains('Player 0'), contains('requested bye')),
        ),
      ),
    );
  });

  test('event dates are calendar dates, never normalized', () {
    for (final ok in ['2026-09-29', '2024-02-29', '1999-12-31']) {
      expect(isEventDate(ok), true, reason: ok);
    }
    for (final bad in [
      '',
      'tomorrow',
      '2026-9-29',
      '2026-02-30',
      '2025-02-29',
      '2026-13-01',
      '2026-09-29T10:00',
      ' 2026-09-29',
    ]) {
      expect(isEventDate(bad), false, reason: bad);
    }
    expect(
      () => validateEvent(field(4).copy(date: '2026-02-30')),
      throwsA(isA<TournamentException>()),
    );
  });
}
