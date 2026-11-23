import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/posted_results.dart';

Event event({
  Outcome first = Outcome.unreported,
  Outcome second = Outcome.unreported,
  String section = 'Open',
}) => Event(
  id: 'e',
  name: 'Test',
  date: '2026-11-21',
  players: [
    Player(id: 'a', name: 'Winter, Shea'),
    Player(id: 'b', name: 'Damon Cai'),
    Player(id: 'c', name: 'José Núñez'),
    Player(id: 'd', name: 'Lee Park'),
  ],
  sections: [
    Section(
      id: 's',
      name: section,
      players: const ['a', 'b', 'c', 'd'],
      rounds: [
        Round(
          number: 1,
          games: [
            Game(id: 'g1', white: 'a', black: 'b', board: 1, outcome: first),
            Game(id: 'g2', white: 'c', black: 'd', board: 2, outcome: second),
          ],
        ),
      ],
    ),
  ],
);

PostedRound page({
  String section = 'Open',
  int round = 1,
  List<PostedGame>? games,
}) => PostedRound(
  section: section,
  round: round,
  games:
      games ??
      const [
        PostedGame(
          board: 1,
          white: 'Shea Winter',
          black: 'Damon Cai',
          whiteResult: '1',
          blackResult: '0',
        ),
        PostedGame(board: 2, white: 'Jose Nunez', black: 'Lee Park'),
      ],
);

