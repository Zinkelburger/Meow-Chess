import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/infrastructure/tournament_tools.dart';

void main() {
  late Directory directory;
  late TournamentTools tools;
  late List<String> ids;
  late String sectionId;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('meow-knockout-');
    tools = TournamentTools(directory.path);
    await tools.call('create_event', {
      'path': 'ko.meow',
      'name': 'Club Knockout',
      'date': '2026-10-10',
    });
  });
  tearDown(() {
    tools.close();
    directory.deleteSync(recursive: true);
  });

  Future<Map<String, dynamic>> write(String name, Map<String, dynamic> args) =>
      tools.call(name, {...args, 'expectedRevision': tools.event.revision});

  Future<void> enter(Map<String, dynamic> bracket) async {
    final added = await write('add_players', {
      'players': [
        for (var i = 0; i < 8; i++)
          {'name': 'Player $i', 'rating': 2000 - 50 * i},
      ],
    });
    ids = [for (final p in added['added']) p['id'] as String];
    final created = await write('create_section', {
      'name': 'Knockout',
      'players': ids,
      'format': 'knockout',
      'plannedRounds': 3,
      'boardStart': 1,
      'doubleGames': true,
      'bracket': bracket,
    });
    sectionId = created['section']['id'] as String;
  }

  Section section() => tools.event.sections.single;
  int seed(String id) => ids.indexOf(id);

  /// Posts the next round and records every game: the better seed wins,
  /// except on [drawnBoard], where each player wins one game.
  Future<Map<String, dynamic>> playRound({int? drawnBoard}) async {
    final proposal = await tools.call('propose_pairings', {
      'sectionId': sectionId,
    });
    final issues = proposal['issues'] as Map;
    if (issues.isNotEmpty) return proposal;
    await write('post_pairings', {'proposalId': proposal['proposalId']});
    for (final g in section().rounds.last.games) {
      // Colors reverse between legs, so White winning both is one win each.
      final outcome = g.board == drawnBoard
          ? Outcome.whiteWin
          : seed(g.white) < seed(g.black)
          ? Outcome.whiteWin
          : Outcome.blackWin;
      await write('record_result', {'gameId': g.id, 'outcome': outcome.name});
    }
    return proposal;
  }

  test(
    'an eight-player knockout through the tools, director decides a tie',
    () async {
      await enter({'gamesPerMatch': 2, 'tiebreak': 'none'});
      expect(section().bracket, {'gamesPerMatch': 2, 'tiebreak': 'none'});

      final r1 = await playRound(drawnBoard: 1);
      final round = r1['rounds'][sectionId] as Map;
      expect(round['policy'], 'knockout-v1');
      expect((round['games'] as List).length, 8);
      expect(section().bracket['seeds'], ids);
      expect(section().plannedRounds, 3);

      // Board 1 is drawn: the next round waits for the director.
      final blocked = await playRound();
      expect(blocked['issues'][sectionId], contains('Choose who advances'));

      await expectLater(
        write('advance_knockout', {
          'sectionId': sectionId,
          'board': 1,
          'playerId': ids[3],
        }),
        throwsA(isA<TournamentException>()),
      );
      final decided = await write('advance_knockout', {
        'sectionId': sectionId,
        'board': 1,
        'playerId': ids[7],
        'reason': 'Coin toss',
      });
      expect(decided['bracket'], contains('Quarterfinals'));
      expect(section().bracket['rounds'][0]['decisions'], [
        {'board': 1, 'advanced': ids[7], 'reason': 'Coin toss'},
      ]);
      final history = tools.controller.graph;
      expect(
        history.nodes[history.head]!.action,
        'Player 7 advances over Player 0',
      );

      // The tie-break may still change after round 1; games per match may not.
      await write('update_section', {
        'sectionId': sectionId,
        'bracket': {'tiebreak': 'blitz'},
      });
      expect(section().bracket['tiebreak'], 'blitz');
      expect(section().bracket['rounds'], isNotEmpty);
      await expectLater(
        write('update_section', {
          'sectionId': sectionId,
          'bracket': {'gamesPerMatch': 1},
        }),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'message',
            contains('fixed once round 1'),
          ),
        ),
      );
      await expectLater(
        write('update_section', {
          'sectionId': sectionId,
          'bracket': {'gamesPerMatch': 3},
        }),
        throwsA(isA<TournamentException>()),
      );

      final r2 = await playRound();
      expect(r2['rounds'][sectionId]['note'], startsWith('Semifinals'));
      final r3 = await playRound();
      expect(r3['rounds'][sectionId]['note'], startsWith('Final'));
      expect(section().rounds.length, 3);
      expect(section().finished, isTrue);

      final standings = await tools.call('standings', {});
      final rows = standings['sections'][0];
      expect(rows['placings'][0], {'playerId': ids[1], 'placing': 'Winner'});
      expect(rows['placings'][1], {'playerId': ids[3], 'placing': 'Runner-up'});
      // Within a placing, players are listed by seed: the top seed, out on
      // the director's decision, leads the quarterfinalists.
      expect(
        [
          for (final p in rows['placings'] as List)
            if (p['placing'] == 'Quarterfinalist') p['playerId'],
        ],
        [ids[0], ids[4], ids[5], ids[6]],
      );
      expect(rows['bracket'], contains('Final'));

      final text = crosstable(tools.event);
      expect(text, contains('Bracket: 2-game matches · blitz tie-break games'));
      expect(text, contains('Placings: Player 1 – Winner'));
      final done = await playRound();
      expect(done['issues'][sectionId], contains('complete'));
    },
  );

  test('rapid tie-break legs post as an extra round', () async {
    await enter({'gamesPerMatch': 2, 'tiebreak': 'rapid'});
    await playRound(drawnBoard: 1);
    final tb = await playRound();
    final round = tb['rounds'][sectionId] as Map;
    expect(round['note'], startsWith('Tie-break games (rapid)'));
    expect(
      [
        for (final g in round['games']) [g['board'], g['leg']],
      ],
      [
        [1, 3],
        [1, 4],
      ],
    );
    expect(section().rounds.length, 2);
    expect(section().plannedRounds, 4);
    final semis = await playRound();
    expect(semis['rounds'][sectionId]['note'], startsWith('Semifinals'));
    expect(section().rounds.length, 3);
  });

  test('a drawn final still takes its tie-break games', () async {
    final added = await write('add_players', {
      'players': [
        {'name': 'Ann', 'rating': 1800},
        {'name': 'Bob', 'rating': 1700},
      ],
    });
    final created = await write('create_section', {
      'name': 'Final',
      'players': [for (final p in added['added']) p['id']],
      'format': 'knockout',
      'plannedRounds': 1,
      'boardStart': 1,
      'doubleGames': true,
      'bracket': {'gamesPerMatch': 2, 'tiebreak': 'blitz'},
    });
    sectionId = created['section']['id'] as String;
    Future<Map<String, dynamic>> post() async {
      final proposal = await tools.call('propose_pairings', {});
      await write('post_pairings', {'proposalId': proposal['proposalId']});
      // White wins every leg: colors reverse, so one win each.
      for (final g in section().rounds.last.games) {
        await write('record_result', {'gameId': g.id, 'outcome': 'whiteWin'});
      }
      return proposal;
    }

    await post();
    // Every planned round is played and complete, yet the final is drawn.
    expect(section().rounds.length, section().plannedRounds);
    final tb = await post();
    expect(tb['rounds'][sectionId]['note'], startsWith('Tie-break games'));
    expect(section().rounds.length, 2);
  });

  test('create_section refuses bad bracket settings', () async {
    final added = await write('add_players', {
      'players': [
        {'name': 'Ann', 'rating': 1800},
        {'name': 'Bob', 'rating': 1700},
      ],
    });
    await expectLater(
      write('create_section', {
        'name': 'Knockout',
        'players': [for (final p in added['added']) p['id']],
        'format': 'knockout',
        'plannedRounds': 1,
        'boardStart': 1,
        'bracket': {'gamesPerMatch': 4},
      }),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('1 or 2'),
        ),
      ),
    );
  });
}
