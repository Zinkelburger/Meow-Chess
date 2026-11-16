import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/tournament_tools.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late TournamentTools tools;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('meow-tools-');
    tools = TournamentTools(directory.path);
  });
  tearDown(() {
    tools.close();
    directory.deleteSync(recursive: true);
  });

  test('a rated event is never turned into a practice copy in place', () async {
    final created = await tools.call('create_event', {
      'path': 'spring.meow',
      'name': 'Spring Open',
      'date': '2026-10-10',
      'practice': false,
    });
    expect(created['practice'], isFalse);
    final revision = tools.event.revision;
    await expectLater(
      tools.call('update_event', {
        'practice': true,
        'expectedRevision': revision,
      }),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('cannot be turned into a practice copy'),
        ),
      ),
    );
    expect(tools.event.practice, isFalse);
    expect(tools.event.revision, revision);
    // Other metadata, and repeating practice: false, still save.
    await tools.call('update_event', {
      'venue': 'Boylston Chess Club',
      'practice': false,
      'expectedRevision': revision,
    });
    expect(tools.event.venue, 'Boylston Chess Club');
  });

  test('a failed create leaves no file behind, so it can be retried', () async {
    final locked = Directory(p.join(directory.path, 'locked'))..createSync();
    Process.runSync('chmod', ['555', locked.path]);
    addTearDown(() => Process.runSync('chmod', ['755', locked.path]));
    try {
      File(p.join(locked.path, 'probe')).createSync();
      markTestSkipped('Folder permissions are not enforced here.');
      return;
    } on FileSystemException {
      // Expected: the folder refuses new files.
    }
    final arguments = {
      'path': 'locked/spring.meow',
      'name': 'Spring Open',
      'date': '2026-10-10',
    };
    await expectLater(
      tools.call('create_event', arguments),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('cannot create a file in this folder'),
        ),
      ),
    );
    expect(locked.listSync(), isEmpty);
    Process.runSync('chmod', ['755', locked.path]);
    await tools.call('create_event', arguments);
    expect(tools.event.name, 'Spring Open');
  }, skip: Platform.isWindows);

  Future<Map<String, dynamic>> write(String name, Map<String, dynamic> args) =>
      tools.call(name, {...args, 'expectedRevision': tools.event.revision});

  Matcher refusal(String text) => throwsA(
    isA<TournamentException>().having((e) => e.message, 'message', text),
  );

  /// A practice event with four registered players; returns their IDs.
  Future<List<String>> fourPlayers() async {
    await tools.call('create_event', {
      'path': 'club.meow',
      'name': 'Club Night',
      'date': '2026-10-10',
    });
    final added = await write('add_players', {
      'players': [
        {'name': 'Ann', 'rating': 1800},
        {'name': 'Bob', 'rating': 1700},
        {'name': 'Cy', 'rating': 1600},
        {'name': 'Di', 'rating': 1500},
      ],
    });
    return [for (final p in added['added'] as List) (p as Map)['id'] as String];
  }

  test('create_section refuses what the section panel refuses', () async {
    final ids = await fourPlayers();
    Map<String, dynamic> section(List<String> players, {int rounds = 3}) => {
      'name': '  Open  ',
      'players': players,
      'format': 'swiss',
      'plannedRounds': rounds,
      'boardStart': 1,
    };
    // Listed twice used to surface as "belongs to more than one section".
    await expectLater(
      write('create_section', section([ids[0], ids[0]])),
      refusal('A player is listed twice.'),
    );
    await expectLater(
      write('create_section', section(ids, rounds: 33)),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          'arguments.plannedRounds: must be between 1 and 32',
        ),
      ),
    );
    await write('update_player', {'playerId': ids[3], 'withdrawn': true});
    await expectLater(
      write('create_section', section(ids)),
      refusal('Di has withdrawn. Reinstate them first.'),
    );
    expect(tools.event.sections, isEmpty);
    await write('create_section', section(ids.take(3).toList()));
    expect(tools.event.sections.single.name, 'Open');
    await expectLater(
      write('create_section', section([ids[3]])),
      refusal('Di has withdrawn. Reinstate them first.'),
    );
    await write('update_player', {'playerId': ids[3], 'withdrawn': false});
    await expectLater(
      write('create_section', section([ids[3]])),
      refusal('There is already a section called Open.'),
    );
    await expectLater(
      write('create_section', {
        ...section([ids[3]]),
        'format': 'arena',
      }),
      refusal(
        'arguments.format: invalid choice "arena"; choose one of '
        '${Format.values.map((f) => '"${f.name}"').join(', ')}',
      ),
    );
    await expectLater(
      tools.call('prize_report', {'sectionId': 'nope'}),
      refusal('No section has the ID "nope".'),
    );
  });

  test('a manual round names what is wrong with it', () async {
    final ids = await fourPlayers();
    final created = await write('create_section', {
      'name': 'Open',
      'players': ids,
      'format': 'swiss',
      'plannedRounds': 1,
      'boardStart': 1,
    });
    final sectionId = created['section']['id'] as String;
    Map<String, dynamic> round({int byePoints = 2}) => {
      'sectionId': sectionId,
      'reason': 'Replay of the posted sheet',
      'games': [
        {'white': ids[0], 'black': ids[1], 'board': 1},
      ],
      'byes': [
        {'player': ids[2], 'points': byePoints, 'reason': 'Bye'},
        {'player': ids[3], 'points': 0, 'reason': 'Unpaired'},
      ],
    };
    // Two points is a double round's full-point bye, not a single game's.
    await expectLater(
      write('post_manual_round', round(byePoints: 4)),
      refusal('A bye in Open is worth 0 to 2 half-points.'),
    );
    // A player with a game and a bye is named, with the round.
    await expectLater(
      write('post_manual_round', {
        ...round(),
        'byes': [
          {'player': ids[0], 'points': 0, 'reason': 'Unpaired'},
          {'player': ids[2], 'points': 2, 'reason': 'Bye'},
          {'player': ids[3], 'points': 0, 'reason': 'Unpaired'},
        ],
      }),
      refusal('Ann has a bye and another game or bye in round 1 of Open.'),
    );
    await write('post_manual_round', round());
    final gameId = tools.event.sections.single.rounds.single.games.single.id;
    await write('record_result', {'gameId': gameId, 'outcome': 'draw'});
    await expectLater(
      write('post_manual_round', round()),
      refusal(
        'All 1 planned rounds of Open are posted. Raise the planned rounds with update_section first.',
      ),
    );
  });

  test('rating checks use the injected clock, not the machine clock', () async {
    tools.close();
    tools = TournamentTools(directory.path, now: () => DateTime(2026, 10, 9));
    await tools.call('create_event', {
      'path': 'tomorrow.meow',
      'name': 'Club Night',
      'date': '2026-10-10',
    });
    final early = await tools.call('rating_preflight', {});
    expect(
      early['issues'],
      contains(contains('The event ends after today (2026-10-10).')),
    );
    tools.close();
    tools = TournamentTools(
      directory.path,
      now: () => DateTime(2026, 10, 10, 0, 0, 1),
    );
    await tools.call('open_event', {'path': 'tomorrow.meow'});
    final onTheDay = await tools.call('rating_preflight', {});
    expect(
      (onTheDay['issues'] as List).where((i) => '$i'.contains('after today')),
      isEmpty,
    );
  });
}