void main() {
  test(
    'result cells read as outcomes; what cannot be entered reads as none',
    () {
      expect(postedOutcome('1', '0'), Outcome.whiteWin);
      expect(postedOutcome('0', '1'), Outcome.blackWin);
      expect(postedOutcome('½', '½'), Outcome.draw);
      expect(postedOutcome('&frac12;', '1/2'), Outcome.draw);
      expect(postedOutcome('0.5', '0.5'), Outcome.draw);
      expect(postedOutcome('1.0', '0.0'), Outcome.whiteWin);
      expect(postedOutcome('1X', '0F'), Outcome.whiteForfeit);
      expect(postedOutcome('0F', '1X'), Outcome.blackForfeit);
      expect(postedOutcome('0.0F', '1.0X'), Outcome.blackForfeit);
      expect(postedOutcome('0F', '0F'), Outcome.doubleForfeit);
      // A forfeit draw, a cleared result, nonsense, and scores that do not
      // add up to one game are never entered.
      for (final (w, b) in [
        ('½Z', '½Z'),
        ('0U', '0U'),
        ('', ''),
        ('1', ''),
        ('1', '1'),
        ('0', '0'),
        ('½', '0'),
        ('W', 'L'),
        ('2', '0'),
      ]) {
        expect(postedOutcome(w, b), isNull, reason: '$w $b');
      }
      expect(const PostedGame(white: 'A', black: 'B').hasResult, isFalse);
      expect(
        const PostedGame(
          white: 'A',
          black: 'B',
          whiteResult: '0U',
          blackResult: '0U',
        ).hasResult,
        isFalse,
      );
      const forfeitDraw = PostedGame(
        white: 'A',
        black: 'B',
        whiteResult: '½Z',
        blackResult: '½Z',
      );
      expect(forfeitDraw.hasResult, isTrue);
      expect(forfeitDraw.understood, isFalse);
    },
  );

  test('names match across word order, accents and capitals', () {
    expect(personKey('Winter, Shea'), personKey('shea WINTER'));
    expect(personKey('José Núñez'), personKey('NUNEZ,JOSE'));
    expect(personKey('Shea Winter'), isNot(personKey('Shea Winters')));
  });

  test('a result on the website is taken for the matching board', () {
    final reading = readPostedResults(event(), [page()]);
    expect(reading.take, {'g1': Outcome.whiteWin});
    expect(reading.following, ['Open round 1']);
    expect(reading.differences, isEmpty);
    expect(reading.problems, isEmpty);
  });

  test('one board that is not this round\'s stops the whole round', () {
    final reading = readPostedResults(event(), [
      page(
        games: const [
          PostedGame(
            board: 1,
            white: 'Shea Winter',
            black: 'Damon Cai',
            whiteResult: '1',
            blackResult: '0',
          ),
          PostedGame(board: 2, white: 'Jose Nunez', black: 'Someone Else'),
        ],
      ),
    ]);
    expect(reading.take, isEmpty);
    expect(reading.following, isEmpty);
    expect(reading.problems.single, contains('other pairings'));
    expect(
      reading.problems.single,
      contains('board 2, Jose Nunez – Someone Else'),
    );
  });

  test('colors the other way round are other pairings', () {
    final reading = readPostedResults(event(), [
      page(
        games: const [
          PostedGame(
            board: 1,
            white: 'Damon Cai',
            black: 'Shea Winter',
            whiteResult: '0',
            blackResult: '1',
          ),
        ],
      ),
    ]);
    expect(reading.take, isEmpty);
    expect(reading.problems.single, contains('other pairings'));
  });

  test('another round or another section on the website takes nothing', () {
    final wrongRound = readPostedResults(event(), [page(round: 2)]);
    expect(wrongRound.take, isEmpty);
    expect(
      wrongRound.problems,
      contains(
        'The website shows Open round 2, which this event does not have.',
      ),
    );
    expect(
      wrongRound.problems,
      contains('Open round 1 is not on the website yet (it shows round 2).'),
    );
    final notYet = readPostedResults(event(), [
      const PostedRound(section: 'Open', round: 0, games: []),
    ]);
    expect(notYet.take, isEmpty);
    expect(notYet.problems, ['Open round 1 is not on the website yet.']);
    final nothing = readPostedResults(event(), const []);
    expect(nothing.problems, ['Open round 1 is not on the website yet.']);
  });

  test(
    'a section named differently is followed when its boards are the same',
    () {
      final same = readPostedResults(event(section: 'Championship'), [page()]);
      expect(same.take, {'g1': Outcome.whiteWin});
      // SwissSys file names lose punctuation.
      final punctuated = readPostedResults(event(section: 'U1800/U1600'), [
        page(section: 'U1800 U1600'),
      ]);
      expect(punctuated.take, {'g1': Outcome.whiteWin});
    },
  );

  test('a result entered here is never replaced; the two are listed', () {
    final reading = readPostedResults(event(first: Outcome.draw), [page()]);
    expect(reading.take, isEmpty);
    expect(reading.corrections, isEmpty);
    final difference = reading.differences.single;
    expect(difference.gameId, 'g1');
    expect(difference.here, Outcome.draw);
    expect(difference.website, Outcome.whiteWin);
    expect(
      difference.describe(nameSection: false),
      'board 1, Winter, Shea – Damon Cai: the website says 1–0, entered here as ½–½.',
    );
  });

  test('a result taken from the website follows a correction made there', () {
    final reading = readPostedResults(
      event(first: Outcome.draw),
      [page()],
      taken: {'g1': Outcome.draw},
    );
    expect(reading.corrections, {'g1': Outcome.whiteWin});
    expect(reading.differences, isEmpty);
  });

  test('a result taken back here is offered, not entered again', () {
    final reading = readPostedResults(
      event(),
      [page()],
      taken: {'g1': Outcome.whiteWin},
    );
    expect(reading.take, isEmpty);
    expect(reading.differences.single.why, contains('taken back here'));
    expect(reading.differences.single.website, Outcome.whiteWin);
  });

  test('a disputed game and a held board are left to the director', () {
    final disputed = readPostedResults(event(first: Outcome.disputed), [
      page(),
    ]);
    expect(disputed.take, isEmpty);
    expect(disputed.differences.single.why, contains('disputed'));
    final held = readPostedResults(event(), [page()], held: {'g1'});
    expect(held.take, isEmpty);
    expect(held.differences.single.why, contains('later round'));
    // Refused because a later round is paired: the director enters it, so
    // no Use button offers to enter it past that round.
    expect(held.differences.single.byHand, isTrue);
  });

  test('a result with no equivalent here is listed while the board waits', () {
    PostedRound forfeitDraw() => page(
      games: const [
        PostedGame(
          board: 1,
          white: 'Shea Winter',
          black: 'Damon Cai',
          whiteResult: '½Z',
          blackResult: '½Z',
        ),
      ],
    );
    final waiting = readPostedResults(event(), [forfeitDraw()]);
    expect(waiting.take, isEmpty);
    expect(waiting.differences.single.website, isNull);
    expect(
      waiting.differences.single.describe(nameSection: true),
      contains(
        'Open board 1, Winter, Shea – Damon Cai: the website says ½Z–½Z',
      ),
    );
    expect(waiting.problems, ['Open round 1: board 2 is not on the website.']);
    final settled = readPostedResults(
      event(first: Outcome.draw, second: Outcome.draw),
      [forfeitDraw()],
    );
    expect(settled.differences, isEmpty);
    expect(settled.problems, isEmpty);
  });

  test('a finished event with a matching page has nothing to do', () {
    final reading = readPostedResults(
      event(first: Outcome.whiteWin, second: Outcome.draw),
      [page()],
    );
    expect(reading.take, isEmpty);
    expect(reading.differences, isEmpty);
    expect(reading.problems, isEmpty);
    expect(reading.following, ['Open round 1']);
  });

  test(
    'once a later round is paired, the website changes nothing in the round',
    () {
      // Board 1 came from the website as 1–0, and round 2 has been paired.
      final e = event(first: Outcome.whiteWin, second: Outcome.unreported);
      final paired = e.copy(
        sections: [
          e.sections.single.copy(
            rounds: [
              ...e.sections.single.rounds,
              Round(
                number: 2,
                games: [Game(id: 'g3', white: 'b', black: 'c', board: 1)],
              ),
            ],
          ),
        ],
      );
      final settled = settledGames(paired);
      expect(settled, {'g1', 'g2'});
      final reading = readPostedResults(
        paired,
        [
          page(
            games: const [
              // Corrected on the website after round 2 was paired.
              PostedGame(
                board: 1,
                white: 'Shea Winter',
                black: 'Damon Cai',
                whiteResult: '0',
                blackResult: '1',
              ),
              // A board still waiting: not taken either.
              PostedGame(
                board: 2,
                white: 'Jose Nunez',
                black: 'Lee Park',
                whiteResult: '½',
                blackResult: '½',
              ),
            ],
          ),
        ],
        taken: const {'g1': Outcome.whiteWin},
        settled: settled,
      );
      expect(reading.take, isEmpty);
      expect(reading.corrections, isEmpty);
      expect(reading.following, isEmpty);
      expect(reading.differences.map((d) => (d.gameId, d.byHand)), [
        ('g1', true),
        ('g2', true),
      ]);
      expect(
        reading.differences.first.describe(nameSection: false),
        'board 1, Winter, Shea – Damon Cai: the website says 0–1. A later '
        'round is paired, so the website no longer changes this one. Enter '
        'it yourself if it is right.',
      );
      // Without it, the same page would have followed the correction.
      final before = readPostedResults(
        paired,
        [
          page(games: [page().games.first.copyWithResult('0', '1')]),
        ],
        taken: const {'g1': Outcome.whiteWin},
      );
      expect(before.corrections, {'g1': Outcome.blackWin});
    },
  );

  test('a result a transfer carried elsewhere is settled too', () {
    final e = event();
    expect(settledGames(e), isEmpty);
    expect(settledGames(e, dependsOn: (id) => id == 'g2'), {'g2'});
  });
}

extension on PostedGame {
  PostedGame copyWithResult(String white, String black) => PostedGame(
    board: board,
    white: this.white,
    black: this.black,
    whiteResult: white,
    blackResult: black,
  );
}
