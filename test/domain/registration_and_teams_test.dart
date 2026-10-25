import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/acceleration.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/standings.dart';
import 'package:meow_chess/domain/teams.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/infrastructure/roster_import.dart';
import 'package:meow_chess/infrastructure/team_reports.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import '../support.dart';
import '../infrastructure/rating_contract_test.dart' show exportFixture, today;
import 'swiss_tools_test.dart' show eventWith;

void main() {
  test(
    'acceleration splits first-round groups without awarding competition points',
    () {
      final e = eventWith(8), original = e.sections.single;
      final s = original.copy(
        acceleration: topHalfAcceleration(e, original, rounds: 2),
      );
      expect(s.acceleration.keys, ['p0', 'p1', 'p2', 'p3']);
      var id = 0;
      final round = proposeRound(e.copy(sections: [s]), s, () => '${id++}');
      expect(round.games.map((g) => {g.white, g.black}), [
        {'p0', 'p2'},
        {'p1', 'p3'},
        {'p4', 'p6'},
        {'p5', 'p7'},
      ]);
      expect(
        standings(e.copy(sections: [s]), s).every((r) => r.points == 0),
        isTrue,
      );
      expect(s.accelerationFor('p0', 3), 0);
      final restored = Event.decode(e.copy(sections: [s]).encode());
      expect(restored.sections.single.acceleration, s.acceleration);
    },
  );

  test(
    'preset ranks odd rosters deterministically and excludes withdrawals',
    () {
      final original = eventWith(8);
      final e = original.copy(
        players: [
          original.players.first.copy(withdrawn: true),
          for (final p in original.players.skip(1)) p.copy(rating: 1500),
        ],
      );
      expect(topHalfAcceleration(e, e.sections.single, rounds: 1).keys, [
        'p1',
        'p2',
        'p3',
      ]);
      for (final s in [
        e.sections.single.copy(format: Format.roundRobin),
        e.sections.single.copy(doubleGames: true),
        e.sections.single.copy(scoring: const Scoring(win: 6, draw: 2)),
        e.sections.single.copy(rounds: [Round(number: 1, games: [])]),
        e.sections.single.copy(plannedRounds: 1),
      ]) {
        expect(
          () => topHalfAcceleration(e, s, rounds: 1),
          throwsA(isA<TournamentException>()),
        );
      }
    },
  );

  test(
    'team standings count best scores, share ties and keep sections separate',
    () {
      var e = eventWith(8);
      e = e.copy(
        players: [
          for (var i = 0; i < 8; i++)
            e.players[i].copy(
              team: i < 4 ? (i.isEven ? 'Owls' : ' owls ') : 'Bears',
              house: i == 3,
              withdrawn: i == 1,
            ),
        ],
      );
      final s = e.sections.single.copy(
        rounds: [
          Round(
            number: 1,
            games: [],
            byes: [
              for (var i = 0; i < 8; i++)
                ByeAward('p$i', [4, 2, 0, 10, 3, 3, 1, 0][i], 'Fixture'),
            ],
          ),
        ],
      );
      e = e.copy(sections: [s]);
      final teams = teamStandings(e, s, best: 2);
      expect(teams.map((t) => t.points), [6, 6]);
      expect(teams.map((t) => t.rank), [1, 1]);
      expect(teams.last.counted.map((m) => m.player.id), ['p0', 'p1']);
      expect(teamStandings(e, s, best: 0).first.points, 7);
      expect(
        teamStandings(
          e,
          s.copy(players: ['p2', 'p6']),
          best: 4,
        ).map((t) => t.points),
        [1, 0],
      );
      expect(teamReport(e, best: 2), contains('Not counted: Player 2'));
    },
  );

  test('same-person re-entry cannot count twice for one team', () {
    final a = Player(
      id: 'a',
      name: 'First entry',
      personId: 'person',
      team: 'Team',
    );
    final b = Player(
      id: 'b',
      name: 'Re-entry',
      personId: 'person',
      team: 'Team',
    );
    final s = Section(
      id: 's',
      name: 'Open',
      players: ['a', 'b'],
      rounds: [
        Round(
          number: 1,
          games: [],
          byes: [const ByeAward('a', 1, ''), const ByeAward('b', 2, '')],
        ),
      ],
    );
    final e = Event(
      id: 'e',
      name: 'Test',
      date: '2024-01-01',
      players: [a, b],
      sections: [s],
    );
    final team = teamStandings(e, s, best: 0).single;
    expect(team.points, 2);
    expect(team.counted.single.player.id, 'b');
    expect(team.members.length, 2);
  });

  test(
    'extended roster columns preserve teams separately and reject malformed details',
    () {
      final rows = parseRoster(
        'Name,Club,Team,School,Grade,Title,FIDE ID,FIDE Rating,Federation,Birth Date\n'
        'Ada Lee,City Club,Owls,Lincoln,6,wfm,1234567,1700,usa,2014-02-28',
      );
      final p = rows.single.player!;
      expect(p.club, 'City Club');
      expect(p.team, 'Owls');
      expect(p.school, 'Lincoln');
      expect(p.grade, '6');
      expect(p.title, 'WFM');
      expect(p.fideRating, 1700);
      expect(p.federation, 'USA');
      expect(p.birthDate, '2014-02-28');
      for (final row in parseRoster(
        'Name,FIDE ID,FIDE Rating,Federation,Birth Date\n'
        'A,abc,1200,USA,2014-01-01\nB,123,abc,USA,2014-01-01\n'
        'C,123,1200,US,2014-01-01\nD,123,1200,USA,2014-02-30',
      )) {
        expect(row.player, isNull);
        expect(row.error, isNotNull);
      }
      final legacy = Player.fromJson({
        'id': 'old',
        'name': 'Old',
        'memberId': '',
        'rating': 0,
        'checkedIn': false,
        'withdrawn': false,
        'club': '',
        'notes': '',
        'source': '',
        'byes': {},
      });
      expect(legacy.fideId, '');
      expect(legacy.fideRating, 0);
    },
  );

  test('optional details survive save, undo, redo and reopening', () {
    final dir = Directory.systemTemp.createTempSync('meow-details-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/details.meow';
    final c = fixture(count: 4, path: path);
    c.savePlayer(
      c.event!.players.first.copy(
        title: 'FM',
        fideId: '12345',
        fideRating: 2100,
        federation: 'USA',
        birthDate: '1990-02-28',
        school: 'School',
        grade: '12',
        club: 'Club',
      ),
    );
    c.undo();
    expect(c.event!.players.first.fideId, '');
    c.redo();
    expect(c.event!.players.first.fideId, '12345');
    c.dispose();
    final repo = SqliteEventRepository(path);
    addTearDown(repo.close);
    final p = repo.load()!.players.first;
    expect(
      [p.title, p.fideId, p.federation, p.birthDate, p.school, p.grade, p.club],
      ['FM', '12345', 'USA', '1990-02-28', 'School', '12', 'Club'],
    );
    expect(p.fideRating, 2100);
  });

  test(
    'registration metadata leaves US Chess bytes unchanged and birth dates private',
    () {
      final before = exportFixture();
      final after = before.copy(
        players: [
          for (final p in before.players)
            p.copy(
              title: 'FM',
              fideId: '87654321',
              fideRating: 2100,
              federation: 'USA',
              birthDate: '1981-12-23',
              school: 'Private school detail',
              grade: '12',
              team: '=Team',
            ),
        ],
      );
      final oldFiles = ratingPackage(before, today: today),
          newFiles = ratingPackage(after, today: today);
      for (final name in oldFiles.keys) {
        expect(newFiles[name], oldFiles[name], reason: name);
      }
      for (final report in [
        crosstable(after),
        standingsCsv(after),
        teamReport(after),
        teamReportCsv(after),
      ]) {
        expect(report, isNot(contains('1981-12-23')));
        expect(report, isNot(contains('Private school detail')));
        expect(report, isNot(contains('87654321')));
      }
      expect(teamReportCsv(after), contains("'=Team"));
    },
  );
}
