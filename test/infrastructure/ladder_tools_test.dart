import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/history.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/fixed_schedule.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/infrastructure/tournament_tools.dart';

void main() {
  late Directory directory;
  late TournamentTools tools;
  late List<String> ids;
  late String sectionId;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('meow-ladder-');
    tools = TournamentTools(directory.path);
    await tools.call('create_event', {
      'path': 'ladder.meow',
      'name': 'Club Ladder',
      'date': '2026-10-10',
    });
    final added = await tools.call('add_players', {
      'expectedRevision': tools.event.revision,
      'players': [
        {'name': 'Alex Chen', 'rating': 1900, 'memberId': '12000001'},
        {'name': 'Bo Li', 'rating': 1800, 'memberId': '12000002'},
        {'name': 'Cy Dee', 'rating': 1700, 'memberId': '12000003'},
        {'name': 'Di Fox', 'rating': 1600, 'memberId': '12000004'},
        {'name': 'Ed Gray', 'rating': 1500, 'memberId': '12000005'},
      ],
    });
    ids = [for (final p in added['added']) p['id'] as String];
    final created = await tools.call('create_section', {
      'expectedRevision': tools.event.revision,
      'name': 'Ladder',
      'players': ids,
      'format': 'ladder',
      'plannedRounds': 32,
      'boardStart': 1,
    });
    sectionId = created['section']['id'] as String;
  });
  tearDown(() {
    tools.close();
    directory.deleteSync(recursive: true);
  });

  Future<Map<String, dynamic>> write(String name, Map<String, dynamic> args) =>
      tools.call(name, {...args, 'expectedRevision': tools.event.revision});
  Section section() =>
      tools.event.sections.firstWhere((s) => s.id == sectionId);
  String name(String id) => tools.event.player(id).name;

  test('three challenges through the tools reorder the ladder', () async {
    final [a, b, c, d, e] = ids;
    // Ed (#5) beats Cy (#3): Ed takes #3, Cy and Di move down.
    var out = await write('record_ladder_game', {
      'sectionId': sectionId,
      'challenger': e,
      'defender': c,
      'result': 'win',
    });
    expect(out['ladder'], [a, b, e, c, d]);
    final game = section().rounds.single.games.single;
    expect(game.id, out['gameId']);
    expect((game.white, game.black), (c, e), reason: 'challenger has Black');
    expect(game.outcome, Outcome.blackWin);
    expect(section().rounds.single.complete, isTrue);

    // Bo (#2) draws Alex (#1) with White: nothing moves, same batch.
    out = await write('record_ladder_game', {
      'sectionId': sectionId,
      'challenger': b,
      'defender': a,
      'result': 'draw',
      'challengerWhite': true,
    });
    expect(out['ladder'], [a, b, e, c, d]);
    expect(section().rounds.length, 1);
    expect(section().rounds.single.games.length, 2);
    expect(section().rounds.single.games.last.white, b);
    expect(section().rounds.single.games.last.outcome, Outcome.draw);

    // Cy (#4) beats Ed (#3) by forfeit: a new batch, since both played in
    // the first one.
    out = await write('record_ladder_game', {
      'sectionId': sectionId,
      'challenger': c,
      'defender': e,
      'result': 'forfeitWin',
    });
    expect(out['ladder'], [a, b, c, e, d]);
    expect(section().rounds.length, 2);
    expect(section().rounds.last.games.single.outcome, Outcome.blackForfeit);

    // History says who moved where.
    final steps = describeChanges(
      tools.event.copy(
        sections: [
          section().copy(players: [a, b, e, c, d]),
        ],
      ),
      tools.event,
    );
    expect(steps, contains('Ladder: Cy Dee up to #3, Ed Gray down to #4'));

    // Reports: the crosstable reads top down and the DBF reports a Swiss.
    final text = crosstable(tools.event);
    expect(text, contains('Ladder — ladder, 2 batches of challenge games'));
    final lines = text
        .split('\n')
        .where((l) => l.contains('Alex Chen'))
        .toList();
    expect(lines.single.trimLeft(), startsWith('1  '));
    expect(section().rounds.length, 2);
    // The DBF section row would go out as type S: no fixed schedule.
    expect(hasFixedSchedule(section()), isFalse);
    final standingsPdf = await reportPdf(tools.event, ReportKind.standings);
    expect(standingsPdf, isNotEmpty);

    // Undo puts the last challenge back.
    await write('undo', {'acceptLosses': true});
    expect(section().players, [a, b, e, c, d]);
    expect(section().rounds.length, 1);
  });

  test('illegal challenges are refused plainly', () async {
    final [a, b, c, d, e] = ids;
    await expectLater(
      write('record_ladder_game', {
        'sectionId': sectionId,
        'challenger': e,
        'defender': b,
        'result': 'win',
      }),
      throwsA(
        isA<TournamentException>().having(
          (x) => x.message,
          'message',
          'Bo Li is 3 places above Ed Gray; a challenge reaches at most 2 places up.',
        ),
      ),
    );
    await expectLater(
      write('record_ladder_game', {
        'sectionId': sectionId,
        'challenger': a,
        'defender': c,
        'result': 'win',
      }),
      throwsA(
        isA<TournamentException>().having(
          (x) => x.message,
          'message',
          contains('below'),
        ),
      ),
    );
    await expectLater(
      write('record_ladder_game', {
        'sectionId': sectionId,
        'challenger': d,
        'defender': c,
        'result': 'victory',
      }),
      throwsA(isA<TournamentException>()),
    );
    expect(section().players, ids);
    expect(section().rounds, isEmpty);
  });

  test('the director can reorder the ladder with a reason', () async {
    final [a, b, c, d, e] = ids;
    final out = await write('set_ladder_order', {
      'sectionId': sectionId,
      'players': [b, a, c, d, e],
      'reason': 'Season reset by rating',
    });
    expect(out['ladder'], [b, a, c, d, e]);
    expect(name(section().players.first), 'Bo Li');
    await expectLater(
      write('set_ladder_order', {
        'sectionId': sectionId,
        'players': [b, a, c, d],
        'reason': 'oops',
      }),
      throwsA(
        isA<TournamentException>().having(
          (x) => x.message,
          'message',
          contains('exactly once'),
        ),
      ),
    );
    await expectLater(
      write('set_ladder_order', {
        'sectionId': sectionId,
        'players': [a, b, c, d, e],
        'reason': '',
      }),
      throwsA(isA<TournamentException>()),
    );
  });

  test('a ladder is left out of Create pairings and refuses propose', () async {
    expect(tools.event.sections.single.format, Format.ladder);
    final ready = await tools.controller.propose(onlyReady: true);
    expect(ready.rounds, isEmpty);
    expect(ready.issues, isEmpty);
    final explicit = await tools.controller.propose(sectionId: sectionId);
    expect(explicit.rounds, isEmpty);
    expect(explicit.issues[sectionId], contains('record challenge games'));
  });
}
