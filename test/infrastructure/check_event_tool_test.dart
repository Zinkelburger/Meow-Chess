import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/tournament_tools.dart';

void main() {
  test('automation reads the event check without changing the event', () async {
    final directory = Directory.systemTemp.createTempSync('meow-check-');
    final tools = TournamentTools(directory.path);
    addTearDown(() {
      tools.close();
      directory.deleteSync(recursive: true);
    });
    await tools.call('create_event', {
      'path': 'open.meow',
      'name': 'Open',
      'date': '2026-11-21',
    });
    await tools.call('add_players', {
      'players': [
        for (final (i, name) in ['Ann', 'Bob', 'Cal', 'Dee', 'Eve'].indexed)
          {'name': name, 'rating': 2000 - i * 100},
      ],
      'expectedRevision': tools.event.revision,
    });
    await tools.call('create_section', {
      'name': 'Open',
      'format': 'swiss',
      'plannedRounds': 3,
      'boardStart': 1,
      'players': [for (final p in tools.event.players.take(4)) p.id],
      'expectedRevision': tools.event.revision,
    });
    final proposal = await tools.call('propose_pairings', {});
    await tools.call('post_pairings', {
      'proposalId': proposal['proposalId'],
      'expectedRevision': tools.event.revision,
    });
    final revision = tools.event.revision;
    final check = await tools.call('check_event', {});
    expect(tools.event.revision, revision);
    expect(check['scope'], 'Open');
    expect(check['findings'], [
      {
        'level': 'note',
        'message': '1 player is in no section: Eve.',
        'players': [tools.event.players.last.id],
      },
    ]);
    final checks = check['checks'] as List;
    expect(
      checks.firstWhere((c) => c['title'] == 'Everyone has a game or a bye'),
      {
        'title': 'Everyone has a game or a bye',
        'ran': true,
        'verdict': 'Clear: 4 players checked',
        'found': 0,
      },
    );
    final quality = (check['pairingQuality'] as List).single as Map;
    expect(quality['name'], 'Open');
    expect((quality['rounds'] as List).single['sameScoreBoards'], {
      'count': 2,
      'of': 2,
    });
    // One section's check leaves the event-wide checks out.
    final one = await tools.call('check_event', {
      'sectionId': tools.event.sections.single.id,
    });
    expect(one['findings'], isEmpty);
    await expectLater(
      tools.call('check_event', {'sectionId': 'missing'}),
      throwsA(anything),
    );
  });
}
