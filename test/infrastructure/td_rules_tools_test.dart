import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/tournament_tools.dart';

void main() {
  late Directory directory;
  late TournamentTools tools;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('meow-td-rules-');
    tools = TournamentTools(directory.path);
    await tools.call('create_event', {
      'path': 'open.meow',
      'name': 'Club Open',
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
    'update_section takes the 22C bye policy and reserve_bye enforces it',
    () async {
      final added = await write('add_players', {
        'players': [
          {'name': 'Ann', 'rating': 1800},
          {'name': 'Bob', 'rating': 1700},
          {'name': 'Cy', 'rating': 1600},
          {'name': 'Di', 'rating': 1500},
        ],
      });
      final ids = [for (final p in added['added']) p['id'] as String];
      final created = await write('create_section', {
        'name': 'Open',
        'players': ids,
        'format': 'swiss',
        'plannedRounds': 5,
        'boardStart': 1,
      });
      final sectionId = created['section']['id'] as String;
      await write('update_section', {
        'sectionId': sectionId,
        'byeRules': {'lastHalfByeRound': 3, 'irrevocableFromRound': 3},
      });
      expect(tools.event.sections.single.byeRules, {
        'lastHalfByeRound': 3,
        'irrevocableFromRound': 3,
      });
      await expectLater(
        write('reserve_bye', {'playerId': ids[0], 'round': 3, 'points': 1}),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'message',
            contains('irrevocable'),
          ),
        ),
      );
      await write('reserve_bye', {
        'playerId': ids[0],
        'round': 3,
        'points': 1,
        'irrevocable': true,
      });
      expect(tools.event.player(ids[0]).irrevocableByes, {3});
      await write('cancel_bye', {'playerId': ids[0], 'round': 3});
      expect(tools.event.player(ids[0]).byes, isEmpty);
      expect(tools.event.player(ids[0]).irrevocableByes, {3});
      await expectLater(
        write('update_section', {
          'sectionId': sectionId,
          'byeRules': {'lastHalfByeRound': 9},
        }),
        throwsA(isA<TournamentException>()),
      );
    },
  );

  test('update_player accepts assigned, foreign and computer fields', () async {
    final added = await write('add_players', {
      'players': [
        {'name': 'Ann', 'rating': 1800},
      ],
    });
    final id = added['added'][0]['id'] as String;
    await expectLater(
      write('update_player', {'playerId': id, 'pairingRating': 1700}),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('28E1'),
        ),
      ),
    );
    await write('update_player', {
      'playerId': id,
      'pairingRating': 1900,
      'prizeRating': 1950,
      'ratingNote': 'Superior to the class (28E2a)',
      'foreignRating': 1850,
      'foreignFederation': 'FIDE',
      'computer': true,
    });
    final p = tools.event.player(id);
    expect(p.pairingRating, 1900);
    expect(p.prizeRating, 1950);
    expect(p.ratingNote, contains('28E2a'));
    expect(p.foreignRating, 1850);
    expect(p.foreignFederation, 'FIDE');
    expect(p.computer, isTrue);
  });

  test('log_ruling records the entry and update_event marks online', () async {
    final logged = await write('log_ruling', {
      'kind': 'ruling',
      'text': 'Illegal move corrected; two minutes added to the opponent.',
      'round': 2,
      'decidedBy': '12345678',
      'outcome': 'Time added (11D1)',
    });
    expect(tools.event.rulings.single['id'], logged['rulingId']);
    expect(tools.event.rulings.single['round'], 2);
    await write('update_event', {'online': true});
    expect(tools.event.online, isTrue);
    final preflight = await tools.call('rating_preflight', {});
    expect(
      (preflight['advice'] as List).join('\n'),
      contains('online rating categories'),
    );
  });

  test('hold_out_non_reporters treats unreported games', () async {
    final added = await write('add_players', {
      'players': [
        {'name': 'Ann', 'rating': 1800},
        {'name': 'Bob', 'rating': 1700},
        {'name': 'Cy', 'rating': 1600},
        {'name': 'Di', 'rating': 1500},
      ],
    });
    final ids = [for (final p in added['added']) p['id'] as String];
    final created = await write('create_section', {
      'name': 'Open',
      'players': ids,
      'format': 'swiss',
      'plannedRounds': 3,
      'boardStart': 1,
    });
    final sectionId = created['section']['id'] as String;
    final proposal = await tools.call('propose_pairings', {
      'sectionId': sectionId,
    });
    await write('post_pairings', {'proposalId': proposal['proposalId']});
    final result = await write('hold_out_non_reporters', {
      'sectionId': sectionId,
      'treatment': 'doubleForfeit',
    });
    expect(result['boards'], [1, 2]);
    expect(
      tools.event.sections.single.rounds.single.games.map((g) => g.outcome),
      everyElement(Outcome.doubleForfeit),
    );
  });

  test('repair_round re-pairs only the boards not kept (29G3)', () async {
    final added = await write('add_players', {
      'players': [
        for (var i = 0; i < 6; i++) {'name': 'P$i', 'rating': 1800 - 50 * i},
      ],
    });
    final ids = [for (final p in added['added']) p['id'] as String];
    final created = await write('create_section', {
      'name': 'Open',
      'players': ids,
      'format': 'swiss',
      'plannedRounds': 4,
      'boardStart': 1,
    });
    final sectionId = created['section']['id'] as String;
    final proposal = await tools.call('propose_pairings', {
      'sectionId': sectionId,
    });
    await write('post_pairings', {'proposalId': proposal['proposalId']});
    final posted = tools.event.sections.single.rounds.single;
    final gone = posted.games.last.black;
    await write('update_player', {'playerId': gone, 'withdrawn': true});
    final keep = [posted.games[0].id, posted.games[1].id];
    await expectLater(
      write('repair_round', {
        'sectionId': sectionId,
        'keep': keep,
        'reason': ' ',
      }),
      throwsA(isA<TournamentException>()),
    );
    final result = await write('repair_round', {
      'sectionId': sectionId,
      'keep': keep,
      'reason': '${tools.event.player(gone).name} withdrew',
    });
    expect((result['explanations'] as List).first, contains('29G3'));
    final round = tools.event.sections.single.rounds.single;
    expect(round.revision, posted.revision + 1);
    expect(round.games.map((g) => g.id).take(2), keep);
    expect(round.games, hasLength(2));
    expect(round.byes.any((b) => b.player == gone && b.points == 0), isTrue);
    expect(round.byes.where((b) => b.allocated), hasLength(1));
  });
}
