import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/knockout.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/prizes.dart';

var _ids = 0;
String _id() => 'g${_ids++}';
int _num(String id) => int.parse(id.substring(1));

final _prizes = {
  'list': [
    {'id': 'p1', 'kind': 'place', 'place': 1, 'cents': 10000, 'trophy': true},
    {'id': 'p2', 'kind': 'place', 'place': 2, 'cents': 6000, 'trophy': true},
    {'id': 'p3', 'kind': 'place', 'place': 3, 'cents': 3000, 'trophy': true},
  ],
};

Map<String, int> _cash(PrizeAllocation a) => {
  for (final w in a.awards)
    if (w.cents > 0) w.player.id: w.cents,
};

/// Posts the next knockout round. [legs] gives a match's legs from the
/// better seed's side, as `W`, `D` or `L`, by "better-worse" seed IDs;
/// other matches go 2–0 to the better seed.
Event _post(Event e, [Map<String, String> legs = const {}]) {
  final s = e.sections.single;
  var r = proposeRound(e, s, _id);
  Outcome result(Game g) {
    final whiteBetter = _num(g.white) < _num(g.black);
    final key = whiteBetter ? '${g.white}-${g.black}' : '${g.black}-${g.white}';
    final mark = legs[key]?[g.leg - 1] ?? 'W';
    return switch (mark) {
      'D' => Outcome.draw,
      'W' => whiteBetter ? Outcome.whiteWin : Outcome.blackWin,
      _ => whiteBetter ? Outcome.blackWin : Outcome.whiteWin,
    };
  }

  r = r.copy(games: [for (final g in r.games) g.copy(outcome: result(g))]);
  return e.copy(
    sections: [
      knockoutAfterPost(e, s.copy(rounds: [...s.rounds, r])),
    ],
  );
}

Event _knockout(int n, {int games = 2}) => Event(
  id: 'e',
  name: 'Knockout',
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
      bracket: Bracket.fromJson({'gamesPerMatch': games, 'tiebreak': 'none'}),
      prizes: PrizeTable.fromJson(_prizes),
    ),
  ],
);

void main() {
  group('knockout prizes follow the bracket', () {
    test('the runner-up takes 2nd alone, however many points others have', () {
      // p3 wins the play-in 2–0 and loses the semifinal ½–1½: 2½ points,
      // the same as the runner-up p1 (2–0, then ½–1½ in the final).
      var e = _knockout(5);
      e = _post(e);
      e = _post(e, {'p0-p3': 'WD'});
      e = _post(e, {'p0-p1': 'WD'});
      final s = e.sections.single;
      expect(knockoutBracket(e, s).winner, 'p0');
      final a = allocatePrizes(e, s);
      // The two semifinalists are level and share 3rd.
      expect(_cash(a), {'p0': 10000, 'p1': 6000, 'p2': 1500, 'p3': 1500});
      expect(a.awards.map((w) => w.placing), [
        'Winner',
        'Runner-up',
        'Semifinalist',
        'Semifinalist',
      ]);
      final third = a.lines.firstWhere((l) => l.prize.id == 'p3');
      expect(third.trophyWinner, 'p2');
      expect(third.trophyNote, contains('decide by lot'));
      expect(third.trophyNote, contains('the bracket does not rank them'));
    });

    test('the champion wins 1st with fewer points than the runner-up', () {
      // One-game matches: p0 draws both and is advanced by the director;
      // p1 wins the semifinal, so p1 has 1½ points to p0's 1.
      var e = _knockout(4, games: 1);
      e = _post(e, {'p0-p3': 'D'});
      var s = knockoutDecided(e, e.sections.single, 1, 'p0', 'Play-off');
      e = _post(e.copy(sections: [s]), {'p0-p1': 'D'});
      s = knockoutDecided(e, e.sections.single, 1, 'p0', 'Play-off');
      e = e.copy(sections: [s]);
      expect(knockoutBracket(e, s).winner, 'p0');
      final a = allocatePrizes(e, s);
      expect(_cash(a)['p0'], 10000);
      expect(_cash(a)['p1'], 6000);
      expect(a.lines.first.trophyWinner, 'p0');
    });

    test('before the bracket ends, players still in it are level', () {
      final e = _post(_knockout(4));
      final a = allocatePrizes(e, e.sections.single);
      // The finalists share 1st and 2nd for now; the losers share 3rd.
      expect(_cash(a), {'p0': 8000, 'p1': 8000, 'p2': 1500, 'p3': 1500});
    });
  });

  test('ladder prizes follow the ladder, top first, never tied', () {
    final players = [
      for (final id in ['a', 'b', 'c'])
        Player(id: id, name: 'Player $id', rating: 1500),
    ];
    final e = Event(
      id: 'e',
      name: 'Ladder',
      date: '2026-10-10',
      players: players,
      sections: [
        Section(
          id: 's',
          name: 'Ladder',
          players: const ['c', 'a', 'b'],
          format: Format.ladder,
          unrated: true,
          prizes: PrizeTable.fromJson(_prizes),
        ),
      ],
    );
    final a = allocatePrizes(e, e.sections.single);
    expect(_cash(a), {'c': 10000, 'a': 6000, 'b': 3000});
    expect(a.awards.first.placing, '#1 on the ladder');
    expect(a.lines.map((l) => l.trophyNote).join(), isEmpty);
  });

  test('a bughouse partnership wins one prize as a unit', () {
    final players = [
      for (final (i, name) in [
        'Ann',
        'Bob',
        'Cy',
        'Dee',
        'Eve',
        'Flo',
        'Gus',
        'Hal',
      ].indexed)
        Player(id: 'p$i', name: name, rating: 1800 - 50 * i),
    ];
    Game match(int id, int white, int black) => Game(
      id: 'g$id',
      white: 'p${2 * white}',
      black: 'p${2 * black}',
      whitePartner: 'p${2 * white + 1}',
      blackPartner: 'p${2 * black + 1}',
      board: id,
      outcome: Outcome.whiteWin,
    );
    final e = Event(
      id: 'e',
      name: 'Bughouse',
      date: '2026-10-10',
      players: players,
      sections: [
        Section(
          id: 's',
          name: 'Bughouse',
          players: [for (final p in players) p.id],
          format: Format.bughouse,
          plannedRounds: 2,
          unrated: true,
          partners: [
            for (var i = 0; i < 4; i++) ['p${2 * i}', 'p${2 * i + 1}'],
          ],
          rounds: [
            Round(number: 1, games: [match(1, 0, 1), match(2, 2, 3)]),
            Round(number: 2, games: [match(3, 0, 2), match(4, 1, 3)]),
          ],
          prizes: PrizeTable.fromJson(_prizes),
        ),
      ],
    );
    final a = allocatePrizes(e, e.sections.single);
    // Ann / Bob win 1st and its trophy once; the two partnerships on one
    // point share 2nd and 3rd.
    expect(_cash(a), {'p0': 10000, 'p2': 4500, 'p4': 4500});
    expect(a.paidCents, 19000);
    expect(
      a.awards.map((w) => w.name),
      unorderedEquals(['Ann / Bob', 'Cy / Dee', 'Eve / Flo']),
    );
    expect(a.awards.first.name, 'Ann / Bob');
    expect(a.awards.first.trophies.single.id, 'p1');
    expect(a.lines.first.names, {'p0': 'Ann / Bob'});
    expect(
      a.explanations,
      contains(
        allOf(startsWith('2 partnerships tied at 1 ('), contains('Cy / Dee')),
      ),
    );
  });
}
