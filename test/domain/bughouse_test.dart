import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/bughouse.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/standings.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';

/// [pairs] partnerships of two players each, rated 1800 downwards in
/// listed order, plus [extra] unpartnered players at the bottom.
Event build({
  int pairs = 4,
  int extra = 0,
  bool unrated = true,
  bool doubleGames = false,
  List<Round> rounds = const [],
}) {
  final n = pairs * 2 + extra;
  final players = [
    for (var i = 0; i < n; i++)
      Player(id: 'p$i', name: 'Player $i', rating: 1800 - 50 * i),
  ];
  return Event(
    id: 'e',
    name: 'Bughouse night',
    date: '2026-10-10',
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'Bughouse',
        players: [for (final p in players) p.id],
        format: Format.bughouse,
        plannedRounds: 3,
        unrated: unrated,
        doubleGames: doubleGames,
        partners: [
          for (var i = 0; i < pairs; i++) ['p${2 * i}', 'p${2 * i + 1}'],
        ],
        rounds: rounds,
      ),
    ],
  );
}

String Function() ids() {
  var next = 0;
  return () => 'g${next++}';
}

/// The partnerships that met, as "p0p1-p4p5" keys.
Set<String> meetings(Section s, Round r) => {
  for (final g in r.games)
    ([
      partnershipOf(s, g.white)!.join(),
      partnershipOf(s, g.black)!.join(),
    ]..sort()).join('-'),
};

/// Every match won by the side listed first in the section's partnerships.
Round decided(Round r) =>
    r.copy(games: [for (final g in r.games) g.copy(outcome: Outcome.whiteWin)]);

