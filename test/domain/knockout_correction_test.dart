import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/knockout.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/result_correction.dart';

var _ids = 0;
String _id() => 'g${_ids++}';
int _num(String id) => int.parse(id.substring(1));

Event _event(int n) => Event(
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
      bracket: const {'gamesPerMatch': 1, 'tiebreak': 'none'},
    ),
  ],
);

Section _s(Event e) => e.sections.single;

Outcome _betterWins(Game g) =>
    _num(g.white) < _num(g.black) ? Outcome.whiteWin : Outcome.blackWin;

/// Posts the next round as the controller does; [result] may leave a game
/// unreported by returning null.
Event _post(Event e, [Outcome? Function(Game g)? result]) {
  var r = proposeRound(e, _s(e), _id);
  r = r.copy(
    games: [for (final g in r.games) g.copy(outcome: result?.call(g))],
  );
  final next = e.copy(
    sections: [
      knockoutAfterPost(e, _s(e).copy(rounds: [..._s(e).rounds, r])),
    ],
  );
  validateEvent(next);
  return next;
}

Game _game(Event e, int round, String a, String b) => _s(e)
    .rounds[round - 1]
    .games
    .firstWhere((g) => {g.white, g.black}.containsAll([a, b]));

/// The result that makes [winner] win [g].
Outcome _won(Game g, String winner) =>
    g.white == winner ? Outcome.whiteWin : Outcome.blackWin;

