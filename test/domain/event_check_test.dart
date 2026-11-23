import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/event_check.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/pairing_quality.dart';
import 'package:meow_chess/domain/prizes.dart';

Player player(int i, {String team = '', String memberId = ''}) => Player(
  id: 'p$i',
  name: 'Player $i',
  rating: 1900 - i * 20,
  team: team,
  memberId: memberId,
);

Game game(int round, int board, int white, int black, [Outcome? outcome]) =>
    Game(
      id: 'r$round-b$board',
      white: 'p$white',
      black: 'p$black',
      board: board,
      outcome: outcome ?? Outcome.whiteWin,
    );

Event event(
  List<Round> rounds, {
  int players = 6,
  List<Player>? roster,
  Section Function(Section)? section,
  List<Section> more = const [],
}) {
  final people = roster ?? [for (var i = 0; i < players; i++) player(i)];
  final open = Section(
    id: 's',
    name: 'Open',
    players: [for (final p in people.take(players)) p.id],
    plannedRounds: 5,
    rounds: rounds,
  );
  return Event(
    id: 'e',
    name: 'Fall Open',
    date: '2026-11-21',
    players: people,
    sections: [section?.call(open) ?? open, ...more],
  );
}

CheckLine line(EventCheck check, String title) =>
    check.checks.singleWhere((c) => c.title == title);

