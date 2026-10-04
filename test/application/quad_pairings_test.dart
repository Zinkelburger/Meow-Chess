import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import '../support.dart';

List<List<String>> schedule(Section s) => [
  for (final r in sectionSchedule(s))
    [
      for (final p in r) ...[p.$1!, p.$2!],
    ],
];

void main() {
  test(
    'manual opponents and colors persist, post, print and undo together',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final s = c.event!.sections.single;
      final original = schedule(s);
      final edited = [original[1].reversed.toList(), original[0], original[2]];
      c.editQuadPairings(s.id, edited, c.event!.revision);
      final decoded = Event.decode(c.event!.encode());
      expect(schedule(decoded.sections.single), edited);
      final paper = reportPairingRounds(decoded.sections.single);
      expect(paper.first.games.first.white, edited[0][0]);
      expect(paper[1].games.last.black, edited[1][3]);
      c.undo();
      expect(schedule(c.event!.sections.single), original);
      c.redo();
      for (var n = 0; n < 3; n++) {
        c.post(await c.propose());
        final r = c.event!.sections.single.rounds.last;
        expect([
          for (final g in r.games) ...[g.white, g.black],
        ], edited[n]);
        for (final g in r.games) {
          c.recordResult(g.id, Outcome.draw);
        }
      }
    },
  );

  test(
    'editing a posted quad renames only changed games and revises their round',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post(await c.propose());
      final s = c.event!.sections.single, r = s.rounds.single;
      final edited = schedule(s);
      edited[0] = [edited[0][1], edited[0][0], edited[0][2], edited[0][3]];
      c.editQuadPairings(s.id, edited, c.event!.revision);
      final saved = c.event!.sections.single.rounds.single;
      // A changed pairing is a new game; an unchanged one keeps its identity.
      expect(saved.games.first.id, isNot(r.games.first.id));
      expect(saved.games.last.id, r.games.last.id);
      expect(saved.games.first.white, r.games.first.black);
      expect(saved.revision, r.revision + 1);
      expect(saved.games.every((g) => g.outcome == Outcome.unreported), isTrue);
    },
  );

  test(
    'played rounds stay intact while remaining opponents can change',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post(await c.propose());
      for (final g in c.event!.games.toList()) {
        c.recordResult(g.id, Outcome.draw);
      }
      c.post(await c.propose());
      final s = c.event!.sections.single;
      final edited = schedule(s);
      final swapped = [edited[0], edited[2], edited[1]];
      c.editQuadPairings(s.id, swapped, c.event!.revision);
      expect(
        c.event!.sections.single.rounds.first.toJson(),
        s.rounds.first.toJson(),
      );
      expect(
        c.event!.sections.single.rounds.last.games.first.white,
        swapped[1][0],
      );
      final invalid = [edited[0].reversed.toList(), edited[2], edited[1]];
      final before = c.event!.encode();
      expect(
        () => c.editQuadPairings(s.id, invalid, c.event!.revision),
        throwsA(isA<TournamentException>()),
      );
      expect(c.event!.encode(), before);
    },
  );

  test('stale, duplicate and incomplete schedules fail atomically', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final s = c.event!.sections.single,
        rows = schedule(c.event!.sections.single);
    final before = c.event!.encode();
    for (final rowsToTry in [
      [rows[0], rows[0], rows[2]],
      [rows[0]],
      [
        ['p0', 'p0', 'p2', 'p3'],
        rows[1],
        rows[2],
      ],
    ]) {
      expect(
        () => c.editQuadPairings(s.id, rowsToTry, c.event!.revision),
        throwsA(isA<TournamentException>()),
      );
      expect(c.event!.encode(), before);
    }
    expect(
      () => c.editQuadPairings(s.id, rows, c.event!.revision - 1),
      throwsA(isA<TournamentException>()),
    );
  });

  test('double games stay reversed and assumptions block editing', () async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    c.change(
      'Both colors',
      c.event!.copy(
        sections: [c.event!.sections.single.copy(doubleGames: true)],
      ),
    );
    c.post(await c.propose());
    final s = c.event!.sections.single,
        rows = schedule(c.event!.sections.single);
    final edited = [rows[1], rows[0], rows[2]];
    c.editQuadPairings(s.id, edited, c.event!.revision);
    final games = c.event!.sections.single.rounds.single.games;
    expect(games[0].white, games[1].black);
    expect(games[0].black, games[1].white);
    c.setPairingAssumption(games.first.id, Outcome.draw, 'Still playing');
    expect(
      () => c.editQuadPairings(s.id, rows, c.event!.revision),
      throwsA(isA<TournamentException>()),
    );
  });

  group('projected quad schedule', () {
    Section quad(TournamentController c) => c.event!.sections.first;
    List<Round> projected(TournamentController c) =>
        c.pairingEvent.sections.firstWhere((s) => s.id == quad(c).id).rounds;

    test('a result saves only the rounds through its own', () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      expect(projected(c), hasLength(3));
      final game = projected(c).first.games.first;
      c.recordResult(game.id, Outcome.whiteWin);
      final saved = quad(c).rounds.single;
      expect(saved.number, 1);
      expect(saved.postedAt, isNotNull);
      expect(saved.policy, 'quad-30G-seeded-v1');
      expect(saved.games.first.outcome, Outcome.whiteWin);
      // Round 2 is still unposted, so it can still take a requested bye.
      c.reserveBye('p0', 2, 1);
      expect(projected(c), hasLength(1));
      expect(c.quadScheduleIssues[quad(c).id], contains('Round 2'));
    });

    test('a later result saves the earlier rounds with it, in order', () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final game = projected(c)[1].games.first;
      c.recordResult(game.id, Outcome.draw);
      expect(quad(c).rounds.map((r) => r.number), [1, 2]);
      expect(
        c.event!.games.singleWhere((g) => g.id == game.id).outcome,
        Outcome.draw,
      );
    });

    test('withdrawals and do-not-pair requests stop the projection', () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.savePlayer(c.event!.player('p3').copy(withdrawn: true));
      expect(projected(c), isEmpty);
      expect(c.quadScheduleIssues[quad(c).id], contains('withdrawn'));
      c.savePlayer(c.event!.player('p3').copy(withdrawn: false));
      expect(projected(c), hasLength(3));
      expect(c.quadScheduleIssues, isEmpty);
      c.avoidPair('p0', 'p1', true);
      expect(projected(c), isEmpty);
      expect(c.quadScheduleIssues[quad(c).id], contains('do-not-pair'));
    });

    test('an edited pairing retires its projected game ID', () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final s = quad(c);
      final stale = projected(c).first.games.first;
      final rows = schedule(s);
      final flipped = [
        [rows[0][1], rows[0][0], rows[0][2], rows[0][3]],
        rows[1],
        rows[2],
      ];
      c.editQuadPairings(s.id, flipped, c.event!.revision);
      final before = c.event!.encode();
      expect(
        () => c.recordResult(stale.id, Outcome.whiteWin),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'message',
            'The selected game no longer exists.',
          ),
        ),
      );
      expect(c.event!.encode(), before);
      final fresh = projected(c).first.games.first;
      expect(fresh.white, stale.black);
      expect(fresh.id, isNot(stale.id));
    });

    test('the projection is computed once per revision', () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      expect(identical(c.pairingEvent, c.pairingEvent), isTrue);
      final first = c.pairingEvent;
      c.recordResult(
        first.sections.first.rounds.first.games.first.id,
        Outcome.draw,
      );
      expect(identical(c.pairingEvent, first), isFalse);
    });
  });
}
