import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/holland.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

TournamentController blitzNight(int count) {
  final c = TournamentController(SqliteEventRepository(':memory:'));
  c.create('Friday Blitz Holland');
  c.importPlayers([
    for (var i = 0; i < count; i++)
      Player(
        id: 'p$i',
        name: 'Player ${i.toString().padLeft(2, '0')}',
        rating: 2000 - i * 25,
        memberId: '${12000000 + i}',
      ),
  ]);
  return c;
}

/// Plays every posted round of every section: the higher rating wins.
Future<void> playOut(TournamentController c) async {
  while (c.event!.sections.any((s) => !s.finished)) {
    final batch = await c.propose();
    if (batch.rounds.isNotEmpty) c.post(batch);
    for (final s in c.event!.sections) {
      for (final g in s.rounds.expand((r) => r.games)) {
        if (g.outcome.resolved) continue;
        final e = c.event!;
        c.recordResult(
          g.id,
          e.player(g.white).rating > e.player(g.black).rating
              ? Outcome.whiteWin
              : Outcome.blackWin,
        );
      }
    }
  }
}

void main() {
  test('makeHolland splits the roster and makeHollandFinal follows', () async {
    final c = blitzNight(8);
    addTearDown(c.dispose);
    final ids = c.makeHolland(groups: 2, qualifiers: 2);
    expect(ids, hasLength(2));
    final prelims = c.event!.sections;
    expect(prelims.map((s) => s.name), ['Prelim 1', 'Prelim 2']);
    expect(prelims.map((s) => s.players.length), [4, 4]);
    final group = hollandGroup(prelims.first);
    expect(c.undoLabel, contains('Make 2 Holland prelims'));

    expect(
      () => c.makeHollandFinal(group),
      throwsA(
        isA<TournamentException>().having(
          (x) => x.message,
          'message',
          contains('0 of 2 prelims finished'),
        ),
      ),
    );
    expect(
      () => c.makeHolland(groups: 2, qualifiers: 1),
      throwsA(isA<TournamentException>()),
      reason: 'no unassigned players are left',
    );

    await playOut(c);
    expect(c.event!.sections.every((s) => s.finished), isTrue);
    expect(
      () => c.makeHolland(groups: 2, qualifiers: 1, players: ['p0', 'p1']),
      throwsA(
        isA<TournamentException>().having(
          (x) => x.message,
          'message',
          contains('Rounds are already posted'),
        ),
      ),
    );

    final finalId = c.makeHollandFinal(group, seed: 3);
    final e = c.event!;
    final section = e.sections.firstWhere((s) => s.id == finalId);
    expect(section.name, 'Final');
    expect(section.players, hasLength(4));
    expect(hollandRole(section), 'final');
    expect(e.players, hasLength(12));
    expect(section.players.map((id) => e.player(id).personId), [
      'p0',
      'p3',
      'p1',
      'p2',
    ]);
    expect(c.undoLabel, 'Create Final from 2 prelims (seed 3)');
    expect(
      () => c.makeHollandFinal(group),
      throwsA(
        isA<TournamentException>().having(
          (x) => x.message,
          'message',
          contains('already been created'),
        ),
      ),
    );

    // The final starts from zero and plays as a round robin.
    final batch = await c.propose(sectionId: finalId);
    c.post(batch);
    expect(c.event!.sections.last.rounds.single.games, hasLength(2));
    c.undo();
    c.undo();
    expect(c.event!.sections, hasLength(2));
    expect(c.event!.players, hasLength(8));
  });
}
