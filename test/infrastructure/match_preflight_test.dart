import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';

final today = DateTime(2026, 10, 10);

Event twoPlayerSection({
  int games = 2,
  int bRating = 1700,
  bool sideGames = false,
  List<Player> extra = const [],
}) => Event(
  id: 'event',
  name: 'Club Playoff',
  date: '2026-10-10',
  tdId: '12345678',
  players: [
    Player(id: 'a', name: 'Ann Able', rating: 1800, memberId: '12000001'),
    Player(id: 'b', name: 'Bob Baker', rating: bRating, memberId: '12000002'),
    ...extra,
  ],
  sections: [
    Section(
      id: 'playoff',
      name: 'Playoff',
      players: ['a', 'b', for (final p in extra) p.id],
      format: Format.swiss,
      plannedRounds: games,
      sideGames: sideGames,
      rounds: [
        for (var n = 1; n <= games; n++)
          Round(
            number: n,
            games: [
              Game(
                id: 'g$n',
                white: n.isOdd ? 'a' : 'b',
                black: n.isOdd ? 'b' : 'a',
                board: 1,
                outcome: Outcome.draw,
              ),
            ],
            byes: [for (final p in extra) ByeAward(p.id, 0, 'Sit-out')],
            postedAt: 'now',
          ),
      ],
    ),
  ],
);

Iterable<String> matchAdvice(Event e) => ratingIssues(e, today: today)
    .where((i) => !i.blocking && i.message.contains('as a match'))
    .map((i) => i.message);

void main() {
  test('two players meeting twice in a section is flagged as a match', () {
    final advice = matchAdvice(twoPlayerSection()).single;
    expect(
      advice,
      contains(
        'Playoff: Ann Able and Bob Baker play each other 2 games and nobody else',
      ),
    );
    expect(advice, contains('Mark it as a match when uploading'));
    expect(advice, contains('within 400 points'));
    expect(
      advice,
      contains('50 points per match, 100 in 180 days and 200 in three years'),
    );
    expect(advice, isNot(contains('apart')));
    expect(
      ratingIssues(twoPlayerSection(), today: today)
          .where((i) => !i.blocking && i.message.contains('as a match'))
          .single
          .repairs
          .single
          .label,
      'Go to Playoff results',
    );
  });

  test('a single game or a third player is not a match', () {
    expect(matchAdvice(twoPlayerSection(games: 1)), isEmpty);
    expect(
      matchAdvice(
        twoPlayerSection(
          extra: [
            Player(
              id: 'c',
              name: 'Cy Cole',
              rating: 1600,
              memberId: '12000003',
            ),
          ],
        ),
      ),
      isEmpty,
    );
  });

  test('a side-game pair meeting twice is flagged even among others', () {
    final e = twoPlayerSection(
      sideGames: true,
      extra: [
        Player(id: 'c', name: 'Cy Cole', rating: 1600, memberId: '12000003'),
      ],
    );
    final advice = matchAdvice(e).single;
    expect(
      advice,
      startsWith('Playoff: Ann Able and Bob Baker play each other 2 games.'),
    );
  });

  test('a rating gap over 400 or no published rating asks for review', () {
    expect(
      matchAdvice(twoPlayerSection(bRating: 1300)).single,
      contains('500 points apart, more than the 400 the FAQ allows'),
    );
    expect(
      matchAdvice(twoPlayerSection(bRating: 0)).single,
      contains('Bob Baker has no published rating'),
    );
  });
}
