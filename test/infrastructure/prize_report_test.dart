import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/history.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/infrastructure/tournament_tools.dart';

Event event() {
  final players = [
    Player(id: 'a', name: 'Ann', rating: 2100),
    Player(id: 'b', name: 'Bob', rating: 1900),
    Player(id: 'c', name: 'Cal', rating: 1700),
  ];
  return Event(
    id: 'e',
    name: 'Club Open',
    date: '2026-10-09',
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'Open',
        players: ['a', 'b', 'c'],
        plannedRounds: 1,
        rounds: [
          Round(
            number: 1,
            games: [
              Game(
                id: 'g',
                white: 'a',
                black: 'b',
                board: 1,
                outcome: Outcome.draw,
              ),
            ],
            byes: const [ByeAward('c', 0, 'none')],
          ),
        ],
        prizes: {
          'list': [
            {'id': '1', 'kind': 'place', 'place': 1, 'cents': 20000},
            {'id': '2', 'kind': 'place', 'place': 2, 'cents': 10000},
            {
              'id': 'u',
              'label': 'Top Under 1800',
              'kind': 'under',
              'max': 1800,
              'cents': 5000,
              'trophy': true,
            },
          ],
        },
      ),
    ],
  );
}

void main() {
  test('the text report lists prizes, awards and the pooling', () {
    final text = prizeReport(event());
    expect(text, contains('Open — 3 entries'));
    expect(text, contains('pooled: Ann \$150, Bob \$150'));
    expect(text, contains('Top Under 1800'));
    expect(text, contains('Cal'));
    expect(text, contains('trophy: Cal'));
    expect(text, contains('Total paid: \$350'));
    expect(text, contains('2 players tied at 0.5 (Ann, Bob) for 1st + 2nd: '));
  });

  test('the PDF report prints a page per section', () async {
    final bytes = await reportPdf(event(), ReportKind.prizes);
    expect(bytes, isNotEmpty);
    await expectLater(
      reportPdf(
        event().copy(sections: [event().sections.single.copy(players: [])]),
        ReportKind.prizes,
      ),
      throwsA(isA<TournamentException>()),
    );
  });

  test('history describes a changed prize table', () {
    final before = event();
    final after = before.copy(
      sections: [before.sections.single.copy(prizes: const {})],
    );
    expect(describeChanges(before, after), ['Open: prize table changed']);
  });

  test('automation sets and reads the prize table', () async {
    final directory = Directory.systemTemp.createTempSync('meow-prizes-');
    final tools = TournamentTools(directory.path);
    addTearDown(() {
      tools.close();
      directory.deleteSync(recursive: true);
    });
    await tools.call('create_event', {
      'path': 'open.meow',
      'name': 'Open',
      'date': '2026-10-10',
    });
    await tools.call('add_players', {
      'players': [
        {'name': 'Ann', 'rating': 2100},
        {'name': 'Bob', 'rating': 1900},
      ],
      'expectedRevision': tools.event.revision,
    });
    final created = await tools.call('create_section', {
      'name': 'Open',
      'players': [for (final p in tools.event.players) p.id],
      'format': 'swiss',
      'plannedRounds': 3,
      'boardStart': 1,
      'expectedRevision': tools.event.revision,
    });
    final sectionId = created['section']['id'];
    await expectLater(
      tools.call('update_section', {
        'sectionId': sectionId,
        'prizes': {
          'list': [
            {'id': 'x', 'kind': 'mystery', 'cents': 100},
          ],
        },
        'expectedRevision': tools.event.revision,
      }),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('kind'),
        ),
      ),
    );
    await tools.call('update_section', {
      'sectionId': sectionId,
      'prizes': {
        'basedOn': 4,
        'list': [
          {'id': '1', 'kind': 'place', 'place': 1, 'cents': 10000},
        ],
      },
      'expectedRevision': tools.event.revision,
    });
    expect(tools.event.sections.single.prizes['basedOn'], 4);
    final report = await tools.call('prize_report', {'sectionId': sectionId});
    final section = (report['sections'] as List).single;
    expect(section['entries'], 2);
    expect(section['payoutPercent'], 50);
    expect(section['prizes'], hasLength(1));
    expect(section['explanations'], isNotEmpty);
    await expectLater(
      tools.call('prize_report', {'sectionId': 'nope'}),
      throwsA(isA<TournamentException>()),
    );
  });
}
