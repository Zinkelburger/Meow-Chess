import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/holland.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';

Event field(int n) => Event(
  id: 'event',
  name: 'Friday Blitz Holland',
  date: '2026-10-10',
  players: [
    for (var i = 0; i < n; i++)
      Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 25),
  ],
);

int counter = 0;
String nextId() => 'id${counter++}';

/// Every prelim of [e] played to the end: the higher-rated player wins every
/// game, except [draws] which are drawn.
Event playOut(Event e, {Set<String> draws = const {}}) {
  var event = e;
  for (final s in e.sections) {
    final rounds = <Round>[];
    var section = s;
    for (var n = 1; n <= s.plannedRounds; n++) {
      final round = scheduledRound(event, section, n, (_, w, b) => '$n-$w-$b');
      final played = round.copy(
        games: [
          for (final g in round.games)
            g.copy(
              outcome: draws.contains(g.id)
                  ? Outcome.draw
                  : event.player(g.white).rating > event.player(g.black).rating
                  ? Outcome.whiteWin
                  : Outcome.blackWin,
            ),
        ],
        postedAt: 'now',
      );
      rounds.add(played);
      section = section.copy(rounds: rounds);
    }
    event = event.copy(
      sections: [for (final x in event.sections) x.id == s.id ? section : x],
    );
  }
  return event;
}

