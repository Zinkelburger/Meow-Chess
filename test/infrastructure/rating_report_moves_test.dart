import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/membership.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

import '../dbf_reader.dart';

/// Sections A and B, four members each, with the details a report needs.
TournamentController twoSections({int rounds = 2}) {
  final c = TournamentController(SqliteEventRepository(':memory:'));
  c.create('Moves');
  c.importPlayers([
    for (var i = 0; i < 8; i++)
      Player(
        id: 'p$i',
        name: 'Given$i Family$i',
        rating: 1900 - i * 50,
        memberId: '${12000000 + i}',
        state: 'MA',
      ),
  ]);
  c.createSections(
    ['p0', 'p1', 'p2', 'p3'],
    format: Format.swiss,
    name: 'A',
    rounds: rounds,
  );
  c.createSections(
    ['p4', 'p5', 'p6', 'p7'],
    format: Format.swiss,
    name: 'B',
    rounds: rounds,
  );
  c.change(
    'Report details',
    c.event!.copy(
      tdId: '12345678',
      affiliateId: 'A6012345',
      city: 'Boston',
      state: 'MA',
      zip: '02116',
      timeControl: 'G/60 d5',
    ),
  );
  return c;
}

Section named(TournamentController c, String name) =>
    c.event!.sections.firstWhere((s) => s.name == name);

/// Pairs every section that is ready and scores each game for White.
Future<void> playRound(TournamentController c) async {
  c.post(await c.propose(onlyReady: true));
  for (final g in c.event!.games.toList()) {
    if (!g.outcome.resolved) c.recordResult(g.id, Outcome.whiteWin);
  }
}

typedef Rows = List<Map<String, String>>;

(Rows, Rows) decode(Event e) {
  final files = ratingPackage(e);
  return (
    readDbf(files['TSEXPORT.DBF']!).$2,
    readDbf(files['TDEXPORT.DBF']!).$2,
  );
}

Rows section(Rows details, String number) => [
  for (final r in details)
    if (r['D_SEC_NUM'] == number) r,
];

/// Every played cell names an opponent in the same section whose cell for
/// that round names this player back with the opposite result and color;
/// pairing numbers run 1..n without a gap.
void expectConsistent(Rows rows) {
  expect(
    [for (final r in rows) r['D_PAIR_NUM']],
    [for (var i = 1; i <= rows.length; i++) '$i'],
  );
  final cell = RegExp(r'^([WDL])(\d+)([WB])$');
  for (final row in rows) {
    for (final MapEntry(key: column, value: text) in row.entries) {
      if (!column.startsWith('D_RND')) continue;
      final m = cell.firstMatch(text);
      if (m == null) {
        expect(text, matches(r'^[XFBHU]0$'), reason: '$column of $row');
        continue;
      }
      final other = rows[int.parse(m[2]!) - 1][column]!;
      final expected =
          '${{'W': 'L', 'L': 'W', 'D': 'D'}[m[1]]}${row['D_PAIR_NUM']}${m[3] == 'W' ? 'B' : 'W'}';
      expect(other, expected, reason: '$column of $row');
    }
  }
}

Map<String, String> rowOf(Rows rows, String memberId) =>
    rows.singleWhere((r) => r['D_MEM_ID'] == memberId);

Iterable<String> advice(Event e) => [
  for (final i in ratingIssues(e))
    if (!i.blocking) i.message,
];

