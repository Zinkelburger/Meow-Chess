import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/diagnostics.dart';
import 'package:meow_chess/domain/model.dart';
import '../support.dart';

Matcher refuses(String text) => throwsA(
  isA<TournamentException>().having(
    (e) => e.message,
    'message',
    contains(text),
  ),
);

void main() {
  group('moving players keeps board ranges', () {
    test('a custom first board survives an unrelated move', () {
      final c = fixture(count: 12);
      addTearDown(c.dispose);
      final [q1, q2, q3] = c.event!.sections;
      c.change(
        'Set first board',
        c.event!.copy(sections: [q1, q2, q3.copy(boardStart: 50)]),
      );
      c.movePlayers([q1.players.last], q2.id);
      expect(c.event!.sections.map((s) => s.boardStart), [1, 3, 50]);
    });

    test('a grown section moves clear of a section playing a round', () async {
      final c = fixture(count: 12);
      addTearDown(c.dispose);
      final [q1, q2, q3] = c.event!.sections;
      c.post(await c.propose(sectionId: q3.id));
      final live = c.event!.sections.last.rounds.single.games
          .map((g) => g.board)
          .toSet();
      expect(live, {5, 6});
      c.movePlayers([q1.players.last], q2.id);
      final [a, b, playing] = c.event!.sections;
      expect(a.boardStart, 1);
      expect(playing.boardStart, 5);
      // Five players need boards 3 to 5, which Quad 3 is using.
      expect(b.boardStart, 7);
      for (final id in [q1.id, q2.id]) {
        c.post(await c.propose(sectionId: id));
      }
      final boards = [
        for (final s in c.event!.sections)
          for (final g in s.rounds.last.games) g.board,
      ];
      expect(boards.toSet().length, boards.length);
    });

    test('a manual quad schedule is cleared when its roster changes', () {
      final c = fixture(count: 8);
      addTearDown(c.dispose);
      final [q1, q2] = c.event!.sections;
      final [a, b, x, y] = q2.players;
      c.editQuadPairings(q2.id, [
        [a, b, x, y],
        [a, x, b, y],
        [a, y, b, x],
      ], c.event!.revision);
      expect(c.event!.sections.last.quadPairings, isNotEmpty);
      c.movePlayers([q1.players.last], q2.id);
      c.movePlayers([a], q1.id);
      expect(c.event!.sections.map((s) => s.players.length), [4, 4]);
      expect(c.event!.sections.last.quadPairings, isEmpty);
    });
  });

  test('undo, redo and restore are written to the diagnostic log', () {
    final lines = <String>[];
    final previous = Diagnostics.sink;
    Diagnostics.sink = lines.add;
    addTearDown(() => Diagnostics.sink = previous);
    // Closed below, which releases the event file.
    final c = fixture(count: 4);
    c.savePlayer(c.event!.players.first.copy(rating: 1600));
    lines.clear();
    c.undo();
    expect(lines.first, contains('save event — started'));
    expect(lines.first, contains('action: Undo Edit Player 00'));
    expect(lines.last, contains('save event — succeeded'));
    lines.clear();
    c.redo();
    expect(lines.last, contains('action: Redo Edit Player 00'));
    lines.clear();
    c.releaseResources();
    expect(c.undo, refuses('This event has closed.'));
    expect(lines.last, contains('save event — failed'));
    expect(lines.last, contains('Error: This event has closed.'));
  });

  test('a quad result entered in round 3 lets round 1 start first', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final quad = c.pairingEvent.sections.single;
    c.recordResult(quad.rounds[2].games.first.id, Outcome.whiteWin);
    expect(c.event!.sections.single.rounds, hasLength(3));
    c.startRound(quad.id);
    final rounds = c.event!.sections.single.rounds;
    expect(rounds.first.startedAt, isNotNull);
    expect(rounds.skip(1).map((r) => r.startedAt), [null, null]);
    expect(
      () => c.startRound(quad.id),
      refuses('earlier games are still unresolved'),
    );
    for (final g in rounds.first.games) {
      c.recordResult(g.id, Outcome.draw);
    }
    c.startRound(quad.id);
    expect(c.event!.sections.single.rounds[1].startedAt, isNotNull);
  });

  group('section names', () {
    test('renaming a section to an existing name is refused', () {
      final c = fixture(count: 8);
      addTearDown(c.dispose);
      final [q1, q2] = c.event!.sections;
      final revision = c.event!.revision;
      expect(
        () => c.change(
          'Edit section settings',
          c.event!.copy(
            sections: [
              q1,
              q2.copy(name: '  quad 1 '),
            ],
          ),
        ),
        refuses('There is already a section called Quad 1. Choose another'),
      );
      expect(c.event!.revision, revision);
      c.change(
        'Edit section settings',
        c.event!.copy(
          sections: [
            q1,
            q2.copy(name: 'Reserve'),
          ],
        ),
      );
      expect(c.event!.sections.last.name, 'Reserve');
    });

    test('a file that already has duplicate names still saves', () {
      final c = fixture(count: 8);
      addTearDown(c.dispose);
      final [q1, q2] = c.event!.sections;
      c.event = c.repository.commit(
        c.event!.copy(
          sections: [
            q1,
            q2.copy(name: 'Quad 1'),
          ],
        ),
        expectedRevision: c.event!.revision,
        action: 'Older file',
      );
      c.change('Edit event', c.event!.copy(venue: 'Library'));
      expect(c.event!.venue, 'Library');
    });

    test('a new side-games section takes a free name', () {
      final c = fixture(count: 8);
      addTearDown(c.dispose);
      final [q1, q2] = c.event!.sections;
      c.change(
        'Rename',
        c.event!.copy(
          sections: [
            q1.copy(name: 'Side games'),
            q2,
          ],
        ),
      );
      final id = c.addSideGame(q1.players[0], q2.players[0]);
      expect(
        c.event!.sections.firstWhere((s) => s.id == id).name,
        'Side Games 2',
      );
    });
  });

  test('a placeholder US Chess ID identifies nobody', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final [a, b, ...] = c.event!.players;
    c.savePlayer(a.copy(memberId: '00000000'));
    c.savePlayer(b.copy(memberId: '00000000'));
    expect(
      c.event!.players.where((p) => p.memberId == '00000000'),
      hasLength(2),
    );
    expect(
      c.importPlayers([
        Player(id: 'new', name: 'New Player', memberId: '00000000'),
      ]),
      0,
    );
    expect(c.event!.players.last.name, 'New Player');
  });

  group('stale pairing proposals cannot post', () {
    test('after a result is recorded', () async {
      final c = fixture(count: 12, format: Format.swiss);
      addTearDown(c.dispose);
      c.post(await c.propose(sectionId: c.event!.sections.first.id));
      final batch = await c.propose();
      c.recordResult(c.event!.games.first.id, Outcome.draw);
      final before = c.event!.encode();
      expect(() => c.post(batch), refuses('Generate a fresh proposal'));
      expect(c.event!.encode(), before);
    });

    test('after an undo', () async {
      final c = fixture(count: 8);
      addTearDown(c.dispose);
      c.savePlayer(c.event!.players.first.copy(rating: 2100));
      final batch = await c.propose();
      c.undo();
      expect(() => c.post(batch), refuses('Generate a fresh proposal'));
      expect(c.event!.sections.every((s) => s.rounds.isEmpty), true);
    });

    test('when an overlapping proposal posted first', () async {
      final c = fixture(count: 8);
      addTearDown(c.dispose);
      final first = await c.propose(), second = await c.propose();
      c.post(first);
      final before = c.event!.encode();
      expect(() => c.post(second), refuses('Generate a fresh proposal'));
      expect(c.event!.encode(), before);
      expect(c.event!.sections.every((s) => s.rounds.length == 1), true);
    });
  });

  test('several sections start in one revision, or none do', () async {
    final c = fixture(count: 12);
    addTearDown(c.dispose);
    final [q1, q2, q3] = c.event!.sections;
    c.post(await c.propose(sectionId: q1.id));
    c.post(await c.propose(sectionId: q2.id));
    final revision = c.event!.revision;
    expect(
      () => c.startRounds([q1.id, q2.id, q3.id]),
      refuses('Post a round before starting it.'),
    );
    expect(c.event!.revision, revision);
    expect(() => c.startRounds([]), refuses('No round is waiting'));
    c.startRounds([q1.id, q2.id]);
    expect(c.event!.revision, revision + 1);
    expect(c.undoLabel, 'Start round in 2 sections');
    final starts = c.event!.sections
        .take(2)
        .map((s) => s.rounds.single.startedAt)
        .toSet();
    expect(starts.single, isNotNull);
    expect(c.event!.sections.last.rounds, isEmpty);
  });

  test('removing a section keeps its players; a paired one stays', () async {
    final c = fixture(count: 8);
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    c.post(await c.propose(sectionId: q1.id));
    expect(
      () => c.removeSection(q1.id),
      refuses('Sections with posted rounds cannot be deleted.'),
    );
    c.removeSection(q2.id);
    expect(c.event!.sections.map((s) => s.id), [q1.id]);
    expect(c.event!.players, hasLength(8));
    expect(q2.players.map(c.event!.sectionOf), everyElement(isNull));
    expect(c.undoLabel, 'Delete Quad 2');
    expect(
      () => c.removeSection(q2.id),
      refuses('That section no longer exists.'),
    );
  });

  test('posting onto boards a live round holds is refused whole', () async {
    final c = fixture(count: 8);
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    c.post(await c.propose(sectionId: q1.id));
    c.change(
      'Overlap boards',
      c.event!.copy(
        sections: [c.event!.sections.first, q2.copy(boardStart: 2)],
      ),
    );
    final batch = await c.propose(sectionId: q2.id);
    final before = c.event!.encode();
    expect(
      () => c.post(batch),
      refuses('Board 2 is already reserved by Quad 1. Adjust board ranges.'),
    );
    expect(c.event!.encode(), before);
  });

  test('commands after the event closes are refused', () async {
    final c = fixture(count: 8);
    final batch = await c.propose();
    final player = c.event!.players.first;
    c.releaseResources();
    for (final command in <void Function()>[
      () => c.savePlayer(player.copy(rating: 1234)),
      () => c.post(batch),
      () => c.removeSection(c.event!.sections.first.id),
      c.undo,
    ]) {
      expect(command, refuses('This event has closed.'));
    }
    expect(c.event!.players.first.rating, player.rating);
  });
}
