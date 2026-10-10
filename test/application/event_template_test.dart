import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/event_template.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/prizes.dart';

import '../support.dart';

void main() {
  test('templateFrom copies the set-up and nothing about the people', () async {
    final c = fixture(count: 8, format: Format.swiss);
    addTearDown(c.dispose);
    final first = c.event!.sections.first;
    c.change(
      'Announce',
      c.event!.copy(
        tdId: '12345678',
        affiliateId: 'A6012345',
        timeControl: 'G/25 d5',
        useTiebreaks: true,
        tiebreaks: ['solkoff', 'cumulative'],
        notes: 'private',
        sections: [
          first.copy(
            plannedRounds: 5,
            doubleGames: true,
            ratingCeiling: 1800,
            accelerated: 'addedScore',
            byeRules: const {'lastHalfByeRound': 3},
            homeTeam: 'Home',
            bracket: const {
              'gamesPerMatch': 2,
              'seeds': ['p0', 'p1'],
            },
            prizes: PrizeTable(
              list: [
                Prize(id: 'x', place: 1, cents: 5000, eligible: const ['p0']),
              ],
            ).toJson(),
          ),
          ...c.event!.sections.skip(1),
        ],
      ),
    );
    c.post(await c.propose(sectionId: first.id));
    final source = c.event!;
    final copy = templateFrom(source, name: 'Next week', date: '2026-10-16');
    expect(copy.id, isNot(source.id));
    expect(copy.name, 'Next week');
    expect(copy.date, '2026-10-16');
    expect(copy.players, isEmpty);
    expect(copy.notes, isEmpty);
    expect(copy.transitions, isEmpty);
    expect(copy.tdId, '12345678');
    expect(copy.affiliateId, 'A6012345');
    expect(copy.timeControl, 'G/25 d5');
    expect(copy.useTiebreaks, isTrue);
    expect(copy.tiebreaks, ['solkoff', 'cumulative']);
    expect(copy.sections, hasLength(source.sections.length));
    final s = copy.sections.first;
    expect(s.id, isNot(first.id));
    expect(s.name, first.name);
    expect(s.format, Format.swiss);
    expect(s.players, isEmpty);
    expect(s.rounds, isEmpty);
    expect(s.plannedRounds, 5);
    expect(s.doubleGames, isTrue);
    expect(s.ratingCeiling, 1800);
    expect(s.accelerated, 'addedScore');
    expect(s.byeRules, {'lastHalfByeRound': 3});
    expect(s.homeTeam, 'Home');
    expect(s.bracket, {'gamesPerMatch': 2});
    final prizes = PrizeTable.fromJson(s.prizes);
    expect(prizes.list.single.cents, 5000);
    expect(prizes.list.single.eligible, isEmpty);
    expect(
      templateNote(source),
      'Copied from Saturday Quads: 2 sections, tie-break order, time control, '
      'TD and affiliate IDs. No players, results or rulings.',
    );
  });
}