void main() {
  test('a player moved after round 1 is reported in both sections', () async {
    final c = twoSections();
    addTearDown(c.dispose);
    await playRound(c);
    c.movePlayers(
      ['p3'],
      named(c, 'B').id,
      reason: 'Entered the wrong section',
    );
    await playRound(c);

    expect(ratingPreflight(c.event!), isEmpty);
    final (sections, details) = decode(c.event!);
    expect(
      [
        for (final s in sections)
          (s['S_SEC_NAME'], s['S_TOT_RNDS'], s['S_LST_PAIR']),
      ],
      [('A', '2', '4'), ('B', '2', '5')],
    );
    final a = section(details, '1'), b = section(details, '2');
    expectConsistent(a);
    expectConsistent(b);
    // Round 1 stays in A, where it was played; the later round is unplayed.
    final left = rowOf(a, '12000003');
    expect(left['D_PAIR_NUM'], '4');
    expect(left['D_RND01'], matches(r'^[WL][1-3][WB]$'));
    expect(left['D_RND02'], 'U0');
    // In B the earlier round is unplayed and round 2 is theirs.
    final joined = rowOf(b, '12000003');
    expect(joined['D_RND01'], 'U0');
    expect(joined['D_RND02'], isNot('U0'));
  });

  test('a missed round of a moved player can take a half-point bye', () async {
    final c = twoSections();
    addTearDown(c.dispose);
    await playRound(c);
    c.movePlayers(
      ['p3'],
      named(c, 'B').id,
      reason: 'Entered the wrong section',
    );
    c.reserveBye('p3', 1, 1);
    await playRound(c);
    final (_, details) = decode(c.event!);
    expect(rowOf(section(details, '2'), '12000003')['D_RND01'], 'H0');
    expect(rowOf(section(details, '1'), '12000003')['D_RND02'], 'U0');
  });

  test('sections combined after round 1 report one set of rounds', () async {
    final c = twoSections();
    addTearDown(c.dispose);
    await playRound(c);
    c.movePlayers(
      named(c, 'A').players,
      named(c, 'B').id,
      reason: 'Too few players in A',
    );
    await playRound(c);

    expect(ratingPreflight(c.event!), isEmpty);
    expect(reportedSections(c.event!).map((s) => s.name), ['B']);
    final (sections, details) = decode(c.event!);
    expect(
      [
        for (final s in sections)
          (s['S_SEC_NUM'], s['S_SEC_NAME'], s['S_TOT_RNDS'], s['S_LST_PAIR']),
      ],
      [('1', 'B', '2', '8')],
    );
    expectConsistent(details);
    // Everyone's round 1, wherever it was played, and round 2 are games.
    for (final row in details) {
      expect(row['D_RND01'], matches(r'^[WL]\d[WB]$'), reason: '$row');
      expect(row['D_RND02'], matches(r'^[WL]\d[WB]$'), reason: '$row');
    }
  });

  test('games at another time control stay in the emptied section', () async {
    final c = twoSections();
    addTearDown(c.dispose);
    c.change(
      'Faster section',
      c.event!.copy(
        sections: [
          for (final s in c.event!.sections)
            s.name == 'A' ? s.copy(timeControl: 'G/30 d5') : s,
        ],
      ),
    );
    await playRound(c);
    c.movePlayers(named(c, 'A').players, named(c, 'B').id, reason: 'Combined');
    await playRound(c);

    expect(ratingPreflight(c.event!), isEmpty);
    final (sections, details) = decode(c.event!);
    expect(
      [
        for (final s in sections)
          (s['S_SEC_NAME'], s['S_TIMECTL'], s['S_TOT_RNDS'], s['S_LST_PAIR']),
      ],
      [('A', 'G/30;d5', '1', '4'), ('B', 'G/60;d5', '2', '8')],
    );
    expectConsistent(section(details, '1'));
    expectConsistent(section(details, '2'));
    expect(rowOf(section(details, '2'), '12000000')['D_RND01'], 'U0');
  });

  test('a no-show without a US Chess ID is left out, not a blocker', () async {
    final c = twoSections();
    addTearDown(c.dispose);
    c.savePlayer(c.event!.player('p3').copy(memberId: ''));
    c.post(await c.propose(onlyReady: true));
    for (final g in c.event!.games.toList()) {
      final absent = g.white == 'p3'
          ? Outcome.blackForfeit
          : g.black == 'p3'
          ? Outcome.whiteForfeit
          : Outcome.whiteWin;
      c.recordResult(g.id, absent);
    }
    c.setWithdrawn(['p3'], true);
    await playRound(c);

    expect(ratingPreflight(c.event!), isEmpty);
    expect(
      advice(c.event!),
      contains(
        'A: Given3 Family3 played no games and has no US Chess ID; left out of the report.',
      ),
    );
    final (sections, details) = decode(c.event!);
    expect(sections.first['S_LST_PAIR'], '3');
    final a = section(details, '1');
    expect(a, hasLength(3));
    expectConsistent(a);
    expect(a.where((r) => r['D_RND01'] == 'X0'), hasLength(1));

    // Someone who played still needs an ID.
    c.savePlayer(c.event!.player('p0').copy(memberId: ''));
    expect(
      ratingPreflight(c.event!).single,
      startsWith('US Chess ID missing or invalid for Given0 Family0.'),
    );
  });

  test(
    'a no-show without an ID is still asked for while play goes on',
    () async {
      final c = twoSections();
      addTearDown(c.dispose);
      c.savePlayer(c.event!.player('p3').copy(memberId: ''));
      await playRound(c);
      c.savePlayer(c.event!.player('p7').copy(memberId: ''));
      expect(
        ratingPreflight(c.event!).join('\n'),
        contains('US Chess ID missing or invalid for Given3 Family3, Given7'),
      );
    },
  );

  group('re-entries', () {
    Future<TournamentController> reentered({required bool withdraw}) async {
      final c = twoSections(rounds: 3);
      await playRound(c);
      if (withdraw) c.setWithdrawn(['p0'], true);
      // The re-entry is a new entry of the same member.
      c.savePlayer(
        Player(
          id: 'again',
          name: 'Given0 Family0',
          rating: 1900,
          memberId: '12000000',
          state: 'MA',
          reentryOf: 'p0',
        ),
      );
      c.movePlayers(['again'], named(c, 'A').id);
      await playRound(c);
      await playRound(c);
      return c;
    }

    test('share the US Chess ID and merge into one detail row', () async {
      final c = await reentered(withdraw: true);
      addTearDown(c.dispose);
      expect(ratingPreflight(c.event!), isEmpty);
      final (sections, details) = decode(c.event!);
      expect(sections.first['S_LST_PAIR'], '4');
      final a = section(details, '1');
      expectConsistent(a);
      final row = rowOf(a, '12000000');
      // Round 1 is the first entry's game, not the re-entry's bye.
      expect(row['D_RND01'], matches(r'^[WL]\d[WB]$'));
      expect(
        [row['D_RND02'], row['D_RND03']].where((x) => x != 'U0' && x != 'B0'),
        isNotEmpty,
      );
    });

    test('merge whatever order the roster lists them in', () async {
      // The re-entry listed ahead of the entry it replaced, as a re-sorted
      // roster or a first entry that has left the section leaves them.
      final c = await reentered(withdraw: true);
      addTearDown(c.dispose);
      final e = c.event!, a = named(c, 'A');
      expect(a.players.indexOf('p0'), lessThan(a.players.indexOf('again')));
      final reordered = e.copy(
        sections: [
          for (final s in e.sections)
            s.id == a.id
                ? s.copy(
                    players: [
                      'again',
                      for (final id in s.players)
                        if (id != 'again') id,
                    ],
                  )
                : s,
        ],
      );
      expect(ratingPreflight(reordered), isEmpty);
      expect(advice(reordered).join('\n'), isNot(contains('re-entered while')));
      final (_, details) = decode(reordered);
      final rows = section(details, '1');
      expectConsistent(rows);
      expect(rows, hasLength(4));
      final row = rowOf(rows, '12000000');
      // Where its first-listed entry stands, with the first entry's game.
      expect(row['D_PAIR_NUM'], '1');
      expect(row['D_RND01'], matches(r'^[WL]\d[WB]$'));
      // Same merged results as in roster order, only renumbered.
      final (_, original) = decode(e);
      final before = rowOf(section(original, '1'), '12000000');
      for (final round in ['D_RND01', 'D_RND02', 'D_RND03']) {
        expect(row[round]![0], before[round]![0], reason: round);
      }
    });

    test('that overlap are reported as two rows, with advice', () async {
      // The first entry keeps playing, so both have games in rounds 2 and 3.
      final c = await reentered(withdraw: false);
      addTearDown(c.dispose);
      final played = named(c, 'A').rounds
          .skip(1)
          .any(
            (r) =>
                r.games.any((g) => g.white == 'p0' || g.black == 'p0') &&
                r.games.any((g) => g.white == 'again' || g.black == 'again'),
          );
      expect(played, isTrue);
      expect(ratingPreflight(c.event!), isEmpty);
      expect(advice(c.event!).join('\n'), contains('re-entered while'));
      final (_, details) = decode(c.event!);
      final a = section(details, '1');
      expect(a.where((r) => r['D_MEM_ID'] == '12000000'), hasLength(2));
      expectConsistent(a);
    });

    test('an unrelated entry still cannot take a member\'s ID', () {
      final c = twoSections();
      addTearDown(c.dispose);
      expect(
        () => c.savePlayer(
          Player(id: 'other', name: 'Someone Else', memberId: '12000000'),
        ),
        throwsA(isA<TournamentException>()),
      );
    });
  });

  test(
    'a control with no delay stated is reported with the standard delay',
    () async {
      final c = twoSections();
      addTearDown(c.dispose);
      c.change('Quick', c.event!.copy(timeControl: 'G/10'));
      await playRound(c);
      await playRound(c);
      expect(ratingPreflight(c.event!), isEmpty);
      expect(
        advice(c.event!),
        contains(
          'G/10 has no delay or increment stated; reported as G/10;d2, Quick. Type d0 after the time control if the games had no delay.',
        ),
      );
      var (sections, _) = decode(c.event!);
      expect(
        {for (final s in sections) (s['S_TIMECTL'], s['S_R_SYSTEM'])},
        {('G/10;d2', 'Q')},
      );
      // A stated d0 stays d0, and that is blitz.
      c.change('Blitz', c.event!.copy(timeControl: 'G/10 d0'));
      expect(advice(c.event!).join('\n'), isNot(contains('no delay')));
      (sections, _) = decode(c.event!);
      expect(
        {for (final s in sections) (s['S_TIMECTL'], s['S_R_SYSTEM'])},
        {('G/10;d0', 'D')},
      );
    },
  );

  group('knockout tie-breaks', () {
    Event knockout({required bool twoGames, required String tiebreak}) {
      Game g(String id, String w, String b, int leg, Outcome o) =>
          Game(id: id, white: w, black: b, board: 1, leg: leg, outcome: o);
      final match = twoGames ? 2 : 1;
      return Event(
        id: 'ko',
        name: 'Knockout final',
        date: '2024-03-01',
        timeControl: 'G/60 d5',
        tdId: '12345678',
        affiliateId: 'A6012345',
        city: 'Boston',
        state: 'MA',
        zip: '02116',
        players: [
          for (var i = 0; i < 2; i++)
            Player(
              id: 'k$i',
              name: 'Given$i Family$i',
              memberId: '${12000000 + i}',
              rating: 1800,
              state: 'MA',
            ),
        ],
        sections: [
          Section(
            id: 'final',
            name: 'Final',
            format: Format.knockout,
            doubleGames: twoGames,
            plannedRounds: 2,
            players: const ['k0', 'k1'],
            bracket: Bracket.fromJson({
              'gamesPerMatch': match,
              'tiebreak': tiebreak,
            }),
            rounds: [
              Round(
                number: 1,
                games: [
                  g('m1', 'k0', 'k1', 1, Outcome.draw),
                  if (twoGames) g('m2', 'k1', 'k0', 2, Outcome.draw),
                ],
              ),
              Round(
                number: 2,
                games: [
                  g('t1', 'k0', 'k1', match + 1, Outcome.whiteWin),
                  if (tiebreak != 'armageddon')
                    g('t2', 'k1', 'k0', match + 2, Outcome.draw),
                ],
              ),
            ],
          ),
        ],
      );
    }

    test('are left out with advice; every match game is reported', () {
      for (final twoGames in [true, false]) {
        final e = knockout(twoGames: twoGames, tiebreak: 'rapid');
        expect(ratingPreflight(e, today: DateTime(2024, 3, 2)), isEmpty);
        expect(
          [
            for (final i in ratingIssues(e, today: DateTime(2024, 3, 2)))
              if (!i.blocking) i.message,
          ].join('\n'),
          contains('Final: 2 rapid tie-break games are not in the report.'),
        );
        final files = ratingPackage(e, today: DateTime(2024, 3, 2));
        final s = readDbf(files['TSEXPORT.DBF']!).$2.single;
        expect(s['S_TOT_RNDS'], twoGames ? '2' : '1');
        final rows = readDbf(files['TDEXPORT.DBF']!).$2;
        expectConsistent(rows);
        expect(rows.first['D_RND01'], 'D2W');
        if (twoGames) expect(rows.first['D_RND02'], 'D2B');
        expect(rows.first.containsKey('D_RND03'), isFalse);
      }
    });

    test('an armageddon game is named as unratable time odds', () {
      final e = knockout(twoGames: true, tiebreak: 'armageddon');
      expect(
        [
          for (final i in ratingIssues(e, today: DateTime(2024, 3, 2)))
            if (!i.blocking) i.message,
        ].join('\n'),
        contains(
          '1 armageddon tie-break game is not in the report. Armageddon',
        ),
      );
    });
  });

  group('membership', () {
    Player checked(Player p, {String? expiration, String? status}) => p.copy(
      membershipEvidence: {
        'id': p.memberId,
        'retrievedAt': '2026-01-01T00:00:00Z',
        'expiration': expiration,
        'status': status,
      },
    );

    test('a lapse found by the last check is advice on the report', () async {
      final c = twoSections();
      addTearDown(c.dispose);
      await playRound(c);
      await playRound(c);
      final e = c.event!;
      final lapsed = e.copy(
        players: [
          for (final p in e.players)
            p.id == 'p1'
                ? checked(p, expiration: '2020-01-31', status: 'Expired')
                : p.id == 'p2'
                ? checked(p, expiration: '2099-01-31', status: 'Active')
                : p,
        ],
      );
      expect(ratingPreflight(lapsed), isEmpty);
      final lines = advice(lapsed).where((m) => m.contains('Membership'));
      expect(lines.single, contains('Given1 Family1 (expired 2020-01-31)'));
      expect(lines.single, isNot(contains('Given2')));
    });

    test('statuses that still allow play are not errors', () {
      final p = Player(id: 'x', name: 'X', memberId: '12345678');
      for (final status in [
        'Active',
        'RevokedButCanPlay',
        'NewFromLogin',
        'NewFromImport',
      ]) {
        final summary = MembershipSummary(
          checked(p, expiration: '2099-01-31', status: status),
          eventDate: '2026-01-01',
          now: DateTime(2026, 1, 1),
        );
        expect(summary.severity, MembershipSeverity.normal, reason: status);
      }
      for (final status in ['Suspended', 'Deceased', 'Revoked', 'Inactive']) {
        final summary = MembershipSummary(
          checked(p, expiration: '2099-01-31', status: status),
          eventDate: '2026-01-01',
          now: DateTime(2026, 1, 1),
        );
        expect(summary.severity, MembershipSeverity.error, reason: status);
      }
    });
  });
}
