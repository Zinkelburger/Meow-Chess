import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/standings.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

import '../dbf_reader.dart';

/// A Swiss of [count] members with the details a rating report needs.
TournamentController swiss({
  int count = 6,
  int rounds = 3,
  Format format = Format.swiss,
}) {
  final c = TournamentController(SqliteEventRepository(':memory:'));
  c.create('Late entries');
  c.importPlayers([
    for (var i = 0; i < count; i++)
      Player(
        id: 'p$i',
        name: 'Given$i Family$i',
        rating: 1900 - i * 50,
        memberId: '${12000000 + i}',
        state: 'MA',
      ),
  ]);
  c.addSection('Open', format, rounds);
  c.change(
    'Report details',
    c.event!.copy(
      tdId: '12345678',
      affiliateId: 'A6012345',
      city: 'Boston',
      state: 'MA',
      zip: '02116',
      timeControl: 'G/60 d5',
    ),
  );
  return c;
}

Section open(TournamentController c) => c.event!.sections.single;

Future<void> post(TournamentController c) async => c.post(await c.propose());

void finish(TournamentController c) {
  for (final g in open(c).rounds.last.games) {
    if (!g.outcome.resolved) c.recordResult(g.id, Outcome.whiteWin);
  }
}

Player walkIn(String id, {String memberId = '12999999'}) => Player(
  id: id,
  name: 'Walk In',
  rating: 1500,
  memberId: memberId,
  state: 'MA',
);

Matcher refuses(String text) => throwsA(
  isA<TournamentException>().having(
    (e) => e.message,
    'message',
    contains(text),
  ),
);

