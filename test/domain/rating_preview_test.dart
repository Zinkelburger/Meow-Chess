import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/rating_preview.dart';
import 'package:meow_chess/domain/member_observation.dart';
import 'package:meow_chess/domain/rating_update.dart';

Event eventWith(
  List<Game> games, {
  int rating = 2190,
  int opponent = 2190,
  String timeControl = 'G/65 d10',
  List<ByeAward> byes = const [],
}) => Event(
  id: 'event',
  name: 'Preview',
  date: '2026-10-03',
  timeControl: timeControl,
  players: [
    Player(id: 'p', name: 'Player', rating: rating),
    for (final id in ['a', 'b', 'c'])
      Player(id: id, name: id, rating: opponent),
  ],
  sections: [
    Section(
      id: 's',
      name: 'Quad',
      players: ['p', 'a', 'b', 'c'],
      rounds: [Round(number: 1, games: games, byes: byes)],
    ),
  ],
);

Game game(
  String id,
  Outcome outcome, {
  bool black = false,
  String opponent = 'a',
}) => Game(
  id: id,
  white: black ? opponent : 'p',
  black: black ? 'p' : opponent,
  board: 1,
  outcome: outcome,
);

RatingPreview estimate(Event e) =>
    previewRating(e, e.sections.single, e.player('p'));

void main() {
  test('near-2200 round-one win uses rating-dependent K without bonus', () {
    final e = eventWith([game('1', Outcome.whiteWin)]);
    final before = e.encode();
    final result = estimate(e);
    expect(result.rating, 2200);
    expect(result.change, 10);
    expect(result.games, 1);
    expect(e.encode(), before);
  });

  test(
    'published Regular evidence preserves player and opponent estimates',
    () {
      final event = eventWith([game('1', Outcome.whiteWin)]);
      final before = estimate(event);
      final approved = event.copy(
        players: [
          for (final player in event.players)
            applyRatingObservation(
              player,
              MemberObservation(
                id: player.memberId,
                name: player.name,
                retrievedAt: '2026-10-04',
                supplementDate: '2026-10-01',
                ratings: {'R': player.rating},
              ),
              'R',
            ),
        ],
      );
      expect(estimate(approved).rating, before.rating);
      expect(estimate(approved).change, before.change);
      for (final category in ['regular', 'Regular', 'R']) {
        final compatible = approved.copy(
          players: [
            for (final player in approved.players)
              player.copy(ratingEvidence: {'category': category}),
          ],
        );
        expect(estimate(compatible).rating, before.rating);
      }
      for (final category in ['Q', 'B', 'quick', 'blitz', 'unknown']) {
        final other = approved.copy(
          players: [
            for (final player in approved.players)
              player.id == 'a'
                  ? player.copy(ratingEvidence: {'category': category})
                  : player,
          ],
        );
        expect(estimate(other).rating, isNull);
        expect(estimate(other).reason, contains('starting Regular rating'));
      }
    },
  );

  test('black win, draw and loss score from the player perspective', () {
    expect(
      estimate(eventWith([game('1', Outcome.blackWin, black: true)])).rating,
      2200,
    );
    expect(estimate(eventWith([game('1', Outcome.draw)])).change, 0);
    expect(estimate(eventWith([game('1', Outcome.blackWin)])).rating, 2180);
  });

  test('unfinished, disputed, assumptions, forfeits and byes do not count', () {
    final ignored = [
      for (final o in Outcome.values.where((o) => !o.played))
        game(o.name, o).copy(pairingAssumption: Outcome.whiteWin),
    ];
    final e = eventWith(ignored, byes: [const ByeAward('p', 2, 'Bye')]);
    expect(estimate(e).rating, isNull);
    expect(estimate(e).games, 0);
    expect(
      estimate(eventWith([...ignored, game('win', Outcome.whiteWin)])).rating,
      2200,
    );
  });

  test(
    'recomputes cumulative results from the start and reverses corrections',
    () {
      final win = game('1', Outcome.whiteWin);
      final loss = game('2', Outcome.blackWin, opponent: 'b');
      expect(estimate(eventWith([win, loss])).change, 0);
      expect(estimate(eventWith([loss, win])).change, 0);
      expect(estimate(eventWith([win.copy(outcome: Outcome.draw)])).change, 0);
      expect(
        estimate(eventWith([win.copy(outcome: Outcome.unreported)])).rating,
        isNull,
      );
    },
  );

  test('bonus requires three distinct opponents for a three-game event', () {
    final distinct = eventWith(
      [
        for (final id in ['a', 'b', 'c'])
          game(id, Outcome.whiteWin, opponent: id),
      ],
      rating: 1700,
      opponent: 1700,
    );
    // K ≈ 34.798, base gain ≈ 52.197, bonus ≈ 32.197.
    expect(estimate(distinct).rating, 1784);
    final repeated = eventWith(
      [for (var i = 0; i < 3; i++) game('$i', Outcome.whiteWin)],
      rating: 1700,
      opponent: 1700,
    );
    expect(estimate(repeated).rating, 1752);
  });

  test(
    'unrated players or opponents do not yield a misleading partial estimate',
    () {
      expect(
        estimate(eventWith([game('1', Outcome.whiteWin)], rating: 0)).rating,
        isNull,
      );
      expect(
        estimate(eventWith([game('1', Outcome.whiteWin)], opponent: 0)).rating,
        isNull,
      );
      final e = eventWith([
        game('1', Outcome.whiteWin),
        game('2', Outcome.whiteWin, opponent: 'b'),
      ]);
      expect(
        estimate(
          e.copy(
            players: [
              for (final p in e.players) p.id == 'b' ? p.copy(rating: 0) : p,
            ],
          ),
        ).rating,
        isNull,
      );
    },
  );

  test('uses section controls and reduces Regular K in Dual events', () {
    final e = eventWith(
      [game('1', Outcome.whiteWin)],
      rating: 2600,
      opponent: 2600,
    );
    expect(estimate(e).change, 8);
    expect(
      estimate(
        e.copy(sections: [e.sections.single.copy(timeControl: 'G/30 d5')]),
      ).change,
      2,
    );
    expect(estimate(e.copy(timeControl: 'G/5 d0')).rating, isNull);
    expect(estimate(e.copy(timeControl: 'unknown')).rating, isNull);
    expect(
      estimate(
        e.copy(
          players: [
            for (final p in e.players)
              p.copy(ratingEvidence: {'category': 'quick'}),
          ],
        ),
      ).rating,
      isNull,
    );
  });
}