void main() {
  group('planHolland', () {
    test('30H: three balanced prelims by snake seeding', () {
      final e = field(12);
      final prelims = planHolland(
        e,
        e.players,
        groups: 3,
        qualifiers: 2,
        id: nextId,
      );
      expect(prelims.map((s) => s.name), ['Prelim 1', 'Prelim 2', 'Prelim 3']);
      expect(prelims.map((s) => s.format), everyElement(Format.roundRobin));
      expect(prelims.map((s) => s.plannedRounds), [3, 3, 3]);
      expect(prelims.map((s) => s.boardStart), [1, 3, 5]);
      expect(prelims[0].players, ['p0', 'p5', 'p6', 'p11']);
      expect(prelims[1].players, ['p1', 'p4', 'p7', 'p10']);
      expect(prelims[2].players, ['p2', 'p3', 'p8', 'p9']);
      final groups = prelims.map(hollandGroup).toSet();
      expect(groups, hasLength(1));
      expect(prelims.every(isHollandPrelim), isTrue);
      expect(prelims.map(hollandQualifiers), everyElement(2));
      expect(prelims.map(hollandUnbalanced), everyElement(isFalse));
    });

    test('30I: the top-rated fill Prelim 1, the next Prelim 2', () {
      final e = field(11);
      final prelims = planHolland(
        e,
        e.players,
        groups: 3,
        qualifiers: 1,
        unbalanced: true,
        id: nextId,
      );
      expect(prelims[0].players, ['p0', 'p1', 'p2', 'p3']);
      expect(prelims[1].players, ['p4', 'p5', 'p6', 'p7']);
      expect(prelims[2].players, ['p8', 'p9', 'p10']);
      expect(prelims.map((s) => s.plannedRounds), [3, 3, 3]);
      expect(prelims.map(hollandUnbalanced), everyElement(isTrue));
    });

    test('names skip existing sections and withdrawn players stay out', () {
      final base = field(9);
      final e = base.copy(
        sections: [Section(id: 'x', name: 'prelim 1', players: const [])],
        players: [
          for (final p in base.players)
            p.id == 'p8' ? p.copy(withdrawn: true) : p,
        ],
      );
      final prelims = planHolland(
        e,
        e.players,
        groups: 2,
        qualifiers: 1,
        id: nextId,
      );
      expect(prelims.map((s) => s.name), ['Prelim 2', 'Prelim 3']);
      expect(prelims.expand((s) => s.players), isNot(contains('p8')));
    });

    test('refuses too few players or too many qualifiers plainly', () {
      final e = field(5);
      expect(
        () => planHolland(e, e.players, groups: 2, qualifiers: 1, id: nextId),
        throwsA(
          isA<TournamentException>().having(
            (x) => x.message,
            'message',
            contains('fewer than three'),
          ),
        ),
      );
      final eight = field(8);
      expect(
        () => planHolland(
          eight,
          eight.players,
          groups: 2,
          qualifiers: 4,
          id: nextId,
        ),
        throwsA(
          isA<TournamentException>().having(
            (x) => x.message,
            'message',
            contains('can send 1 to 3'),
          ),
        ),
      );
      expect(
        () => planHolland(
          eight,
          eight.players,
          groups: 1,
          qualifiers: 1,
          id: nextId,
        ),
        throwsA(isA<TournamentException>()),
      );
    });
  });

  group('finalsFor', () {
    test('refuses while a prelim is unfinished, naming it', () {
      final e = field(8);
      final prelims = planHolland(
        e,
        e.players,
        groups: 2,
        qualifiers: 2,
        id: nextId,
      );
      final event = e.copy(sections: prelims);
      final group = hollandGroup(prelims.first);
      expect(hollandProgress(event, group), (finished: 0, total: 2));
      expect(
        hollandFinalProblem(event, group),
        '0 of 2 prelims finished. Prelim 1, Prelim 2 still have games to play.',
      );
      expect(
        () => finalsFor(event, group, nextId),
        throwsA(isA<TournamentException>()),
      );
    });

    test('takes the top qualifiers of each prelim as fresh entries', () {
      final e = field(8);
      final prelims = planHolland(
        e,
        e.players,
        groups: 2,
        qualifiers: 2,
        id: nextId,
      );
      final event = playOut(e.copy(sections: prelims));
      final group = hollandGroup(prelims.first);
      expect(hollandFinalProblem(event, group), isNull);
      final (:section, :entries) = finalsFor(event, group, nextId);
      expect(section.name, 'Final');
      expect(section.format, Format.roundRobin);
      expect(hollandRole(section), 'final');
      expect(hollandGroup(section), group);
      expect(section.plannedRounds, 3);
      expect(section.boardStart, 5);
      // The strongest two of each snake-seeded prelim: p0, p3 and p1, p2.
      expect(entries.map((p) => p.personId), ['p0', 'p3', 'p1', 'p2']);
      expect(
        entries.map((p) => p.id).toSet().intersection({'p0', 'p1'}),
        isEmpty,
      );
      expect(section.players, entries.map((p) => p.id));
      // The final is a fresh competition: the entries carry no score, so
      // the combined event validates and the prelim games stay put.
      final combined = event.copy(
        players: [...event.players, ...entries],
        sections: [...event.sections, section],
      );
      validateEvent(combined);
      expect(hollandFinalOf(combined, group)?.id, section.id);
      expect(
        hollandFinalProblem(combined, group),
        contains('already been created'),
      );
    });

    test(
      '30I: plus scores from Prelim 1, two from Prelim 2, winners after',
      () {
        final e = field(12);
        final prelims = planHolland(
          e,
          e.players,
          groups: 3,
          qualifiers: 1,
          unbalanced: true,
          id: nextId,
        );
        final event = playOut(e.copy(sections: prelims));
        final (:section, :entries) = finalsFor(
          event,
          hollandGroup(prelims.first),
          nextId,
        );
        // Rating order wins everything: in Prelim 1 (p0–p3) only p0 (3/3)
        // and p1 (2/3) have plus scores; Prelim 2 sends p4 and p5; Prelim 3
        // sends its winner p8.
        expect(entries.map((p) => p.personId), ['p0', 'p1', 'p4', 'p5', 'p8']);
        expect(section.plannedRounds, 5);
      },
    );

    test('a tie at the cut uses the tie-breaks, and a dead tie the lot', () {
      final e = field(8);
      final prelims = planHolland(
        e,
        e.players,
        groups: 2,
        qualifiers: 1,
        id: nextId,
      );
      // Prelim 1 is p0, p3, p4, p7. Let p3 beat p0 and p7 beat p3: p0 and
      // p3 both finish 2/3, and p3 takes the one place on Sonneborn-Berger
      // and the head-to-head (34F).
      var event = playOut(e.copy(sections: prelims));
      final first = event.sections.first;
      Game upset(Game g, String winner) => g.copy(
        outcome: g.white == winner ? Outcome.whiteWin : Outcome.blackWin,
      );
      event = event.copy(
        sections: [
          first.copy(
            rounds: [
              for (final r in first.rounds)
                r.copy(
                  games: [
                    for (final g in r.games)
                      {g.white, g.black}.containsAll({'p0', 'p3'})
                          ? upset(g, 'p3')
                          : {g.white, g.black}.containsAll({'p3', 'p7'})
                          ? upset(g, 'p7')
                          : g,
                  ],
                ),
            ],
          ),
          ...event.sections.skip(1),
        ],
      );
      final group = hollandGroup(prelims.first);
      final (:section, :entries) = finalsFor(event, group, nextId);
      expect(entries.first.personId, 'p3');
      expect(section.plannedRounds, 1);

      // A 3-player prelim where every game is drawn is a dead tie: no seed
      // refuses with the names, a seed picks by lot.
      final three = field(6);
      final small = planHolland(
        three,
        three.players,
        groups: 2,
        qualifiers: 1,
        id: nextId,
      );
      final drawn = playOut(
        three.copy(sections: small),
        draws: {
          for (var n = 1; n <= 3; n++)
            for (final a in ['p0', 'p3', 'p4'])
              for (final b in ['p0', 'p3', 'p4']) '$n-$a-$b',
        },
      );
      final g = hollandGroup(small.first);
      expect(
        () => finalsFor(drawn, g, nextId),
        throwsA(
          isA<TournamentException>().having(
            (x) => x.message,
            'message',
            allOf(contains('tied on every tie-break'), contains('34E13')),
          ),
        ),
      );
      final byLot = finalsFor(drawn, g, nextId, seed: 7);
      expect(byLot.entries, hasLength(2));
      expect(byLot.entries.first.personId, isIn(['p0', 'p3', 'p4']));
      expect(byLot.entries.last.personId, 'p1');
      // The same seed draws the same name.
      expect(
        finalsFor(drawn, g, nextId, seed: 7).entries.first.personId,
        byLot.entries.first.personId,
      );
    });
  });
}
