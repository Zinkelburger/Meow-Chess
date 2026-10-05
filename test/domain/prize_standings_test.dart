import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/standings.dart';

Event roundRobin({
  int count = 5,
  int played = 2,
  bool doubleGames = false,
  int? plannedRounds,
  Format format = Format.roundRobin,
}) {
  final players = [
    for (var i = 0; i < count; i++)
      Player(id: '$i', name: 'Player $i', withdrawn: i == 0),
  ];
  return Event(
    id: 'e',
    name: 'Round robin',
    date: '2026-10-04',
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'Section',
        players: players.map((p) => p.id).toList(),
        format: format,
        plannedRounds: plannedRounds ?? (count.isOdd ? count : count - 1),
        doubleGames: doubleGames,
        rounds: [
          for (var i = 0; i < played; i++)
            Round(
              number: i + 1,
              games: [
                Game(
                  id: 'g$i',
                  white: '0',
                  black: '${i + 1}',
                  board: 1,
                  outcome: Outcome.draw,
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

void main() {
  for (final count in [4, 5, 6, 7]) {
    test(
      '$count-player withdrawal keeps scores after half the actual games',
      () {
        final played = (count - 1 + 1) ~/ 2;
        final event = roundRobin(count: count, played: played);
        final before = event.encode();
        final rows = standings(event, event.sections.single, forPrizes: true);
        expect(rows, hasLength(count));
        expect(rows.firstWhere((r) => r.player.id == '0').points, played);
        for (var i = 1; i <= played; i++) {
          expect(rows.firstWhere((r) => r.player.id == '$i').points, 1);
        }
        expect(event.encode(), before);
        final early = roundRobin(count: count, played: played - 1);
        final excluded = standings(
          early,
          early.sections.single,
          forPrizes: true,
        );
        expect(excluded, hasLength(count - 1));
        expect(excluded.every((row) => row.points == 0), isTrue);
      },
    );
  }

  test('double games count both legs but never the odd-field sit-out', () {
    final event = roundRobin(doubleGames: true, played: 4);
    expect(
      standings(event, event.sections.single, forPrizes: true),
      hasLength(5),
    );
    final early = roundRobin(doubleGames: true, played: 3);
    expect(
      standings(early, early.sections.single, forPrizes: true),
      hasLength(4),
    );
  });

  test('unposted incomplete quads use Swiss withdrawal rules', () {
    final event = roundRobin(count: 3, played: 0, format: Format.quad);
    expect(
      standings(event, event.sections.single, forPrizes: true),
      hasLength(3),
    );
  });

  test('empty round-robin standings need no generated schedule', () {
    final event = roundRobin(count: 0, played: 0);
    expect(standings(event, event.sections.single, forPrizes: true), isEmpty);
  });
}
