import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import '../support.dart';

Matcher refuses(String text) => throwsA(
  isA<TournamentException>().having(
    (e) => e.message,
    'message',
    contains(text),
  ),
);

/// Commits nothing and leaves both memory and storage exactly as they were.
void expectUnchanged(TournamentController c, void Function() action) {
  final before = c.event!.encode(), audit = c.repository.history().length;
  try {
    action();
  } on TournamentException {
    // Refusals are also required to be side-effect free.
  }
  expect(c.event!.encode(), before);
  expect(c.repository.load()!.encode(), before);
  expect(c.repository.history().length, audit);
}

TournamentController blank() {
  final c = TournamentController(SqliteEventRepository(':memory:'));
  c.create('Commands');
  return c;
}

Future<void> playRound(TournamentController c, {String? sectionId}) async {
  c.post(await c.propose(sectionId: sectionId));
  for (final s in c.event!.sections) {
    for (final g in s.rounds.lastOrNull?.games ?? const <Game>[]) {
      if (!g.outcome.resolved) c.recordResult(g.id, Outcome.draw);
    }
  }
}

void main() {
  test(
    'new round robin excludes withdrawn and already assigned players',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.importPlayers([
        Player(id: 'active1', name: 'Active One'),
        Player(id: 'active2', name: 'Active Two'),
        Player(id: 'absent', name: 'Absent', withdrawn: true),
      ]);
      c.addSection('New round robin', Format.roundRobin, 1);
      final section = c.event!.sections.last;
      expect(section.players, ['active1', 'active2']);
      final draft = await c.propose(sectionId: section.id);
      expect(draft.issues, isEmpty);
      c.post(draft);
      expect(c.event!.sections.last.rounds.single.games, hasLength(1));
      expect(c.repository.load()!.sectionOf('absent'), isNull);
    },
  );
  group('import identity', () {
    test('a member ID is identity; a shared name alone is not', () {
      final c = blank();
      addTearDown(c.dispose);
      c.importPlayers([
        Player(id: 'a', name: 'Sam Lee', memberId: '10000001'),
        Player(id: 'b', name: 'Pat Doe'),
      ]);
      final skipped = c.importPlayers([
        // Same name, different member: a second person.
        Player(id: 'c', name: 'sam lee ', memberId: '10000002'),
        // Same member ID under another spelling: the same person.
        Player(id: 'd', name: 'Samuel Lee', memberId: '10000001'),
        // Same name and one side has no ID: cannot tell, keep the existing.
        Player(id: 'e', name: 'Pat Doe', memberId: '10000003'),
        Player(id: 'f', name: 'Sam Lee'),
        // Duplicates inside one batch are collapsed too.
        Player(id: 'g', name: 'Ada Park'),
        Player(id: 'h', name: 'Ada Park'),
      ]);
      expect(c.event!.players.map((p) => p.id), ['a', 'b', 'c', 'g']);
      expect(skipped, 4);
    });

    test('an import of only existing entries is refused, not committed', () {
      final c = blank();
      addTearDown(c.dispose);
      c.importPlayers([Player(id: 'a', name: 'Sam Lee')]);
      expectUnchanged(
        c,
        () => expect(
          () => c.importPlayers([Player(id: 'z', name: 'Sam Lee')]),
          refuses('No new entries'),
        ),
      );
    });

    test('an edit may not claim another entry\'s member ID', () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final taken = c.event!.players.first.memberId;
      expectUnchanged(
        c,
        () => expect(
          () => c.savePlayer(c.event!.players.last.copy(memberId: taken)),
          refuses('belongs to'),
        ),
      );
    });
  });

  group('results', () {
    test('an identical repeated result creates no revision', () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post(await c.propose());
      final game = c.event!.games.first.id;
      c.recordResult(game, Outcome.whiteWin);
      expectUnchanged(c, () => c.recordResult(game, Outcome.whiteWin));
    });

    test('an unresolved status keeps the TD pairing assumption', () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post(await c.propose());
      final game = c.event!.games.first.id;
      c.setPairingAssumption(game, Outcome.draw, 'Adjudication pending');
      for (final pending in [Outcome.unfinished, Outcome.disputed]) {
        c.recordResult(game, pending);
        final g = c.event!.games.first;
        expect(g.pairingAssumption, Outcome.draw);
        expect(g.pairingReason, 'Adjudication pending');
      }
      c.recordResult(game, Outcome.blackWin);
      expect(c.event!.games.first.pairingAssumption, isNull);
      expect(c.event!.games.first.pairingReason, isEmpty);
    });

    test('a pairing assumption must be a game outcome with a reason', () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post(await c.propose());
      final game = c.event!.games.first.id;
      for (final (outcome, reason) in [
        (Outcome.whiteForfeit, 'Reason'),
        (Outcome.draw, '  '),
      ]) {
        expectUnchanged(
          c,
          () => expect(
            () => c.setPairingAssumption(game, outcome, reason),
            refuses('reason'),
          ),
        );
      }
      c.recordResult(game, Outcome.draw);
      expectUnchanged(
        c,
        () => expect(
          () => c.setPairingAssumption(game, Outcome.draw, 'Late'),
          refuses('unresolved'),
        ),
      );
    });

    test('stale or missing identities are typed refusals', () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      for (final action in <void Function()>[
        () => c.recordResult('missing', Outcome.draw),
        () => c.setPairingAssumption('missing', Outcome.draw, 'r'),
        () => c.startRound('missing'),
        () => c.movePlayers(['p0'], 'missing'),
        () => c.replacePairing('missing', 1, const [], 'r'),
      ]) {
        expectUnchanged(
          c,
          () => expect(action, throwsA(isA<TournamentException>())),
        );
      }
      final section = c.event!.sections.single.id;
      expect(
        () => c.replacePairing(section, 1, const [], 'r'),
        refuses('not been posted'),
      );
      expect(
        () => c.movePlayers(['nobody'], section),
        refuses('no longer exists'),
      );
    });
  });

  group('posted pairings', () {
    test('replacement must keep participants and precede play', () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post(await c.propose());
      final s = c.event!.sections.single, r = s.rounds.single;
      final swapped = [
        r.games[0].copy(white: r.games[0].black, black: r.games[0].white),
        r.games[1],
      ];
      expect(
        () => c.replacePairing(s.id, 1, swapped, ' '),
        refuses('Record why'),
      );
      expect(
        () => c.replacePairing(s.id, 1, [
          r.games[0].copy(black: r.games[1].white),
          r.games[1],
        ], 'Typo'),
        refuses('preserve the participants'),
      );
      c.replacePairing(s.id, 1, swapped, 'Colors announced reversed');
      final replaced = c.event!.sections.single.rounds.single;
      expect(replaced.revision, 2);
      expect(replaced.games.first.white, r.games[0].black);
      expect(replaced.games.first.id, isNot(r.games.first.id));
      expect(replaced.games.last.id, r.games.last.id);
      expectUnchanged(
        c,
        () => expect(
          () => c.recordResult(r.games.first.id, Outcome.whiteWin),
          refuses('no longer exists'),
        ),
      );
      c.recordResult(replaced.games.first.id, Outcome.draw);
      expect(
        () => c.replacePairing(s.id, 1, r.games, 'Too late'),
        refuses('has started'),
      );
    });

    test('replacement preserves an unresolved pairing assumption', () async {
      final c = fixture(count: 4, format: Format.swiss);
      addTearDown(c.dispose);
      c.post(await c.propose());
      final section = c.event!.sections.single;
      final game = section.rounds.single.games.first;
      c.setPairingAssumption(game.id, Outcome.whiteWin, 'Still playing');
      final round = c.event!.sections.single.rounds.single;
      expectUnchanged(
        c,
        () => expect(
          () => c.replacePairing(section.id, 1, [
            round.games.first.copy(white: game.black, black: game.white),
            round.games.last,
          ], 'Reverse colors'),
          refuses('pairing assumption'),
        ),
      );
    });

    test('a bye cannot be reserved for a posted round', () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post(await c.propose());
      expectUnchanged(
        c,
        () => expect(() => c.reserveBye('p0', 1, 1), refuses('posted')),
      );
      c.reserveBye('p0', 3, 1);
      expect(c.event!.player('p0').byes, {3: 1});
      c.reserveBye('p0', 3, -1);
      expect(c.event!.player('p0').byes, isEmpty);
    });
  });

  group('section transitions', () {
    Future<TournamentController> roundRobinAndSwiss() async {
      final c = fixture(count: 10);
      c.change('Clear', c.event!.copy(sections: []));
      c.addSection('RR', Format.roundRobin, 5);
      c.addSection('Swiss', Format.swiss, 5);
      final rr = c.event!.sections.first;
      c.movePlayers(rr.players.skip(6).toList(), c.event!.sections.last.id);
      return c;
    }

    test('partial moves out of a started round robin are refused', () async {
      final c = await roundRobinAndSwiss();
      addTearDown(c.dispose);
      await playRound(c);
      await playRound(c);
      final rr = c.event!.sections.first, swiss = c.event!.sections.last;
      expectUnchanged(
        c,
        () => expect(
          () => c.movePlayers([rr.players.first], swiss.id, reason: 'Left'),
          refuses('Move all of its players together'),
        ),
      );
      // The whole section may still combine, and no played pair repeats.
      c.movePlayers(rr.players, swiss.id, reason: 'Common pool');
      await playRound(c);
      final pairs = <String>[
        for (final g in c.event!.games.where((g) => g.outcome.played))
          ([g.white, g.black]..sort()).join('/'),
      ];
      expect(pairs.toSet().length, pairs.length);
    });

    test('pre-play partial moves keep the schedule complete', () async {
      final c = await roundRobinAndSwiss();
      addTearDown(c.dispose);
      final rr = c.event!.sections.first;
      c.movePlayers([rr.players.first], c.event!.sections.last.id);
      for (var r = 0; r < 5; r++) {
        await playRound(c, sectionId: c.event!.sections.first.id);
      }
      final games = c.event!.sections.first.rounds.expand((r) => r.games);
      final pairs = games.map((g) => ([g.white, g.black]..sort()).join('/'));
      // Five players, five rounds: all ten pairings exactly once.
      expect(pairs.toSet().length, 10);
      expect(pairs.length, 10);
      expect(c.event!.sections.first.finished, true);
    });

    test('moves require equal progress and a reason after play', () async {
      final c = await roundRobinAndSwiss();
      addTearDown(c.dispose);
      await playRound(c, sectionId: c.event!.sections.last.id);
      final rr = c.event!.sections.first, swiss = c.event!.sections.last;
      expect(
        () => c.movePlayers(rr.players, swiss.id, reason: 'x'),
        refuses('different round progress'),
      );
      await playRound(c, sectionId: rr.id);
      expect(
        () => c.movePlayers(rr.players, swiss.id),
        refuses('transition reason'),
      );
    });
  });

  group('removing players', () {
    test('takes an unplayed entry and every reference to it out', () {
      final c = fixture();
      addTearDown(c.dispose);
      c.avoidPair('p0', 'p5', true);
      final quad = c.event!.sections.first;
      c.change(
        'Manual schedule',
        c.event!.copy(
          sections: [
            quad.copy(
              quadPairings: [
                [0, 1, 2, 3],
                [0, 2, 1, 3],
                [0, 3, 1, 2],
              ],
            ),
            ...c.event!.sections.skip(1),
          ],
        ),
      );
      c.removePlayers(['p0', 'p1']);
      final e = c.event!;
      expect(e.players.map((p) => p.id), isNot(contains('p0')));
      expect(e.sections.first.players, ['p2', 'p3']);
      // Roster slots shifted, so the manual schedule no longer applies.
      expect(e.sections.first.quadPairings, isEmpty);
      expect(e.players.every((p) => !p.avoid.contains('p0')), true);
      expect(c.repository.load()!.encode(), e.encode());
      c.undo();
      expect(c.event!.sections.first.players, quad.players);
    });

    test(
      'is refused once the section is paired, until it is unpaired',
      () async {
        final c = fixture(format: Format.swiss);
        addTearDown(c.dispose);
        final first = c.event!.sections.first, last = c.event!.sections.last;
        c.post(await c.propose(sectionId: first.id));
        expectUnchanged(
          c,
          () => expect(
            () => c.removePlayers([first.players.first]),
            refuses('Withdraw Player 00 instead'),
          ),
        );
        // Another section's entrants are still removable.
        c.removePlayers([last.players.first]);
        c.undo();
        c.undo();
        expect(c.event!.sections.first.rounds, isEmpty);
        c.removePlayers([first.players.first]);
        expect(c.event!.sections.first.players, hasLength(3));
      },
    );

    test('an entry who played elsewhere is withdrawn, not removed', () async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      await playRound(c);
      // Their games stay in the first section's history wherever they sit now.
      final [a, b] = c.event!.sections;
      c.change(
        'Detach',
        c.event!.copy(
          sections: [
            a.copy(players: a.players.skip(1).toList()),
            b,
            Section(
              id: 'late',
              name: 'Late',
              players: const ['p0'],
              format: Format.swiss,
              plannedRounds: 3,
              boardStart: 20,
            ),
          ],
        ),
      );
      expect(removeBlocker(c.event!, 'p0'), contains('has played'));
      expect(() => c.removePlayers(['p0']), refuses('Withdraw them instead'));
    });

    test('withdrawing several players is one undoable change', () {
      final c = fixture();
      addTearDown(c.dispose);
      final history = c.repository.history().length;
      c.setWithdrawn(['p0', 'p1', 'p2'], true);
      expect(c.repository.history().length, history + 1);
      expect(c.event!.players.where((p) => p.withdrawn), hasLength(3));
      c.undo();
      expect(c.event!.players.where((p) => p.withdrawn), isEmpty);
    });
  });

  group('undo', () {
    test('walks back one command at a time and stops at creation', () {
      final c = blank();
      addTearDown(c.dispose);
      final created = c.event!.encode();
      c.importPlayers([Player(id: 'a', name: 'A')]);
      c.savePlayer(c.event!.player('a').copy(notes: 'n'));
      expect(c.undoLabel, 'Edit A');
      c.undo();
      expect(c.event!.player('a').notes, '');
      c.undo();
      expect(c.event!.players, isEmpty);
      expect(c.undoLabel, isNull);
      final revision = c.event!.revision;
      c.undo();
      expect(c.event!.revision, revision);
      // Undo creates new revisions; it never rewinds the revision counter.
      expect(Event.decode(created).revision, lessThan(revision));
    });

    test('a new command after undo is undone before older ones', () {
      final c = blank();
      addTearDown(c.dispose);
      c.importPlayers([Player(id: 'a', name: 'A')]);
      c.savePlayer(c.event!.player('a').copy(notes: 'first'));
      c.undo();
      c.savePlayer(c.event!.player('a').copy(notes: 'second'));
      c.undo();
      expect(c.event!.player('a').notes, '');
      c.undo();
      expect(c.event!.players, isEmpty);
    });

    test('every command keeps a snapshot, so undo reaches creation', () {
      final c = blank();
      addTearDown(c.dispose);
      c.importPlayers([Player(id: 'a', name: 'A')]);
      for (var i = 0; i < 120; i++) {
        c.savePlayer(c.event!.player('a').copy(notes: '$i'));
      }
      var undone = 0;
      while (c.undoLabel != null) {
        c.undo();
        undone++;
      }
      expect(undone, 121);
      expect(c.event!.players, isEmpty);
      expect(
        c.repository.history().where((h) => h['action'] == 'Edit A').length,
        120,
      );
    });
  });

  test('an unchanged dialog save creates no revision', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    expectUnchanged(
      c,
      () => c.change('Edit event settings', c.event!.copy(name: c.event!.name)),
    );
  });

  test('invalid event settings are refused before storage', () {
    final c = blank();
    addTearDown(c.dispose);
    for (final invalid in [
      c.event!.copy(date: '2026-02-30'),
      c.event!.copy(name: '  '),
    ]) {
      expectUnchanged(
        c,
        () => expect(
          () => c.change('Edit', invalid),
          throwsA(isA<TournamentException>()),
        ),
      );
    }
  });
  test(
    'a quad left with the wrong number of players pairs as a small Swiss',
    () async {
      final c = fixture();
      addTearDown(c.dispose);
      final [quad1, quad2] = c.event!.sections;
      c.movePlayers([quad1.players.last], quad2.id);
      final batch = await c.propose();
      expect(batch.issues, isEmpty);
      expect(batch.rounds[quad1.id]!.policy, 'score-swiss-pilot-v1');
      expect(batch.rounds[quad2.id]!.policy, 'score-swiss-pilot-v1');
      // Three players: one game and a bye; five players: two games and a bye.
      expect(batch.rounds[quad1.id]!.games, hasLength(1));
      expect(batch.rounds[quad2.id]!.games, hasLength(2));
      c.post(batch);
      expect(c.event!.sections.map((s) => s.format), [
        Format.swiss,
        Format.swiss,
      ]);
      expect(c.repository.load()!.sections.map((s) => s.format), [
        Format.swiss,
        Format.swiss,
      ]);
    },
  );

  test(
    'a quad restored to four players before round one pairs as a quad',
    () async {
      final c = fixture();
      addTearDown(c.dispose);
      final [quad1, quad2] = c.event!.sections;
      c.movePlayers([quad1.players.last], quad2.id);
      c.movePlayers([quad2.players.first], quad1.id);
      final batch = await c.propose();
      expect(
        batch.rounds.values.map((r) => r.policy),
        everyElement('quad-30G-seeded-v1'),
      );
    },
  );

  test('createSections takes exactly the chosen players', () {
    final c = fixture(count: 8);
    addTearDown(c.dispose);
    final [quad1, quad2] = c.event!.sections;
    // Two from each quad into a new Swiss; everyone else stays put.
    final chosen = [quad1.players[0], quad1.players[1], quad2.players[2]];
    final [id] = c.createSections(
      chosen,
      format: Format.swiss,
      name: 'Reserve',
      rounds: 4,
    );
    final reserve = c.event!.sections.firstWhere((s) => s.id == id);
    expect(reserve.players.toSet(), chosen.toSet());
    expect(reserve.plannedRounds, 4);
    expect(c.event!.sections.first.players, quad1.players.skip(2));
    expect(c.event!.sections[1].players, hasLength(3));
    expect(
      () => c.createSections([], format: Format.swiss, name: 'reserve'),
      refuses('already a section called'),
    );
    c.undo();
    expect(c.event!.sections.map((s) => s.players.length), [4, 4]);

    // Re-making quads from everyone empties and replaces the old ones.
    final everyone = [for (final p in c.event!.players) p.id];
    final ids = c.createSections(everyone, format: Format.quad);
    expect(ids, hasLength(2));
    expect(c.event!.sections.map((s) => s.name), ['Quad 1', 'Quad 2']);
    expect(c.event!.sections.every((s) => ids.contains(s.id)), true);
    expect(c.event!.sections.first.boardStart, 1);
    expect(c.event!.sections.last.boardStart, 3);

    // An empty section, then players in a paired section are refused.
    c.createSections([], format: Format.swiss, name: 'Side', rounds: 3);
    expect(c.event!.sections.last.players, isEmpty);
  });

  test('createSections refuses players whose section is paired', () async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    c.post(await c.propose());
    final paired = c.event!.sections.single.players.first;
    expectUnchanged(
      c,
      () => c.createSections([paired], format: Format.swiss, name: 'X'),
    );
    expect(
      () => c.createSections([paired], format: Format.swiss, name: 'X'),
      refuses('has been paired'),
    );
  });
}
