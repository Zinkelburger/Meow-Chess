import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/knockout.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';

var _ids = 0;
String _id() => 'g${_ids++}';
int _num(String id) => int.parse(id.substring(1));

/// [n] players p0 (strongest) … with a knockout section.
Event _event(int n, {int games = 2, String tiebreak = 'none'}) => Event(
  id: 'e',
  name: 'Club Knockout',
  date: '2026-10-10',
  players: [
    for (var i = 0; i < n; i++)
      Player(id: 'p$i', name: 'Player $i', rating: 2000 - 50 * i),
  ],
  sections: [
    Section(
      id: 's',
      name: 'Knockout',
      players: [for (var i = 0; i < n; i++) 'p$i'],
      format: Format.knockout,
      plannedRounds: 1,
      doubleGames: games == 2,
      bracket: {'gamesPerMatch': games, 'tiebreak': tiebreak},
    ),
  ],
);

Section _section(Event e) => e.sections.single;

/// Posts the next round with [result] recorded on every game, as the
/// controller does: the round appended, then the bracket bookkeeping.
Event _post(Event e, Outcome Function(Game g) result) {
  final s = _section(e);
  var r = proposeRound(e, s, _id);
  r = r.copy(games: [for (final g in r.games) g.copy(outcome: result(g))]);
  final posted = knockoutAfterPost(e, s.copy(rounds: [...s.rounds, r]));
  final next = e.copy(sections: [posted]);
  validateEvent(next);
  return next;
}

Outcome _betterWins(Game g) =>
    _num(g.white) < _num(g.black) ? Outcome.whiteWin : Outcome.blackWin;

/// Board 1 drawn 1–1 (White wins each leg, and colors reverse between
/// legs, so one win each); every other match to the better seed.
Outcome _boardOneDrawn(Game g) =>
    g.board != 1 ? _betterWins(g) : Outcome.whiteWin;

(String, String) _pair(Game g) => (g.white, g.black);