void main() {
  test('a bughouse section must be unrated', () {
    expect(() => validateEvent(build()), returnsNormally);
    expect(
      () => validateEvent(build(unrated: false)),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('unrated'),
        ),
      ),
    );
  });

  test('round 1 pairs partnerships as matches, partners on board 2', () {
    final e = build(), s = e.sections.single;
    final r = proposeRound(e, s, ids());
    expect(r.policy, bughousePolicy);
    expect(r.games, hasLength(2));
    expect(r.byes, isEmpty);
    for (final g in r.games) {
      expect(g.whitePartner, partnerOf(s, g.white));
      expect(g.blackPartner, partnerOf(s, g.black));
      expect({g.white, g.black, g.whitePartner, g.blackPartner}, hasLength(4));
    }
    // Top half against bottom half on average rating: p0/p1 vs p4/p5.
    expect(meetings(s, r), {'p0p1-p4p5', 'p2p3-p6p7'});
    expect(r.games.map((g) => g.board), [1, 2]);
  });

  test('partners share the match points and tie-breaks stay level', () {
    final e0 = build(), s0 = e0.sections.single;
    final r = decided(proposeRound(e0, s0, ids()));
    final e = e0.copy(
      sections: [
        s0.copy(rounds: [r]),
      ],
    );
    final table = standings(e, e.sections.single);
    final points = {for (final row in table) row.player.id: row.points};
    for (final pair in s0.partners) {
      expect(points[pair[0]], points[pair[1]], reason: pair.join('/'));
    }
    expect(points.values.where((p) => p == 2), hasLength(4));
    expect(points.values.where((p) => p == 0), hasLength(4));
    for (final row in table) {
      expect(row.played, 1);
      expect(
        row.buchholz,
        table.firstWhere((x) => x.player.id == row.player.id).buchholz,
      );
    }
    // The partner's opponents are the other side, so both partners carry
    // the same Buchholz.
    for (final pair in s0.partners) {
      final a = table.firstWhere((x) => x.player.id == pair[0]);
      final b = table.firstWhere((x) => x.player.id == pair[1]);
      expect(a.buchholz, b.buchholz);
      expect(a.sonneborn, b.sonneborn);
    }
  });

  test('later rounds pair on match score without repeat meetings', () {
    var e = build();
    final rounds = <Round>[];
    for (var n = 1; n <= 3; n++) {
      final s = e.sections.single;
      final r = proposeRound(e, s, ids());
      expect(r.number, n);
      rounds.add(decided(r));
      e = e.copy(sections: [s.copy(rounds: rounds)]);
    }
    final s = e.sections.single;
    // Round 2: the two winning partnerships meet, as do the two losers.
    final winners = {
      for (final g in rounds[0].games) partnershipOf(s, g.white)!.join(),
    };
    for (final g in rounds[1].games) {
      final w = partnershipOf(s, g.white)!.join(),
          b = partnershipOf(s, g.black)!.join();
      expect(winners.contains(w), winners.contains(b));
    }
    final all = [for (final r in rounds) ...meetings(s, r)];
    expect(all.toSet(), hasLength(all.length), reason: 'no repeat meetings');
    final table = standings(e, s);
    for (final pair in s.partners) {
      expect(
        table.firstWhere((x) => x.player.id == pair[0]).points,
        table.firstWhere((x) => x.player.id == pair[1]).points,
      );
    }
  });

  test(
    'an odd field gives the bye to a partnership; the unpartnered sit out',
    () {
      final e = build(pairs: 3, extra: 1), s = e.sections.single;
      final r = proposeRound(e, s, ids());
      expect(r.games, hasLength(1));
      final noPartner = r.byes.where((b) => b.reason == 'No partner').toList();
      expect(noPartner.map((b) => b.player), ['p6']);
      expect(noPartner.single.points, 0);
      final full = r.byes.where((b) => b.allocated).toList();
      expect(full, hasLength(2));
      expect(full.map((b) => b.points), [2, 2]);
      expect(partnershipOf(s, full[0].player), contains(full[1].player));
      // The lowest partnership takes the bye (28L2).
      expect(full.map((b) => b.player).toSet(), {'p4', 'p5'});
      expect(r.explanations.join(' '), contains('Player 4 / Player 5'));
    },
  );

  test(
    'double games play the match twice with colors and partners swapped',
    () {
      final e = build(pairs: 3, doubleGames: true), s = e.sections.single;
      final r = proposeRound(e, s, ids());
      expect(r.games, hasLength(2));
      final (a, b) = (r.games[0], r.games[1]);
      expect(a.board, b.board);
      expect(
        (b.white, b.black, b.whitePartner, b.blackPartner),
        (a.black, a.white, a.blackPartner, a.whitePartner),
      );
      expect(r.byes.where((x) => x.allocated).map((x) => x.points), [4, 4]);
    },
  );

  test('a requested bye or withdrawal by either partner sits the pair out', () {
    final base = build(pairs: 3);
    final e = base.copy(
      players: [
        for (final p in base.players) p.id == 'p3' ? p.copy(byes: {1: 1}) : p,
      ],
    );
    final r = proposeRound(e, e.sections.single, ids());
    final pair = r.byes.where((b) => b.points == 1).toList();
    expect(pair.map((b) => b.player).toSet(), {'p2', 'p3'});
    expect(pair.map((b) => b.reason).toSet(), {
      'Requested bye',
      "Partner's requested bye",
    });
    expect(r.games, hasLength(1));
  });

  test('the rating report leaves the section out and says so', () {
    final e = build();
    expect(reportedSections(e), isEmpty);
    final note = ratingIssues(e).where(
      (i) => i.message.contains('Bughouse section left out of the report'),
    );
    expect(note, hasLength(1));
    expect(note.single.blocking, isFalse);
  });

  test('pairing refuses a section with no partnerships', () {
    final e = build(pairs: 0, extra: 4);
    expect(
      () => proposeRound(e, e.sections.single, ids()),
      throwsA(
        isA<TournamentException>().having(
          (x) => x.message,
          'message',
          contains('Pair everyone up first'),
        ),
      ),
    );
  });
}