void main() {
  test('a result under a posted bracket round needs the later-rounds '
      'review, as in a Swiss', () {
    var e = _post(_event(4), _betterWins);
    final semi = _game(e, 1, 'p0', 'p3');
    expect(ResultCorrection(e, semi.id).hasDependencies, isFalse);
    e = _post(e);
    expect(ResultCorrection(e, semi.id).hasDependencies, isTrue);
  });

  test('a bughouse result under a later round needs the review too', () {
    final e = Event(
      id: 'e',
      name: 'Bughouse',
      date: '2026-10-10',
      players: [for (var i = 0; i < 4; i++) Player(id: 'p$i', name: 'P$i')],
      sections: [
        Section(
          id: 's',
          name: 'Bughouse',
          players: const ['p0', 'p1', 'p2', 'p3'],
          format: Format.bughouse,
          unrated: true,
          partners: const [
            ['p0', 'p1'],
            ['p2', 'p3'],
          ],
          rounds: [
            for (final n in [1, 2])
              Round(
                number: n,
                games: [
                  Game(
                    id: 'g$n',
                    white: 'p0',
                    black: 'p2',
                    whitePartner: 'p1',
                    blackPartner: 'p3',
                    board: 1,
                    outcome: Outcome.whiteWin,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    expect(ResultCorrection(e, 'g1').hasDependencies, isTrue);
    expect(ResultCorrection(e, 'g2').hasDependencies, isFalse);
  });

  test('changing who advanced into an unstarted round unpairs it', () {
    var e = _post(_event(4), _betterWins);
    e = _post(e);
    final semi = _game(e, 1, 'p0', 'p3');
    final review = ResultCorrection(e, semi.id);
    expect(review.replacedStage(_won(semi, 'p3')), (name: 'Final', round: 2));
    expect(review.replacedStage(Outcome.draw), isNull);
    expect(
      () => review.apply(_won(semi, 'p3'), reason: 'Wrong winner entered'),
      throwsA(
        isA<TournamentException>().having(
          (x) => x.message,
          'message',
          allOf(
            contains('changes who advances'),
            contains('Unpair from round 2'),
          ),
        ),
      ),
    );
    e = review.apply(
      _won(semi, 'p3'),
      reason: 'Wrong winner entered',
      reopenFrom: 2,
      confirmedUnstarted: true,
    );
    validateEvent(e);
    expect(_s(e).rounds, hasLength(1));
    expect(_s(e).plannedRounds, 2);
    expect((_s(e).bracket['rounds'] as List).map((r) => r['stage']), [1]);
    // The final is paired again with the player who now advances.
    final r = proposeRound(e, _s(e), _id);
    expect({r.games.single.white, r.games.single.black}, {'p3', 'p1'});
    expect(r.policy, knockoutPolicy);
  });

  test('once the next round is played the bracket says it must be paired '
      'again, and pairs it', () {
    var e = _post(_event(4), _betterWins);
    e = _post(e, _betterWins);
    expect(knockoutBracket(e, _s(e)).winner, 'p0');
    final semi = _game(e, 1, 'p0', 'p3');
    final review = ResultCorrection(e, semi.id);
    // The final has a result, so it cannot be unpaired with the correction.
    expect(review.canReopenFrom(2), isFalse);
    e = review.apply(_won(semi, 'p3'), reason: 'Wrong winner entered');
    var bracket = knockoutBracket(e, _s(e));
    expect(bracket.complete, isFalse);
    expect(bracket.stages.last.replaced.single.low, 'p3');
    expect(
      knockoutBracketLines(e, _s(e)).join('\n'),
      contains('to be paired again: a corrected result changed who advanced'),
    );
    final r = proposeRound(e, _s(e), _id);
    expect(r.policy, knockoutRepairPolicy);
    expect(r.number, 3);
    expect({r.games.single.white, r.games.single.black}, {'p1', 'p3'});
    expect(r.games.single.board, _game(e, 2, 'p0', 'p1').board);
    expect(r.note, contains('Final paired again after a corrected result'));
    expect(r.explanations.single, contains('posted as'));
    e = _post(e, (g) => _won(g, 'p3'));
    bracket = knockoutBracket(e, _s(e));
    expect(bracket.winner, 'p3');
    expect(bracket.stages.last.rounds.map((x) => x.number), [2, 3]);
    expect(_s(e).plannedRounds, 3);
    // The game that was played stays on the record.
    expect(_s(e).rounds[1].games.single.outcome.played, isTrue);
    expect(knockoutPlacings(e, _s(e)), [
      ('p3', 'Winner'),
      ('p1', 'Runner-up'),
      ('p0', 'Semifinalist'),
      ('p2', 'Semifinalist'),
    ]);
  });

  test('the unplayed games of a replaced pairing are removed when it is '
      'paired again', () {
    var e = _post(_event(8), _betterWins);
    // Semifinals: p0 – p3 waits, p1 – p2 is played.
    e = _post(
      e,
      (g) => {g.white, g.black}.contains('p1') ? _betterWins(g) : null,
    );
    final quarter = _game(e, 1, 'p3', 'p4');
    e = ResultCorrection(
      e,
      quarter.id,
    ).apply(_won(quarter, 'p4'), reason: 'Wrong winner entered');
    e = _post(e);
    validateEvent(e);
    expect(_s(e).rounds[1].games.map((g) => {g.white, g.black}), [
      {'p1', 'p2'},
    ]);
    expect(_s(e).rounds[2].policy, knockoutRepairPolicy);
    expect(_s(e).rounds[2].games.map((g) => {g.white, g.black}), [
      {'p0', 'p4'},
    ]);
    expect(knockoutBracket(e, _s(e)).stages[1].replaced, isEmpty);
  });

  test('a replaced round with nothing played is dropped for its '
      'replacement', () {
    var e = _post(_event(4), _betterWins);
    e = _post(e);
    // A result entered without the review (a tool call) keeps the pairing.
    final semi = _game(e, 1, 'p0', 'p3');
    e = e.copy(
      sections: [
        _s(e).copy(
          rounds: [
            for (final r in _s(e).rounds)
              r.copy(
                games: [
                  for (final g in r.games)
                    g.id == semi.id ? g.copy(outcome: _won(g, 'p3')) : g,
                ],
              ),
          ],
        ),
      ],
    );
    expect(knockoutBracket(e, _s(e)).stages.last.replaced, hasLength(1));
    e = _post(e, (g) => _won(g, 'p1'));
    expect(_s(e).rounds, hasLength(2));
    expect(_s(e).rounds.last.number, 2);
    expect(_s(e).rounds.last.policy, knockoutPolicy);
    expect(_s(e).plannedRounds, 2);
    expect(knockoutBracket(e, _s(e)).winner, 'p1');
  });
}
