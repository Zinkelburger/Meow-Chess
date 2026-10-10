import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/bughouse.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';
import 'package:meow_chess/infrastructure/tournament_tools.dart';

/// A four-partnership, three-round bughouse night run entirely through the
/// MCP tools: partnerships, Swiss matches, results, standings and export.
void main() {
  late Directory directory;
  late TournamentTools tools;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('meow-bughouse-');
    tools = TournamentTools(directory.path);
    await tools.call('create_event', {
      'path': 'bughouse.meow',
      'name': 'Bughouse night',
      'date': '2026-10-10',
    });
  });
  tearDown(() {
    tools.close();
    directory.deleteSync(recursive: true);
  });

  Future<Map<String, dynamic>> write(String name, Map<String, dynamic> args) =>
      tools.call(name, {...args, 'expectedRevision': tools.event.revision});

  test('a bughouse night through the tools', () async {
    final added = await write('add_players', {
      'players': [
        for (var i = 0; i < 8; i++)
          {'name': 'Player $i', 'rating': 1800 - 50 * i},
      ],
    });
    final ids = [for (final p in added['added']) p['id'] as String];
    final created = await write('create_section', {
      'name': 'Bughouse',
      'players': ids,
      'format': 'bughouse',
      'plannedRounds': 3,
      'boardStart': 1,
    });
    final sectionId = created['section']['id'] as String;
    Section section() => tools.event.sections.single;
    expect(section().unrated, isTrue, reason: 'bughouse is never rated');

    // Nothing to pair until everyone has a partner.
    await expectLater(
      tools
          .call('propose_pairings', {'sectionId': sectionId})
          .then((r) => (r['issues'] as Map).values.join()),
      completion(contains('Pair everyone up first')),
    );
    final partners = [
      for (var i = 0; i < 4; i++) [ids[2 * i], ids[2 * i + 1]],
    ];
    await write('set_partners', {'sectionId': sectionId, 'partners': partners});
    expect(section().partners, partners);
    expect(unpartnered(section()), isEmpty);

    // A pair is a pair of distinct section players, each in one pair.
    await expectLater(
      write('set_partners', {
        'sectionId': sectionId,
        'partners': [
          [ids[0], ids[1]],
          [ids[1], ids[2]],
        ],
      }),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('two partnerships'),
        ),
      ),
    );

    for (var n = 1; n <= 3; n++) {
      final proposal = await tools.call('propose_pairings', {
        'sectionId': sectionId,
      });
      expect(proposal['issues'], isEmpty);
      await write('post_pairings', {'proposalId': proposal['proposalId']});
      final round = section().rounds.last;
      expect(round.number, n);
      expect(round.policy, bughousePolicy);
      expect(round.games, hasLength(2));
      expect(round.byes, isEmpty);
      for (final g in round.games) {
        expect(g.whitePartner, partnerOf(section(), g.white));
        expect(g.blackPartner, partnerOf(section(), g.black));
        await write('record_result', {'gameId': g.id, 'outcome': 'whiteWin'});
      }
    }
    final s = section();
    expect(s.finished, isTrue);

    // No partnership met twice.
    final met = [
      for (final r in s.rounds)
        for (final g in r.games)
          ([
            partnershipOf(s, g.white)!.join(),
            partnershipOf(s, g.black)!.join(),
          ]..sort()).join('-'),
    ];
    expect(met.toSet(), hasLength(met.length));

    // Partners are level, and the six match points per round went somewhere.
    final table = await tools.call('standings', {});
    final rows = (table['sections'] as List).single['rows'] as List;
    final points = {
      for (final row in rows) row['playerId'] as String: row['points'] as int,
    };
    for (final pair in partners) {
      expect(points[pair[0]], points[pair[1]], reason: pair.join('/'));
    }
    expect(points.values.fold(0, (a, b) => a + b), 3 * 2 * 2 * 2);

    // Partnerships are fixed once round 1 is posted, by either tool.
    await expectLater(
      write('set_partners', {'sectionId': sectionId, 'partners': partners}),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('fixed once round 1'),
        ),
      ),
    );
    await expectLater(
      write('update_section', {'sectionId': sectionId, 'partners': partners}),
      throwsA(isA<TournamentException>()),
    );

    // The rating report leaves the section out and the preflight says so.
    expect(reportedSections(tools.event), isEmpty);
    expect(
      ratingIssues(tools.event).map((i) => i.message),
      anyElement(contains('Bughouse section left out of the report')),
    );
  });

  test('update_section accepts partners before round 1', () async {
    final added = await write('add_players', {
      'players': [
        for (var i = 0; i < 4; i++) {'name': 'Player $i', 'rating': 1500},
      ],
    });
    final ids = [for (final p in added['added']) p['id'] as String];
    final created = await write('create_section', {
      'name': 'Bughouse',
      'players': ids,
      'format': 'bughouse',
      'plannedRounds': 3,
      'boardStart': 1,
    });
    await write('update_section', {
      'sectionId': created['section']['id'],
      'partners': [
        [ids[0], ids[1]],
      ],
    });
    expect(tools.event.sections.single.partners, [
      [ids[0], ids[1]],
    ]);
    expect(unpartnered(tools.event.sections.single), [ids[2], ids[3]]);
  });
}