void main() {
  test('a clean event finds nothing and says what it checked', () {
    final e = event([
      Round(
        number: 1,
        games: [game(1, 1, 0, 3), game(1, 2, 4, 1), game(1, 3, 2, 5)],
      ),
    ]);
    validateEvent(e);
    final check = checkEvent(e);
    expect(check.findings, isEmpty);
    expect(
      line(check, 'Players paired against each other twice').verdict,
      'Clear: 3 pairings checked',
    );
    expect(
      line(check, 'Half-point byes within the announced limit').verdict,
      'Not checked: no section limits half-point byes',
    );
    expect(check.report(), contains('Nothing found.'));
    expect(check.report(), contains('Checked'));
  });

  test('before any round, the pairing checks say they did not run', () {
    final check = checkEvent(event(const []));
    expect(check.findings, isEmpty);
    expect(
      line(check, 'Everyone has a game or a bye').verdict,
      'Not checked: no Swiss section has a round up',
    );
    expect(line(check, 'The same color three games in a row').ran, isFalse);
  });

  test('a rematch names both players and the round they first met', () {
    final e = event([
      Round(number: 1, games: [game(1, 1, 0, 1), game(1, 2, 2, 3)]),
      Round(
        number: 2,
        games: [game(2, 1, 1, 0, Outcome.unreported), game(2, 2, 3, 4)],
        byes: const [ByeAward('p2', 2, 'odd', allocated: true)],
      ),
    ], players: 5);
    validateEvent(e);
    final found = line(
      checkEvent(e),
      'Players paired against each other twice',
    ).findings.single;
    expect(found.level, CheckLevel.look);
    expect(found.round, 2);
    expect(found.players, ['p1', 'p0']);
    expect(found.message, contains('they played in round 1'));
  });

  test('a forfeit is not a meeting, so the two may be paired again', () {
    final e = event([
      Round(
        number: 1,
        games: [game(1, 1, 0, 1, Outcome.whiteForfeit), game(1, 2, 2, 3)],
      ),
      Round(number: 2, games: [game(2, 1, 1, 0), game(2, 2, 3, 2)]),
    ], players: 4);
    final found = line(
      checkEvent(e),
      'Players paired against each other twice',
    ).findings;
    expect(found.single.players, ['p3', 'p2']);
  });

  test('a third game with one color is found; a forfeit breaks nothing', () {
    final e = event([
      Round(number: 1, games: [game(1, 1, 0, 1), game(1, 2, 2, 3)]),
      Round(number: 2, games: [game(2, 1, 0, 2), game(2, 2, 1, 3)]),
      Round(number: 3, games: [game(3, 1, 0, 3), game(3, 2, 1, 2)]),
    ], players: 4);
    final found = line(
      checkEvent(e),
      'The same color three games in a row',
    ).findings;
    expect(found.map((f) => f.players.single), ['p0', 'p3']);
    expect(found.first.message, contains('White for the third game in a row'));

    // The same three rounds with round 2 forfeited: p0's colors are W, W
    // and p3's B, B, so nobody has three.
    final forfeited = event([
      e.sections.single.rounds[0],
      Round(
        number: 2,
        games: [
          game(2, 1, 0, 2, Outcome.whiteForfeit),
          game(2, 2, 1, 3, Outcome.whiteForfeit),
        ],
      ),
      e.sections.single.rounds[2],
    ], players: 4);
    expect(
      line(
        checkEvent(forfeited),
        'The same color three games in a row',
      ).findings,
      isEmpty,
    );
  });

  test('a player left out of the current round is found', () {
    final e = event([
      Round(number: 1, games: [game(1, 1, 0, 1), game(1, 2, 2, 3)]),
    ], players: 5);
    final found = line(checkEvent(e), 'Everyone has a game or a bye').findings;
    expect(found.single.players, ['p4']);
    expect(
      found.single.message,
      'Open: Player 4 has no game and no bye in round 1.',
    );
  });

  test('a withdrawn player still on a board is found', () {
    final roster = [for (var i = 0; i < 4; i++) player(i)]
      ..[3] = player(3).copy(withdrawn: true);
    final e = event(
      [
        Round(
          number: 1,
          games: [
            game(1, 1, 0, 1, Outcome.unreported),
            game(1, 2, 2, 3, Outcome.unreported),
          ],
        ),
      ],
      roster: roster,
      players: 4,
    );
    final found = line(checkEvent(e), 'Withdrawn players on a board').findings;
    expect(found.single.players, ['p3']);
    expect(found.single.message, contains('board 2 in round 1'));
  });

  test('a second full-point bye and too many half-point byes are found', () {
    final e = event(
      [
        Round(
          number: 1,
          games: [game(1, 1, 0, 1)],
          byes: const [
            ByeAward('p2', 2, 'odd', allocated: true),
            ByeAward('p3', 1, 'requested'),
          ],
        ),
        Round(
          number: 2,
          games: [game(2, 1, 1, 0)],
          byes: const [
            ByeAward('p2', 2, 'odd', allocated: true),
            ByeAward('p3', 1, 'requested'),
          ],
        ),
      ],
      players: 4,
      section: (s) => s.copy(byeRules: const ByePolicy(maxHalfByes: 1)),
    );
    validateEvent(e);
    final check = checkEvent(e);
    expect(
      line(
        check,
        'A second full-point bye for the same player',
      ).findings.single.message,
      'Open: Player 2 has the full-point bye in round 2 and already had it '
      'in round 1.',
    );
    expect(
      line(
        check,
        'Half-point byes within the announced limit',
      ).findings.single.message,
      'Open: Player 3 has 2 half-point byes; the section allows 1.',
    );
  });

  test('an earlier round missing results is found, not the current one', () {
    final e = event([
      Round(
        number: 1,
        games: [game(1, 1, 0, 1, Outcome.unreported), game(1, 2, 2, 3)],
      ),
      Round(
        number: 2,
        games: [
          game(2, 1, 0, 2, Outcome.unreported),
          game(2, 2, 1, 3, Outcome.unreported),
        ],
      ),
    ], players: 4);
    final found = line(
      checkEvent(e),
      'Results missing from an earlier round',
    ).findings;
    expect(
      found.single.message,
      'Open: round 1 is missing 1 result and round 2 is already up.',
    );
  });

  test('team-mates and do-not-pair requests on a board are found', () {
    final roster = [
      player(0, team: 'Lincoln'),
      player(1, team: 'lincoln '),
      player(2).copy(avoid: {'p3'}),
      player(3),
    ];
    final e = event(
      [
        Round(number: 1, games: [game(1, 1, 0, 1), game(1, 2, 2, 3)]),
      ],
      roster: roster,
      players: 4,
      section: (s) => s.copy(avoidTeammates: true),
    );
    final check = checkEvent(e);
    final mates = line(check, 'Team-mates paired against each other');
    expect(mates.findings.single.level, CheckLevel.note);
    expect(mates.findings.single.message, contains('(Lincoln)'));
    expect(line(check, 'Do-not-pair requests').findings.single.players, [
      'p2',
      'p3',
    ]);
    // The notes sort after what needs a look.
    expect(check.findings.last.level, CheckLevel.note);
  });

  test('a rating outside the section range is found until excepted', () {
    Section ranged(Section s) => s.copy(ratingCeiling: 1890);
    final e = event(const [], players: 4, section: ranged);
    final title = 'Ratings inside each section\'s range';
    expect(line(checkEvent(e), title).findings.single.players, ['p0']);
    final excepted = event(
      const [],
      players: 4,
      section: (s) =>
          ranged(s).copy(rangeExceptions: const {'p0': 'Playing up'}),
    );
    expect(line(checkEvent(excepted), title).findings, isEmpty);
  });

  test('playing up into an open section too far is found', () {
    final low = Player(id: 'low', name: 'Low Rated', rating: 1500);
    final e = event(
      const [],
      players: 5,
      roster: [for (var i = 0; i < 4; i++) player(i), low],
      more: [
        Section(
          id: 'u',
          name: 'U1800',
          players: [],
          plannedRounds: 5,
          ratingCeiling: 1800,
        ),
      ],
    ).copy(playUpLimit: 200);
    final ranges = line(checkEvent(e), 'Ratings inside each section\'s range');
    expect(ranges.skipped, isNull);
    expect(ranges.findings.single.players, ['low']);
  });

  test('a prize nobody entered can win is found before round 1', () {
    final e = event(
      const [],
      players: 4,
      section: (s) => s.copy(
        prizes: PrizeTable.fromJson({
          'list': [
            {'id': '1', 'kind': 'place', 'place': 1, 'cents': 10000},
            // Everyone is rated 1840 or more: a mistyped range.
            {'id': 'u', 'kind': 'under', 'max': 1200, 'cents': 5000},
            {'id': 'v', 'kind': 'under', 'max': 1870, 'cents': 5000},
          ],
        }),
      ),
    );
    validateEvent(e);
    expect(allocatePrizes(e, e.sections.single).eligible, {
      '1': 4,
      'u': 0,
      'v': 2,
    });
    final prizes = line(checkEvent(e), 'Prizes somebody can win');
    expect(prizes.examined, '3 prizes');
    expect(
      prizes.findings.single.message,
      'Open: nobody entered can win 1st Under 1200. Check its rating range '
      'and the players it names.',
    );
    expect(
      line(checkEvent(event(const [])), 'Prizes somebody can win').verdict,
      'Not checked: no section with players announces prizes',
    );
  });

  test('one person in two sections is found by ID, then by name', () {
    final roster = [
      player(0, memberId: '12345678'),
      player(1),
      Player(id: 'x0', name: 'Someone Else', memberId: '12345678'),
      Player(id: 'x1', name: 'PLAYER 1'),
      Player(id: 'x2', name: 'Not Placed'),
    ];
    final e = event(
      const [],
      roster: roster,
      players: 2,
      more: [
        Section(id: 'u', name: 'U1600', players: const ['x0', 'x1']),
      ],
    );
    validateEvent(e);
    final check = checkEvent(e);
    final twice = line(check, 'The same person entered twice').findings;
    expect(twice.map((f) => f.message), [
      'Someone Else is entered in Open and in U1600.',
      'PLAYER 1 is entered in Open and in U1600 (same name; no ID to tell '
          'them apart).',
    ]);
    expect(
      line(check, 'Players in no section').findings.single.message,
      '1 player is in no section: Not Placed.',
    );
    // One section's check leaves the event-wide checks out.
    final one = checkEvent(e, sectionId: 'u');
    expect(one.scope, 'U1600');
    expect(
      one.checks.map((c) => c.title),
      isNot(contains('Players in no section')),
    );
  });

  test('a section waiting to be paired while others are ahead is noted', () {
    final e = event(
      [
        Round(number: 1, games: [game(1, 1, 0, 1), game(1, 2, 2, 3)]),
        Round(
          number: 2,
          games: [
            game(2, 1, 0, 2, Outcome.unreported),
            game(2, 2, 1, 3, Outcome.unreported),
          ],
        ),
      ],
      roster: [
        for (var i = 0; i < 4; i++) player(i),
        Player(id: 'x0', name: 'Ann'),
        Player(id: 'x1', name: 'Bo'),
      ],
      players: 4,
      more: [
        Section(
          id: 'u',
          name: 'U1600',
          players: const ['x0', 'x1'],
          plannedRounds: 4,
          boardStart: 10,
          rounds: [
            Round(
              number: 1,
              games: const [
                Game(
                  id: 'u1',
                  white: 'x0',
                  black: 'x1',
                  board: 10,
                  outcome: Outcome.draw,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    validateEvent(e);
    expect(
      line(
        checkEvent(e),
        'A section waiting to be paired',
      ).findings.single.message,
      'U1600 has finished round 1 and round 2 is not paired; other sections '
      'are on round 2.',
    );
  });

  test('a section that is gone is refused by name', () {
    expect(
      () => checkEvent(event(const []), sectionId: 'gone'),
      throwsA(isA<TournamentException>()),
    );
  });

  group('pairing quality', () {
    test('counts score groups, colors due and repeats round by round', () {
      final e = event([
        // Round 1: p0, p1, p2 win with White.
        Round(
          number: 1,
          games: [game(1, 1, 0, 3), game(1, 2, 1, 4), game(1, 3, 2, 5)],
        ),
        // Round 2: one board inside the 1-point group, one across groups
        // (p2 with 1 meets p3 with 0), one inside the 0 group. p0 gets
        // White again although Black was due.
        Round(
          number: 2,
          games: [
            game(2, 1, 0, 1),
            game(2, 2, 3, 2, Outcome.blackWin),
            game(2, 3, 5, 4),
          ],
        ),
        // Round 3 repeats round 1's top board, and gives p0 a third White.
        Round(
          number: 3,
          games: [
            game(3, 1, 0, 3, Outcome.unreported),
            game(3, 2, 5, 1, Outcome.unreported),
            game(3, 3, 4, 2, Outcome.unreported),
          ],
        ),
      ]);
      validateEvent(e);
      final q = pairingQuality(e, e.sections.single)!;
      final r1 = q.rounds[0], r2 = q.rounds[1], r3 = q.rounds[2];
      expect(r1.sameScore, (count: 3, of: 3));
      expect(r1.colorsDue, (count: 0, of: 0));
      expect(r2.sameScore, (count: 2, of: 3));
      expect(r2.floats, 2);
      // Everyone had a color due in round 2; p0 and p1 did not get it.
      expect(r2.colorsDue, (count: 4, of: 6));
      expect(r2.imbalance, (count: 2, of: 6));
      expect(r3.rematches, (count: 1, of: 3));
      expect(r3.thirdInRow, (count: 1, of: 6));
      expect(r3.teammates, isNull);
      expect(q.total.boards, 9);
      expect(q.total.rematches, (count: 1, of: 9));
      expect(q.note, isEmpty);
    });

    test('is not offered for a round robin or before round 1', () {
      final e = event(const []);
      expect(pairingQuality(e, e.sections.single), isNull);
      final rr = event(
        [
          Round(number: 1, games: [game(1, 1, 0, 1), game(1, 2, 2, 3)]),
        ],
        players: 4,
        section: (s) => s.copy(format: Format.roundRobin),
      );
      expect(pairingQuality(rr, rr.sections.single), isNull);
    });

    test('a real paired event has no repeats and no third color', () {
      var e = event(const [], players: 16);
      var next = 0;
      for (var round = 1; round <= 4; round++) {
        final s = e.sections.single;
        final r = proposeRound(e, s, () => 'g${next++}');
        e = e.copy(
          sections: [
            s.copy(
              rounds: [
                ...s.rounds,
                r.copy(
                  games: [
                    for (final g in r.games)
                      g.copy(
                        // The higher-rated player wins, with a few draws.
                        outcome: g.board % 4 == 0
                            ? Outcome.draw
                            : e.player(g.white).rating >
                                  e.player(g.black).rating
                            ? Outcome.whiteWin
                            : Outcome.blackWin,
                      ),
                  ],
                ),
              ],
            ),
          ],
        );
      }
      validateEvent(e);
      final q = pairingQuality(e, e.sections.single)!;
      expect(q.total.rematches.count, 0);
      expect(q.total.thirdInRow.count, 0);
      expect(checkEvent(e).findings, isEmpty);
    });
  });
}
