import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/prizes.dart';
import 'package:meow_chess/domain/standings.dart';
import 'package:meow_chess/domain/team_standings.dart';

/// Players are single letters; `teams` gives each a school. A game is
/// `white-black=result` with results 1, 0 or ½.
Event teamEvent(
  List<List<String>> rounds,
  Map<String, String> teams, {
  TeamAwards? awards = const TeamAwards(),
  List<Json> prizes = const [],
  bool useTiebreaks = true,
  Set<String> withdrawn = const {},
}) {
  final game = RegExp(r'^([A-Z])-([A-Z])=(.+)$');
  final ids = <String>{...teams.keys};
  for (final round in rounds) {
    for (final entry in round) {
      final m = game.firstMatch(entry)!;
      ids.addAll([m[1]!, m[2]!]);
    }
  }
  final sorted = ids.toList()..sort();
  var board = 0;
  return Event(
    id: 'team-event',
    name: 'Scholastic',
    date: '2026-10-09',
    useTiebreaks: useTiebreaks,
    players: [
      for (final id in sorted)
        Player(
          id: id,
          name: id,
          rating: 1000,
          team: teams[id] ?? '',
          withdrawn: withdrawn.contains(id),
        ),
    ],
    sections: [
      Section(
        id: 's',
        name: 'K-12',
        players: sorted,
        plannedRounds: rounds.length,
        prizes: {'list': prizes, if (awards != null) 'teams': awards.toJson()},
        rounds: [
          for (final (i, round) in rounds.indexed)
            Round(
              number: i + 1,
              games: [
                for (final entry in round)
                  if (game.firstMatch(entry) case final m?)
                    Game(
                      id: 'g${++board}',
                      white: m[1]!,
                      black: m[2]!,
                      board: board,
                      outcome: switch (m[3]!) {
                        '1' => Outcome.whiteWin,
                        '0' => Outcome.blackWin,
                        '½' => Outcome.draw,
                        _ => throw ArgumentError(entry),
                      },
                    ),
              ],
            ),
        ],
      ),
    ],
  );
}

/// Lincoln (A–E) against Grant (F–J), two rounds. Final scores:
/// A 2, B 1½, C 1½, E 1, D 0 · J 2, I 1, F ½, H ½, G 0.
const twoSchools = [
  ['A-F=1', 'B-G=1', 'C-H=½', 'D-I=0', 'E-J=0'],
  ['A-G=1', 'B-F=½', 'C-I=1', 'D-J=0', 'E-H=1'],
];
const schools = {
  'A': 'Lincoln',
  'B': 'Lincoln',
  'C': 'lincoln ', // same school, spelled differently
  'D': 'Lincoln',
  'E': 'Lincoln',
  'F': 'Grant',
  'G': 'Grant',
  'H': 'Grant',
  'I': 'Grant',
  'J': 'Grant',
};

TeamStanding team(List<TeamStanding> rows, String name) =>
    rows.firstWhere((t) => t.team == name);

/// A synthetic team row with 12.3.3 tie-break totals [mm, solk, sb, cum, coin].
TeamStanding synthetic(String name, int score, List<int> values) =>
    TeamStanding(
      team: name,
      members: const [],
      score: score,
      eligible: true,
      method: TeamScoring.topN,
      tiebreaks: [
        for (final (i, m) in [
          ...teamTiebreakMethods,
          TiebreakMethod.coinFlip,
        ].indexed)
          TiebreakValue(m, values[i]),
      ],
    );