void main() {
  test('five players: bracket of eight, byes to the top three seeds', () {
    final e = _event(5);
    final r = proposeRound(e, _section(e), _id);
    expect(r.policy, knockoutPolicy);
    expect(r.note, startsWith('Quarterfinals'));
    expect(r.games.map(_pair), [('p3', 'p4'), ('p4', 'p3')]);
    expect(r.games.map((g) => g.leg), [1, 2]);
    expect(r.games.map((g) => g.board), [1, 1]);
    expect(r.byes.map((b) => b.player), ['p0', 'p1', 'p2']);
    for (final b in r.byes) {
      expect(b.points, 0);
      expect(b.reason, 'Advances without a game');
      expect(b.allocated, isFalse);
    }
    expect(knockoutBracketSize(5), 8);
    expect(knockoutStages(5), 3);
    expect(knockoutBracket(e, _section(e)).stages.map((s) => s.name), [
      'Quarterfinals',
      'Semifinals',
      'Final',
    ]);
  });

  test(
    'eight players: bracket order, colors alternate, 1 and 2 meet in the final',
    () {
      var e = _event(8);
      final r1 = proposeRound(e, _section(e), _id);
      // Game 1 of each odd-numbered bracket round: the higher seed is white.
      expect(r1.games.where((g) => g.leg == 1).map(_pair), [
        ('p0', 'p7'),
        ('p3', 'p4'),
        ('p1', 'p6'),
        ('p2', 'p5'),
      ]);
      expect(r1.games.where((g) => g.leg == 2).map(_pair), [
        ('p7', 'p0'),
        ('p4', 'p3'),
        ('p6', 'p1'),
        ('p5', 'p2'),
      ]);
      expect(r1.byes, isEmpty);
      e = _post(e, _betterWins);
      expect(_section(e).bracket['seeds'], [for (var i = 0; i < 8; i++) 'p$i']);
      expect(_section(e).plannedRounds, 3);
      final r2 = proposeRound(e, _section(e), _id);
      expect(r2.note, startsWith('Semifinals'));
      // Even-numbered bracket round: the higher seed is black in game 1.
      expect(r2.games.where((g) => g.leg == 1).map(_pair), [
        ('p3', 'p0'),
        ('p2', 'p1'),
      ]);
      e = _post(e, _betterWins);
      final r3 = proposeRound(e, _section(e), _id);
      expect(r3.note, startsWith('Final'));
      expect(r3.games.where((g) => g.leg == 1).map(_pair), [('p0', 'p1')]);
      e = _post(e, _betterWins);
      final bracket = knockoutBracket(e, _section(e));
      expect(bracket.complete, isTrue);
      expect(bracket.winner, 'p0');
      expect(
        () => proposeRound(e, _section(e), _id),
        throwsA(
          isA<TournamentException>().having(
            (x) => x.message,
            'message',
            contains('complete'),
          ),
        ),
      );
      expect(knockoutPlacings(e, _section(e)), [
        ('p0', 'Winner'),
        ('p1', 'Runner-up'),
        ('p2', 'Semifinalist'),
        ('p3', 'Semifinalist'),
        ('p4', 'Quarterfinalist'),
        ('p5', 'Quarterfinalist'),
        ('p6', 'Quarterfinalist'),
        ('p7', 'Quarterfinalist'),
      ]);
      final lines = knockoutBracketLines(e, _section(e));
      expect(lines.first, 'Bracket: 2-game matches · director decides ties');
      expect(lines, contains('Final'));
      expect(lines.last, startsWith('Placings: Player 0 – Winner;'));
    },
  );

  test('sixteen players: round of 16 through the final, no byes', () {
    var e = _event(16);
    final r1 = proposeRound(e, _section(e), _id);
    expect(r1.note, startsWith('Round of 16'));
    expect(r1.games.length, 16);
    expect(r1.byes, isEmpty);
    expect(r1.games.where((g) => g.leg == 1).map((g) => g.white).take(4), [
      'p0',
      'p7',
      'p3',
      'p4',
    ]);
    for (final stage in [
      'Round of 16',
      'Quarterfinals',
      'Semifinals',
      'Final',
    ]) {
      expect(proposeRound(e, _section(e), _id).note, startsWith(stage));
      e = _post(e, _betterWins);
    }
    expect(_section(e).plannedRounds, 4);
    expect(knockoutPlacings(e, _section(e)).take(3), [
      ('p0', 'Winner'),
      ('p1', 'Runner-up'),
      ('p2', 'Semifinalist'),
    ]);
    expect(knockoutPlacings(e, _section(e)).last, ('p15', 'Round of 16'));
  });

  test('one-game matches pair a single leg', () {
    final e = _event(4, games: 1);
    final r = proposeRound(e, _section(e), _id);
    expect(r.games.map(_pair), [('p0', 'p3'), ('p1', 'p2')]);
    expect(r.games.every((g) => g.leg == 1), isTrue);
  });

  test('a drawn match with no tie-break waits for the director', () {
    var e = _event(8);
    e = _post(e, _boardOneDrawn);
    final tied = knockoutBracket(e, _section(e)).stages.first.matches.first;
    expect(tied.status, KnockoutMatchStatus.tied);
    expect(tied.highPoints, 2);
    expect(tied.lowPoints, 2);
    expect(
      () => proposeRound(e, _section(e), _id),
      throwsA(
        isA<TournamentException>().having(
          (x) => x.message,
          'message',
          allOf(contains('board 1'), contains('Choose who advances')),
        ),
      ),
    );
    expect(
      () => knockoutDecided(e, _section(e), 1, 'p3', 'wrong player'),
      throwsA(isA<TournamentException>()),
    );
    expect(
      () => knockoutDecided(e, _section(e), 2, 'p3', 'not drawn'),
      throwsA(isA<TournamentException>()),
    );
    final decided = knockoutDecided(e, _section(e), 1, 'p7', 'Coin toss');
    expect(decided.bracket['rounds'], [
      {
        'stage': 1,
        'name': 'Quarterfinals',
        'rounds': [1],
        'decisions': [
          {'board': 1, 'advanced': 'p7', 'reason': 'Coin toss'},
        ],
      },
    ]);
    e = e.copy(sections: [decided]);
    final match = knockoutBracket(e, _section(e)).stages.first.matches.first;
    expect(match.advanced, 'p7');
    expect(match.byDirector, isTrue);
    expect(match.reason, 'Coin toss');
    final r2 = proposeRound(e, _section(e), _id);
    // Semifinals (even round): #4 p3 is the higher seed, so black in game 1.
    expect(r2.games.where((g) => g.leg == 1).map(_pair), [
      ('p7', 'p3'),
      ('p2', 'p1'),
    ]);
    // Once the next round is posted the decision is fixed.
    e = _post(e, _betterWins);
    expect(
      () => knockoutDecided(e, _section(e), 1, 'p0', 'changed my mind'),
      throwsA(
        isA<TournamentException>().having(
          (x) => x.message,
          'message',
          contains('Semifinals has been posted'),
        ),
      ),
    );
  });

  test('rapid tie-break legs are appended on the same board', () {
    var e = _event(8, tiebreak: 'rapid');
    e = _post(e, _boardOneDrawn);
    final tb = proposeRound(e, _section(e), _id);
    expect(tb.number, 2);
    expect(tb.policy, knockoutPolicy);
    expect(
      tb.note,
      startsWith('Tie-break games (rapid) for the Quarterfinals'),
    );
    expect(tb.games.map((g) => (g.board, g.leg)), [(1, 3), (1, 4)]);
    expect(tb.games.map(_pair), [('p0', 'p7'), ('p7', 'p0')]);
    // Leg 3 to the top seed, leg 4 drawn: 3½–2½.
    e = _post(e, (g) => g.leg == 3 ? Outcome.whiteWin : Outcome.draw);
    final s = _section(e);
    expect(s.rounds.length, 2);
    expect(s.plannedRounds, 4);
    expect(s.bracket['rounds'], [
      {
        'stage': 1,
        'name': 'Quarterfinals',
        'rounds': [1, 2],
        'decisions': [],
      },
    ]);
    final match = knockoutBracket(e, s).stages.first.matches.first;
    expect(match.status, KnockoutMatchStatus.decided);
    expect(match.advanced, 'p0');
    expect(match.highPoints, 5);
    expect(match.lowPoints, 3);
    final r3 = proposeRound(e, s, _id);
    expect(r3.number, 3);
    expect(r3.note, startsWith('Semifinals'));
    expect(r3.games.where((g) => g.leg == 1).map(_pair), [
      ('p3', 'p0'),
      ('p2', 'p1'),
    ]);
    // Still tied after the first pair of tie-break legs: more are posted.
    var again = _event(8, tiebreak: 'blitz');
    again = _post(again, _boardOneDrawn);
    again = _post(
      again,
      // Colors reverse between legs: White winning both is one win each.
      (_) => Outcome.whiteWin,
    );
    final more = proposeRound(again, _section(again), _id);
    expect(more.games.map((g) => g.leg), [5, 6]);
  });

  test('armageddon: one leg, a draw advances black', () {
    var e = _event(4, tiebreak: 'armageddon');
    e = _post(e, _boardOneDrawn);
    final tb = proposeRound(e, _section(e), _id);
    expect(tb.games.map((g) => (g.board, g.leg)), [(1, 3)]);
    expect(tb.games.single.white, 'p0');
    expect(tb.note, contains('armageddon'));
    e = _post(e, (_) => Outcome.draw);
    final match = knockoutBracket(e, _section(e)).stages.first.matches.first;
    expect(match.advanced, 'p3');
    expect(match.reason, contains('Armageddon'));
    expect(proposeRound(e, _section(e), _id).games.first.board, 1);
    expect(proposeRound(e, _section(e), _id).games.map(_pair), [
      ('p3', 'p1'),
      ('p1', 'p3'),
    ]);
  });

  test('unreported games block the next round', () {
    final e = _event(4);
    final s = _section(e);
    final r = proposeRound(e, s, _id);
    final half = r.copy(
      games: [
        for (final g in r.games)
          g.board == 1 ? g.copy(outcome: _betterWins(g)) : g,
      ],
    );
    final posted = e.copy(
      sections: [
        s.copy(rounds: [half]),
      ],
    );
    expect(
      () => knockoutRound(posted, _section(posted), 2, _id),
      throwsA(
        isA<TournamentException>().having(
          (x) => x.message,
          'message',
          contains('board 2'),
        ),
      ),
    );
  });

  test('settings are validated and seeds respect withdrawals', () {
    expect(knockoutSettingsProblem({'gamesPerMatch': 4}), contains('1 or 2'));
    expect(knockoutSettingsProblem({'tiebreak': 'coin'}), contains('none'));
    expect(
      knockoutSettingsProblem({'gamesPerMatch': 2, 'tiebreak': 'blitz'}),
      isNull,
    );
    final one = _event(1);
    expect(knockoutProblem(one, _section(one)), contains('two players'));
    var e = _event(5);
    e = e.copy(
      players: [
        for (final p in e.players) p.id == 'p0' ? p.copy(withdrawn: true) : p,
      ],
    );
    expect(knockoutSeeds(e, _section(e)), ['p1', 'p2', 'p3', 'p4']);
    // Stored seeds win over ratings.
    final seeded = _section(e).copy(
      bracket: {
        ..._section(e).bracket,
        'seeds': ['p4', 'p3'],
      },
    );
    expect(knockoutSeeds(e, seeded), ['p4', 'p3', 'p1', 'p2']);
    expect(knockoutBracketOrder(8), [1, 8, 4, 5, 2, 7, 3, 6]);
    expect(knockoutBracketOrder(16).indexOf(2), 8);
    expect(
      knockoutSummary(_section(_event(4, games: 1, tiebreak: 'rapid'))),
      '1-game matches · rapid tie-break games',
    );
  });
}
