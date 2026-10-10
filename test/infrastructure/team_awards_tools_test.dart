import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/team_standings.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/infrastructure/tournament_tools.dart';

void main() {
  late Directory directory;
  late TournamentTools tools;
  late String sectionId;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('meow-team-awards-');
    tools = TournamentTools(directory.path);
    await tools.call('create_event', {
      'path': 'scholastic.meow',
      'name': 'County Scholastic',
      'date': '2026-10-10',
    });
    Future<Map<String, dynamic>> write(
      String name,
      Map<String, dynamic> args,
    ) => tools.call(name, {...args, 'expectedRevision': tools.event.revision});
    final added = await write('add_players', {
      'players': [
        for (var i = 0; i < 4; i++)
          {'name': 'Lincoln $i', 'rating': 1500 - i * 20, 'team': 'Lincoln'},
        for (var i = 0; i < 3; i++)
          {'name': 'Grant $i', 'rating': 1490 - i * 20, 'team': 'Grant'},
        {'name': 'Hayes 0', 'rating': 1300, 'team': 'Hayes'},
      ],
    });
    final created = await write('create_section', {
      'name': 'K-8',
      'players': [for (final p in added['added']) p['id'] as String],
      'format': 'swiss',
      'plannedRounds': 3,
      'boardStart': 1,
      'avoidTeammates': true,
    });
    sectionId = created['section']['id'] as String;
  });
  tearDown(() {
    tools.close();
    directory.deleteSync(recursive: true);
  });
  Future<Map<String, dynamic>> write(String name, Map<String, dynamic> args) =>
      tools.call(name, {...args, 'expectedRevision': tools.event.revision});

  Future<void> playRound() async {
    final proposal = await tools.call('propose_pairings', {
      'sectionId': sectionId,
    });
    await write('post_pairings', {'proposalId': proposal['proposalId']});
    for (final g in tools.event.sections.single.rounds.last.games) {
      await write('record_result', {'gameId': g.id, 'outcome': 'whiteWin'});
    }
  }

  test('update_section sets team awards and standings returns teams', () async {
    await write('update_section', {
      'sectionId': sectionId,
      'teamAwards': {'method': 'topN', 'counting': 3},
    });
    final s = tools.event.sections.single;
    expect(TeamAwards.of(s)!.toJson(), {
      'counting': 3,
      'method': 'topN',
      'minPlayers': 2,
    });

    await playRound();
    final result = await tools.call('standings', {});
    final teams = result['sections'].single['teams'] as Map;
    expect(teams['summary'], 'Top 3 scores count');
    expect(teams['tiebreakOrder'].map((t) => t['code']), [
      'modifiedMedian',
      'solkoff',
      'sonnebornBerger',
      'cumulative',
      'coinFlip',
    ]);
    final rows = teams['rows'] as List;
    expect(rows.map((r) => r['team']).toSet(), {'Lincoln', 'Grant', 'Hayes'});
    final hayes = rows.firstWhere((r) => r['team'] == 'Hayes');
    expect(hayes['eligible'], isFalse);
    expect(hayes['rank'], 0);
    for (final r in rows.where((r) => r['eligible'] == true)) {
      expect((r['counting'] as List).length, lessThanOrEqualTo(3));
      expect(
        r['score'],
        (r['counting'] as List).fold<int>(0, (n, m) => n + m['points'] as int),
      );
    }
  });

  test('a replaced prize table keeps team awards; off removes them', () async {
    await write('update_section', {
      'sectionId': sectionId,
      'teamAwards': {'method': 'rollins'},
    });
    await write('update_section', {
      'sectionId': sectionId,
      'prizes': {
        'list': [
          {'id': 't1', 'kind': 'team', 'place': 1, 'trophy': true},
          {'id': 'p1', 'kind': 'place', 'place': 1, 'cents': 5000},
        ],
      },
    });
    var s = tools.event.sections.single;
    expect(TeamAwards.of(s)!.method, TeamScoring.rollins);
    expect(TeamAwards.of(s)!.counting, 4);

    // A partial update keeps the rest of the stored settings.
    await write('update_section', {
      'sectionId': sectionId,
      'teamAwards': {'counting': 3},
    });
    s = tools.event.sections.single;
    expect(TeamAwards.of(s)!.method, TeamScoring.rollins);
    expect(TeamAwards.of(s)!.counting, 3);

    await playRound();
    final report = await tools.call('prize_report', {});
    final section = report['sections'].single;
    // Individual lines only; the team prize is reported on its own.
    expect(section['prizes'].map((p) => p['id']), ['p1']);
    expect(section['paidCents'], 5000);
    final teamPrize = section['teamPrizes']['prizes'].single;
    expect(teamPrize['id'], 't1');
    expect(teamPrize['trophy'], isNotNull);

    await expectLater(
      write('update_section', {
        'sectionId': sectionId,
        'teamAwards': {'method': 'median'},
      }),
      throwsA(isA<Object>()),
    );

    await write('update_section', {
      'sectionId': sectionId,
      'teamAwards': {'method': 'off'},
    });
    s = tools.event.sections.single;
    expect(TeamAwards.of(s), isNull);
    expect(s.prizes['list'], hasLength(2));
  });

  test('reports carry the team standings and the scoring method', () async {
    await write('update_section', {
      'sectionId': sectionId,
      'teamAwards': {'method': 'topN', 'counting': 3},
      'prizes': {
        'list': [
          {'id': 't1', 'kind': 'team', 'place': 1, 'cents': 2000},
        ],
      },
    });
    await playRound();
    final e = tools.event;
    final text = crosstable(e);
    expect(text, contains('Teams — Top 3 scores count'));
    expect(text, contains('Lincoln'));
    expect(text, contains('(needs 2 players, 10.2.2)'));
    // Team lines use plain figures, so ASCII export still works.
    expect(() => crosstable(e, asciiOnly: true), returnsNormally);

    final prizes = prizeReport(e);
    expect(prizes, contains('Team prizes'));
    expect(prizes, contains('1st team'));
    expect(prizes, contains('No individual prizes.'));

    expect(
      await reportPdf(e, ReportKind.standings, sectionId: e.sections.single.id),
      isNotEmpty,
    );
    expect(
      await reportPdf(e, ReportKind.prizes, sectionId: e.sections.single.id),
      isNotEmpty,
    );
    expect(await conditionsPdf(e), isNotEmpty);
    expect(
      TeamAwards.of(e.sections.single)!.description,
      contains(
        'sum of the top 3 individual scores (Scholastic Regulations 10.2.1)',
      ),
    );
  });
}