void main() {
  group('Scholastic Regulations 10.2.1: team score is the top N', () {
    test('top 4 (Spring Nationals) sums the four best scores', () {
      final e = teamEvent(twoSchools, schools);
      final rows = teamStandings(e, e.sections.single);
      expect(rows.map((t) => t.team), ['Lincoln', 'Grant']);
      final lincoln = team(rows, 'Lincoln');
      expect(lincoln.score, 12); // 2 + 1½ + 1½ + 1, in half-points
      expect(lincoln.scoreText, '6');
      // B and C tie on 1½; the posted tie-breaks order them.
      expect(
        lincoln.counting.map((m) => m.player.id),
        unorderedEquals(['A', 'B', 'C', 'E']),
      );
      expect(lincoln.members.last.player.id, 'D');
      expect(lincoln.members.last.counts, isFalse);
      expect(team(rows, 'Grant').score, 8); // 2 + 1 + ½ + ½
      expect(lincoln.rank, 1);
      expect(team(rows, 'Grant').rank, 2);
    });

    test('top 3 (Grade Nationals, blitz) sums the three best', () {
      final e = teamEvent(
        twoSchools,
        schools,
        awards: const TeamAwards(counting: 3),
      );
      final rows = teamStandings(e, e.sections.single);
      expect(team(rows, 'Lincoln').score, 10); // 2 + 1½ + 1½
      expect(team(rows, 'Grant').score, 7); // 2 + 1 + ½
      expect(team(rows, 'Grant').counting, hasLength(3));
    });

    test('team labels match like team-mate avoidance: trimmed, any case', () {
      final e = teamEvent(twoSchools, schools);
      expect(sectionTeams(e, e.sections.single), ['Lincoln', 'Grant']);
    });

    test('no team awards means no team standings', () {
      final e = teamEvent(twoSchools, schools, awards: null);
      expect(teamStandings(e, e.sections.single), isEmpty);
      expect(TeamAwards.of(e.sections.single), isNull);
    });
  });

  group('10.2.2 / 5.6.1: eligibility', () {
    // X: A 2, B 1½. Y: C ½ alone. D has no school.
    final rounds = [
      ['A-C=1', 'B-D=1'],
      ['A-D=1', 'B-C=½'],
    ];
    const labels = {'A': 'X', 'B': 'X', 'C': 'Y'};

    test('a team short of the counting number still scores its players', () {
      final e = teamEvent(rounds, labels);
      final x = team(teamStandings(e, e.sections.single), 'X');
      expect(x.counting, hasLength(2));
      expect(x.score, 7);
      expect(x.eligible, isTrue);
      expect(x.rank, 1);
    });

    test('a one-player team is listed but ineligible, after the others', () {
      final e = teamEvent(rounds, labels);
      final rows = teamStandings(e, e.sections.single);
      expect(rows.map((t) => t.team), ['X', 'Y']);
      expect(rows.last.eligible, isFalse);
      expect(rows.last.rank, 0);
      expect(rows.last.score, 1);
    });

    test('players without a team label are on no team', () {
      final e = teamEvent(rounds, labels);
      final rows = teamStandings(e, e.sections.single);
      expect(
        rows.expand((t) => t.members).map((m) => m.player.id),
        isNot(contains('D')),
      );
    });

    test('a withdrawn player still counts for the scores they earned', () {
      final e = teamEvent(rounds, labels, withdrawn: {'B'});
      final x = team(teamStandings(e, e.sections.single), 'X');
      expect(x.score, 7);
      expect(x.counting.map((m) => m.player.id), ['A', 'B']);
    });
  });

  group('12.3.3: team tie-breaks', () {
    final levels = [
      'total Modified Median',
      'total Solkoff',
      'total Sonneborn-Berger',
      'total Cumulative',
      'coin flip',
    ];
    for (final (level, name) in levels.indexed) {
      test('$name decides a tie the earlier levels leave', () {
        final low = [10, 20, 30, 40, 50];
        final high = [...low]..[level] += 1;
        final rows = rankTeams([
          synthetic('Adams', 8, low),
          synthetic('Byrd', 8, high),
        ]);
        expect(rows.map((t) => t.team), ['Byrd', 'Adams']);
        expect(rows.map((t) => t.rank), [1, 2]);
      });
    }

    test('team score comes before every tie-break', () {
      final rows = rankTeams([
        synthetic('Adams', 9, [0, 0, 0, 0, 0]),
        synthetic('Byrd', 8, [99, 99, 99, 99, 99]),
      ]);
      expect(rows.first.team, 'Adams');
    });

    test('equal on every value shares the place', () {
      final rows = rankTeams([
        synthetic('Adams', 8, [1, 2, 3, 4, 5]),
        synthetic('Byrd', 8, [1, 2, 3, 4, 5]),
        synthetic('Cole', 6, [1, 2, 3, 4, 5]),
      ]);
      expect(rows.map((t) => t.rank), [1, 1, 3]);
    });

    test('totals are the counting players\' own tie-breaks', () {
      final e = teamEvent(
        twoSchools,
        schools,
        awards: const TeamAwards(counting: 3),
      );
      final s = e.sections.single;
      final own = {
        for (final r in standings(e, s, tiebreaks: teamTiebreakMethods))
          r.player.id: r.tiebreaks,
      };
      for (final t in teamStandings(e, s)) {
        for (final (i, m) in teamTiebreakMethods.indexed) {
          expect(
            t.tiebreaks[i].value,
            t.counting.fold(0, (sum, c) => sum + own[c.player.id]![i].value),
            reason: '${t.team} ${m.label}',
          );
        }
        expect(t.tiebreaks.last.method, TiebreakMethod.coinFlip);
      }
    });

    test('a dead heat on every method falls to the recorded coin flip', () {
      // X and Y each score 1; every tie-break total is equal.
      final e = teamEvent(
        [
          ['A-C=1', 'B-D=0'],
        ],
        {'A': 'X', 'B': 'X', 'C': 'Y', 'D': 'Y'},
      );
      final rows = teamStandings(e, e.sections.single);
      expect(rows.map((t) => t.score), [2, 2]);
      for (var i = 0; i < teamTiebreakMethods.length; i++) {
        expect(rows[0].tiebreaks[i].value, rows[1].tiebreaks[i].value);
      }
      expect(rows.map((t) => t.rank), [1, 2]);
      expect(
        rows[0].tiebreaks.last.value,
        greaterThan(rows[1].tiebreaks.last.value),
      );
    });
  });

  group('31A1 Rollins scoring', () {
    test('each player earns the field size minus their place', () {
      // Places shared on points (no tie-breaks): A, J 1st; B, C 3rd;
      // E, I 5th; F, H 7th; D, G 9th. Ten players.
      final e = teamEvent(
        twoSchools,
        schools,
        useTiebreaks: false,
        awards: const TeamAwards(counting: 3, method: TeamScoring.rollins),
      );
      final rows = teamStandings(e, e.sections.single);
      final lincoln = team(rows, 'Lincoln');
      expect(lincoln.counting.map((m) => m.points), [9, 7, 7]);
      expect(lincoln.score, 23);
      expect(lincoln.scoreText, '23');
      final grant = team(rows, 'Grant');
      expect(grant.counting.map((m) => m.points), [9, 5, 3]);
      expect(grant.score, 17);
      expect(rows.first.team, 'Lincoln');
    });
  });

  group('settings', () {
    test('read from the prize table and checked', () {
      expect(
        TeamAwards.fromJson({'counting': 3, 'method': 'rollins'})!.toJson(),
        {'counting': 3, 'method': 'rollins', 'minPlayers': 2},
      );
      expect(
        () => TeamAwards.fromJson({'counting': 0}),
        throwsA(isA<TournamentException>()),
      );
      expect(
        () => TeamAwards.fromJson({'method': 'median'}),
        throwsA(isA<TournamentException>()),
      );
      expect(const TeamAwards().summary, 'Top 4 scores count');
    });

    test('the prize table editor keeps the team settings', () {
      final json = {
        'list': <Json>[],
        'teams': const TeamAwards(counting: 3).toJson(),
      };
      final table = PrizeTable.fromJson(json).copy(basedOn: 20);
      expect(table.toJson()['teams'], json['teams']);
    });

    test('withTeamAwards sets and removes the key only', () {
      final e = teamEvent(
        twoSchools,
        schools,
        awards: null,
        prizes: [
          {'id': 'p1', 'kind': 'place', 'cents': 1000},
        ],
      );
      final on = withTeamAwards(e.sections.single, const TeamAwards());
      expect(TeamAwards.of(on)!.counting, 4);
      final off = withTeamAwards(on, null);
      expect(off.prizes.containsKey('teams'), isFalse);
      expect(off.prizes['list'], hasLength(1));
    });

    test('offered for a Swiss with at least two schools', () {
      final e = teamEvent(twoSchools, schools, awards: null);
      expect(offersTeamAwards(e, e.sections.single), isTrue);
      final one = teamEvent(twoSchools, {'A': 'Lincoln'}, awards: null);
      expect(offersTeamAwards(one, one.sections.single), isFalse);
      final quads = e.sections.single.copy(format: Format.quad);
      expect(offersTeamAwards(e, quads), isFalse);
    });
  });

  group('team prizes', () {
    final teamPrizes = <Json>[
      {'id': 't1', 'kind': 'team', 'place': 1, 'cents': 10000, 'trophy': true},
      {'id': 't2', 'kind': 'team', 'place': 2, 'cents': 5000, 'trophy': true},
      {'id': 'p1', 'kind': 'place', 'place': 1, 'trophy': true},
    ];

    test('individual allocation leaves team prizes alone', () {
      final e = teamEvent(twoSchools, schools, prizes: teamPrizes);
      final a = allocatePrizes(e, e.sections.single);
      expect(a.lines.map((l) => l.prize.id), ['p1']);
      expect(a.awards.single.trophies.single.id, 'p1');
    });

    test('teams take their places', () {
      final e = teamEvent(twoSchools, schools, prizes: teamPrizes);
      final a = allocateTeamPrizes(e, e.sections.single);
      expect(a.lines.map((l) => l.prize.id), ['t1', 't2']);
      expect(a.lines[0].trophyTeam, 'Lincoln');
      expect(a.lines[0].cash, {'Lincoln': 10000});
      expect(a.lines[1].trophyTeam, 'Grant');
      expect(a.teamCents, {'Lincoln': 10000, 'Grant': 5000});
      expect(a.paidCents, 15000);
      expect(Prize.fromJson(teamPrizes.first).title, '1st team');
    });

    test('teams tied on score split the cash; tie-breaks place trophies', () {
      final e = teamEvent(
        [
          ['A-C=1', 'B-D=0'],
        ],
        {'A': 'X', 'B': 'X', 'C': 'Y', 'D': 'Y'},
        prizes: teamPrizes,
      );
      final a = allocateTeamPrizes(e, e.sections.single);
      expect(a.teamCents, {'X': 7500, 'Y': 7500});
      expect(a.lines[0].pooledWith, ['t2']);
      final first = a.standings.first.team;
      expect(a.lines[0].trophyTeam, first);
      expect(
        a.explanations,
        contains(
          '$first takes the 1st team trophy on team tie-breaks (12.3.3).',
        ),
      );
    });

    test('a one-player team wins nothing', () {
      final e = teamEvent(
        [
          ['A-C=1', 'B-D=1'],
        ],
        {'A': 'X', 'B': 'X', 'C': 'Y'},
        prizes: teamPrizes,
      );
      final a = allocateTeamPrizes(e, e.sections.single);
      expect(a.lines[0].trophyTeam, 'X');
      expect(a.lines[1].trophyTeam, isNull);
      expect(a.lines[1].note, 'No eligible team');
      expect(a.explanations.first, contains('needs 2 for a team prize'));
    });

    test('team prizes with team awards off are not awarded', () {
      final e = teamEvent(
        twoSchools,
        schools,
        awards: null,
        prizes: teamPrizes,
      );
      final a = allocateTeamPrizes(e, e.sections.single);
      expect(a.lines.every((l) => l.cash.isEmpty), isTrue);
      expect(a.lines.first.note, 'Team awards are off');
    });
  });
}
