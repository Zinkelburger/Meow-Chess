import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/scheveningen.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/infrastructure/tournament_tools.dart';

void main() {
  late Directory directory;
  late TournamentTools tools;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('meow-scheveningen-');
    tools = TournamentTools(directory.path);
    await tools.call('create_event', {
      'path': 'match.meow',
      'name': 'Lions v Tigers',
      'date': '2026-10-10',
    });
  });
  tearDown(() {
    tools.close();
    directory.deleteSync(recursive: true);
  });
  Future<Map<String, dynamic>> write(String name, Map<String, dynamic> args) =>
      tools.call(name, {...args, 'expectedRevision': tools.event.revision});

  test(
    'a Scheveningen section is created over MCP and posts two rounds',
    () async {
      final added = await write('add_players', {
        'players': [
          for (var i = 0; i < 3; i++)
            {'name': 'Lion $i', 'rating': 1800 - i * 10, 'team': 'Lions'},
          for (var i = 0; i < 4; i++)
            {'name': 'Tiger $i', 'rating': 1790 - i * 10, 'team': 'Tigers'},
        ],
      });
      final ids = [for (final p in added['added']) p['id'] as String];
      final created = await write('create_section', {
        'name': 'Match',
        'players': ids,
        'format': 'scheveningen',
        'plannedRounds': 4,
        'boardStart': 1,
        'homeTeam': 'Lions',
      });
      final sectionId = created['section']['id'] as String;
      expect(created['section']['homeTeam'], 'Lions');

      for (var n = 1; n <= 2; n++) {
        final proposal = await tools.call('propose_pairings', {
          'sectionId': sectionId,
        });
        await write('post_pairings', {'proposalId': proposal['proposalId']});
        final round = tools.event.sections.single.rounds.last;
        expect(round.number, n);
        expect(round.policy, 'scheveningen-v1');
        expect(round.games, hasLength(3));
        expect(round.byes.single.reason, 'Scheveningen sit-out');
        for (final g in round.games) {
          await write('record_result', {'gameId': g.id, 'outcome': 'whiteWin'});
        }
      }
      final e = tools.event, s = e.sections.single;
      expect(s.rounds, hasLength(2));
      expect(s.rounds.last.note, 'Lions 3 – Tigers 0 after round 1.');
      // Round 1: Lions White on every board; round 2: Tigers.
      expect(scheveningenScore(e, s), (6, 6));
      expect(scheveningenScoreLine(e, s), 'Lions 3 – Tigers 3');

      // Once a round is posted the home team is fixed.
      await expectLater(
        write('update_section', {'sectionId': sectionId, 'homeTeam': 'Tigers'}),
        throwsA(isA<TournamentException>()),
      );

      // The printed pairing sheet lists every round of the table.
      final rounds = reportPairingRounds(s, event: e);
      expect(rounds.map((r) => r.number), [1, 2, 3, 4]);
      expect(rounds[2].policy, 'scheveningen-v1');
      expect(rounds[2].games, hasLength(3));
      expect(reportPairingRounds(s).map((r) => r.number), [2]);
    },
  );
}
