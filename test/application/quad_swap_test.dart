import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import '../support.dart';

void main() {
  test(
    'swap preserves quad sizes, slots and undo; stale and posted swaps fail',
    () async {
      final c = fixture();
      addTearDown(c.dispose);
      final original = c.event!,
          a = original.sections[0].players[0],
          b = original.sections[1].players[0];
      c.swapPlayers(a, b, original.revision);
      expect(c.event!.sections.map((s) => s.players.length), [4, 4]);
      expect(c.event!.sections[0].players[0], b);
      expect(c.event!.sections[1].players[0], a);
      expect(
        () => c.swapPlayers(a, b, original.revision),
        throwsA(isA<TournamentException>()),
      );
      c.undo();
      expect(c.event!.sections[0].players, original.sections[0].players);
      c.post(await c.propose());
      expect(
        () => c.swapPlayers(a, b, c.event!.revision),
        throwsA(isA<TournamentException>()),
      );
    },
  );
  test(
    'Hoy quad schedule balances first two rounds for every final color lot',
    () {
      final ids = ['1', '2', '3', '4'];
      for (var lot = 0; lot < 4; lot++) {
        final rounds = roundRobinSchedule(ids, quad: true, colorLot: lot);
        for (final id in ids) {
          expect(
            rounds.take(2).expand((r) => r).where((g) => g.$1 == id).length,
            1,
          );
          expect(
            rounds.take(2).expand((r) => r).where((g) => g.$2 == id).length,
            1,
          );
          final opponents = rounds
              .expand((r) => r)
              .where((g) => g.$1 == id || g.$2 == id)
              .map((g) => g.$1 == id ? g.$2 : g.$1)
              .toSet();
          expect(opponents.length, 3);
          expect(
            rounds.expand((r) => r).where((g) => g.$1 == id).length,
            inInclusiveRange(1, 2),
          );
        }
      }
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final first = proposeRound(c.event!, c.event!.sections.single, c.newId);
      final second = proposeRound(
        Event.decode(c.event!.encode()),
        c.event!.sections.single,
        c.newId,
      );
      expect(first.note, second.note);
      expect(first.policy, 'quad-30G-seeded-v1');
    },
  );
}
