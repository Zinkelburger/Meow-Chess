import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/standings.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import '../support.dart';

void main() {
  test(
    'forfeit frees a player for an independent side game while main round continues',
    () async {
      final c = fixture(count: 8);
      addTearDown(c.dispose);
      c.post(await c.propose());
      final main = c.event!.sections.first;
      final game = main.rounds.single.games.first;
      final other = c.event!.sections[1].rounds.single.games.first;
      final before = c.event!.encode();
      expect(
        () => c.addSideGame(game.white, other.white),
        throwsA(isA<TournamentException>()),
      );
      expect(c.event!.encode(), before);
      c.recordResult(game.id, Outcome.whiteForfeit);
      c.recordResult(other.id, Outcome.draw);
      final id = c.addSideGame(game.white, other.white);
      var side = c.event!.sections.firstWhere((s) => s.id == id);
      expect(side.sideGames, isTrue);
      expect(side.players, hasLength(2));
      expect(side.players.contains(game.white), isFalse);
      expect(
        c.event!.player(side.players.first).personId,
        c.event!.player(game.white).personId ?? game.white,
      );
      expect(standings(c.event!, side).every((s) => s.points == 0), isTrue);
      expect(
        standings(
          c.event!,
          main,
        ).firstWhere((s) => s.player.id == game.white).points,
        2,
      );
      final played = side.rounds.single.games.single;
      c.recordResult(played.id, Outcome.blackWin);
      c.addSideGame(game.white, other.white);
      side = c.event!.sections.firstWhere((s) => s.id == id);
      expect(side.players, hasLength(2));
      expect(side.rounds, hasLength(2));
      expect(side.plannedRounds, 2);
      expect((await c.propose()).rounds.containsKey(id), isFalse);
      c.savePlayer(
        c.event!.player(side.players.first).copy(notes: 'Separate entry note'),
      );
      expect(c.event!.player(game.white).notes, isEmpty);
    },
  );

  test('finished side-game players can play while other games continue', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final players = c.event!.players;
    final id = c.addSideGame(players[0].id, players[1].id);
    c.addSideGame(players[2].id, players[3].id);
    var section = c.event!.sections.firstWhere((s) => s.id == id);
    expect(section.rounds.single.games, hasLength(2));
    final first = section.rounds.single.games.first;
    c.recordResult(first.id, Outcome.draw);
    c.addSideGame(players[0].id, players[1].id);
    section = c.event!.sections.firstWhere((s) => s.id == id);
    expect(section.rounds, hasLength(2));
    expect(section.rounds.first.complete, isFalse);
    expect(section.rounds.last.games.single.white, first.white);
    expect(section.plannedRounds, 2);
    final before = c.event!.encode();
    expect(
      () => c.addSideGame(players[0].id, players[2].id),
      throwsA(isA<TournamentException>()),
    );
    expect(c.event!.encode(), before);
    expect(c.repository.load()!.encode(), before);
  });

  test(
    'separate section entries keep identity but do not carry scores or byes',
    () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.addSection('Ladder', Format.swiss, 4);
      final target = c.event!.sections.last;
      final source = c.event!.players.first;
      c.reserveBye(source.id, 1, 1);
      final entry = c.addSectionEntry(source.id, target.id);
      expect(entry.personId, source.personId ?? source.id);
      expect(entry.memberId, source.memberId);
      expect(entry.byes, isEmpty);
      expect(
        () => c.addSectionEntry(source.id, target.id),
        throwsA(isA<TournamentException>()),
      );
      expect(
        () => c.savePlayer(
          Player(
            id: 'accidental',
            name: 'Duplicate',
            memberId: source.memberId,
          ),
        ),
        throwsA(isA<TournamentException>()),
      );
    },
  );

  test('double-game allocated bye awards the same points as two wins', () {
    final players = [
      for (var i = 0; i < 5; i++)
        Player(id: '$i', name: 'P$i', rating: 2000 - i * 100),
    ];
    final section = Section(
      id: 's',
      name: 'Double',
      players: players.map((p) => p.id).toList(),
      doubleGames: true,
    );
    final e = Event(
      id: 'e',
      name: 'Blitz',
      date: '2026-04-28',
      players: players,
      sections: [section],
    );
    var serial = 0;
    final round = proposeRound(e, section, () => '${serial++}');
    expect(round.games, hasLength(4));
    expect(round.byes.single.points, 4);
    validateEvent(
      e.copy(
        sections: [
          section.copy(rounds: [round]),
        ],
      ),
    );
    expect(
      () => validateEvent(
        e.copy(
          sections: [
            section.copy(doubleGames: false, rounds: [round]),
          ],
        ),
      ),
      throwsA(isA<TournamentException>()),
    );
  });

  test(
    'shared-place default preserves optional tie-break ranking and serialization',
    () {
      final players = [
        for (final name in ['A', 'B', 'C', 'D']) Player(id: name, name: name),
      ];
      final section = Section(
        id: 's',
        name: 'Open',
        players: players.map((p) => p.id).toList(),
        timeControl: 'G/45 inc/5',
        rounds: [
          Round(
            number: 1,
            games: [
              const Game(
                id: 'g1',
                white: 'A',
                black: 'B',
                board: 1,
                outcome: Outcome.whiteWin,
              ),
              const Game(
                id: 'g2',
                white: 'C',
                black: 'D',
                board: 2,
                outcome: Outcome.draw,
              ),
            ],
          ),
          Round(
            number: 2,
            games: [
              const Game(
                id: 'g3',
                white: 'A',
                black: 'C',
                board: 1,
                outcome: Outcome.blackWin,
              ),
              const Game(
                id: 'g4',
                white: 'B',
                black: 'D',
                board: 2,
                outcome: Outcome.whiteWin,
              ),
            ],
          ),
        ],
      );
      final e = Event(
        id: 'e',
        name: 'Shared places',
        date: '2026-03-07',
        players: players,
        sections: [section],
      );
      final rows = standings(e, section);
      expect(
        rows.firstWhere((r) => r.player.id == 'A').rank,
        rows.firstWhere((r) => r.player.id == 'B').rank,
      );
      final printed = reportStandings(e, section);
      expect(
        printed.firstWhere((r) => r.player.id == 'A').rank,
        printed.firstWhere((r) => r.player.id == 'B').rank,
      );
      final ranked = standings(e.copy(useTiebreaks: true), section);
      expect(
        ranked.firstWhere((r) => r.player.id == 'A').rank,
        isNot(ranked.firstWhere((r) => r.player.id == 'B').rank),
      );
      final saved = Event.fromJson(e.toJson());
      expect(saved.useTiebreaks, isFalse);
      expect(saved.sections.single.effectiveTimeControl(saved), 'G/45 inc/5');
      expect(
        section.copy(timeControl: '').effectiveTimeControl(e),
        e.timeControl,
      );
    },
  );

  test('forfeits and half-point opponentless byes stay independent', () {
    final c = TournamentController(SqliteEventRepository(':memory:'));
    addTearDown(c.dispose);
    c.create('Forfeit and bye');
    c.importPlayers([
      for (var i = 0; i < 3; i++) Player(id: '$i', name: 'Player $i'),
    ]);
    c.addSection('Open', Format.swiss, 1);
    c.post(
      PairingBatch(c.event!.revision, {
        c.event!.sections.single.id: Round(
          number: 1,
          games: [const Game(id: 'g', white: '0', black: '1', board: 1)],
          byes: [const ByeAward('2', 1, 'Requested half-point bye')],
        ),
      }, {}),
    );
    c.recordResult('g', Outcome.whiteForfeit);
    final scores = {
      for (final s in standings(c.event!, c.event!.sections.single))
        s.player.id: s.points,
    };
    expect(scores, {'0': 2, '1': 0, '2': 1});
    expect(c.event!.games.single.outcome.played, isFalse);
  });
}