void main() {
  test('a late entry joins while the round is being played', () async {
    final c = swiss();
    addTearDown(c.dispose);
    await post(c);
    // One result in; the other boards are still playing.
    c.recordResult(open(c).rounds.single.games.first.id, Outcome.draw);
    c.savePlayer(walkIn('late'));
    c.movePlayers(['late'], open(c).id);

    final s = open(c);
    expect(s.players, contains('late'));
    expect(s.format, Format.swiss);
    expect(c.event!.transitions, isEmpty);
    final bye = s.rounds.single.byes.singleWhere((b) => b.player == 'late');
    expect((bye.points, bye.reason, bye.allocated), (1, 'Late entry', false));
    expect(c.event!.player('late').byes, {1: 1});
    expect(
      standings(c.event!, s).firstWhere((r) => r.player.id == 'late').points,
      1,
    );

    finish(c);
    await post(c);
    final second = open(c).rounds.last;
    expect(
      second.games.any((g) => g.white == 'late' || g.black == 'late') ||
          second.byes.any((b) => b.player == 'late'),
      isTrue,
    );
    finish(c);
    await post(c);
    finish(c);

    expect(ratingPreflight(c.event!), isEmpty);
    final rows = readDbf(ratingPackage(c.event!)['TDEXPORT.DBF']!).$2;
    final late = rows.singleWhere((r) => r['D_MEM_ID'] == '12999999');
    expect(late['D_RND01'], 'H0');
    expect(late['D_PAIR_NUM'], '7');
  });

  test(
    'missed rounds take the byes chosen, or what the bye rules allow',
    () async {
      final c = swiss(count: 6, rounds: 4);
      addTearDown(c.dispose);
      c.change(
        'Announce byes',
        c.event!.copy(
          sections: [
            open(c).copy(byeRules: ByePolicy.fromJson({'lastHalfByeRound': 1})),
          ],
        ),
      );
      await post(c);
      finish(c);
      await post(c);
      c.savePlayer(walkIn('late'));
      c.savePlayer(walkIn('later', memberId: '12999998'));
      // Half-point byes were announced through round 1 only.
      c.enterLate(['late'], open(c).id);
      expect(
        [
          for (final r in open(c).rounds)
            r.byes.singleWhere((b) => b.player == 'late').points,
        ],
        [1, 0],
      );
      // The director's choice wins; one the bye rules forbid is refused.
      c.movePlayers(['later'], open(c).id, lateByes: const {1: 0});
      expect(
        [
          for (final r in open(c).rounds)
            r.byes.singleWhere((b) => b.player == 'later').points,
        ],
        [0, 0],
      );
      c.savePlayer(walkIn('last', memberId: '12999997'));
      expect(
        () => c.enterLate(['last'], open(c).id, byes: const {2: 1}),
        refuses('through round 1'),
      );
      expect(
        () => c.enterLate(['last'], open(c).id, byes: const {3: 0}),
        refuses('posted 2 rounds'),
      );
      expect(open(c).players, isNot(contains('last')));
    },
  );

  test('the undo step names each walk-up\'s byes when they differ', () async {
    final c = swiss(count: 6, rounds: 4);
    addTearDown(c.dispose);
    c.change(
      'Announce byes',
      c.event!.copy(
        sections: [
          open(c).copy(byeRules: ByePolicy.fromJson({'maxHalfByes': 1})),
        ],
      ),
    );
    await post(c);
    // One walk-up has already asked for the one half-point bye allowed.
    c.savePlayer(walkIn('late').copy(name: 'Ann Late'));
    c.savePlayer(
      walkIn(
        'booked',
        memberId: '12999998',
      ).copy(name: 'Bea Booked', byes: const {4: 1}),
    );
    c.enterLate(['late', 'booked'], open(c).id);
    final points = {
      for (final b in open(c).rounds.single.byes) b.player: b.points,
    };
    expect(points['late'], 1);
    expect(points['booked'], 0);
    expect(
      c.undoLabel,
      contains(
        'Enter 2 players late in Open (byes: Ann Late round 1 ½; '
        'Bea Booked round 1 0)',
      ),
    );

    // The same byes for everyone are listed once.
    c.undo();
    c.savePlayer(c.event!.player('booked').copy(byes: const {}));
    c.enterLate(['late', 'booked'], open(c).id);
    expect(
      c.undoLabel,
      contains('Enter 2 players late in Open (byes: round 1 ½)'),
    );
  });

  test('a missed-round bye can be changed afterwards', () async {
    final c = swiss();
    addTearDown(c.dispose);
    await post(c);
    c.savePlayer(walkIn('late'));
    c.enterLate(['late'], open(c).id);
    int points() =>
        open(c).rounds.first.byes.singleWhere((b) => b.player == 'late').points;

    c.reserveBye('late', 1, 0);
    expect(points(), 0);
    expect(c.event!.player('late').byes, {1: 0});
    c.reserveBye('late', 1, 1);
    expect(points(), 1);
    expect(() => c.reserveBye('late', 1, 2), refuses('zero or half a point'));
    expect(() => c.reserveBye('late', 1, -1), refuses('zero or half a point'));
    // A round that was played is corrected through its game.
    final playing = open(c).rounds.first.games.first.white;
    expect(() => c.reserveBye(playing, 1, 1), refuses('has a game in it'));
    expect(c.event!.transitions, isEmpty);
  });

  test('a started round robin or quad takes no late entry', () async {
    for (final format in [Format.roundRobin, Format.quad]) {
      final c = swiss(count: 4, format: format);
      addTearDown(c.dispose);
      await post(c);
      c.savePlayer(walkIn('late'));
      final before = c.event!.encode();
      expect(
        () => c.movePlayers(['late'], open(c).id, reason: 'Late'),
        refuses('has no place for another player'),
      );
      expect(c.event!.encode(), before);
    }
  });

  test('before round 1 a player simply joins the section', () {
    final c = swiss();
    addTearDown(c.dispose);
    c.savePlayer(walkIn('early'));
    c.movePlayers(['early'], open(c).id);
    expect(open(c).players, contains('early'));
    expect(c.event!.player('early').byes, isEmpty);
    expect(
      () => c.enterLate(['early'], open(c).id),
      refuses('not been paired'),
    );
  });
}
