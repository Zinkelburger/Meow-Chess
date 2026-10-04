import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/member_lookup.dart';
import 'package:meow_chess/application/member_lookup_batch.dart';
import 'package:meow_chess/domain/member_observation.dart';
import 'package:meow_chess/domain/model.dart';

import '../support.dart';

MemberObservation member(String id) => MemberObservation(
  id: id,
  name: 'Official Name',
  retrievedAt: '2026-10-04',
  ratings: const {'R': 1500},
);

void main() {
  late List<Player> players;
  setUp(() {
    final controller = fixture(count: 4);
    players = controller.event!.players;
    controller.dispose();
  });

  test(
    'one request per identity, one result per entry, no delay for cache hits',
    () async {
      final calls = <String>[], found = <String>[];
      final waits = <Duration>[];
      final batch = MemberLookupBatch(
        wait: (duration) async => waits.add(duration),
      );
      final outcome = await batch.run(
        [
          players[0],
          players[1].copy(memberId: players[0].memberId),
          players[2].copy(memberId: ''),
          players[3],
        ],
        lookup: (id) async {
          calls.add(id);
          return member(id);
        },
        isCurrent: () => true,
        onFound: (player, _) => found.add(player.id),
        onFailure: (_, error, _) => fail('$error'),
      );
      expect(outcome, MemberBatchOutcome.completed);
      expect(calls, [players[0].memberId, players[3].memberId]);
      expect(found, [players[0].id, players[1].id, players[3].id]);
      expect(waits, [const Duration(milliseconds: 500)]);
    },
  );

  test(
    'missing members and mismatched identities do not update records',
    () async {
      final errors = <String>[], found = <String>[];
      final batch = MemberLookupBatch(wait: (_) async {});
      await batch.run(
        players,
        lookup: (id) async {
          if (id == players[0].memberId) throw const MemberNotFound();
          if (id == players[1].memberId) return null;
          if (id == players[2].memberId) return member('99887766');
          return member(id);
        },
        isCurrent: () => true,
        onFound: (player, _) => found.add(player.id),
        onFailure: (player, _, _) => errors.add(player.id),
      );
      expect(errors, players.take(3).map((p) => p.id));
      expect(found, [players.last.id]);
    },
  );

  test(
    'typed provider failures stop regardless of displayed wording',
    () async {
      for (final kind in [
        MemberLookupFailureKind.accessDenied,
        MemberLookupFailureKind.rateLimited,
        MemberLookupFailureKind.unavailable,
      ]) {
        var called = 0, failed = 0;
        final outcome = await const MemberLookupBatch().run(
          players,
          lookup: (_) async {
            called++;
            throw MemberLookupFailure(kind, 'Translated message');
          },
          isCurrent: () => true,
          onFound: (_, _) => fail('Unexpected success'),
          onFailure: (_, _, _) => failed++,
        );
        expect(outcome, MemberBatchOutcome.providerStopped);
        expect(called, 1);
        expect(failed, 1);
      }
    },
  );

  test(
    'cancellation rejects a late response and never starts the next lookup',
    () async {
      var current = true, calls = 0;
      final pending = Completer<MemberObservation?>();
      final work = const MemberLookupBatch().run(
        players,
        lookup: (_) {
          calls++;
          return pending.future;
        },
        isCurrent: () => current,
        onFound: (_, _) => fail('Stale result'),
        onFailure: (_, _, _) => fail('Stale error'),
      );
      current = false;
      pending.complete(member(players.first.memberId));
      expect(await work, MemberBatchOutcome.cancelled);
      expect(calls, 1);
    },
  );

  test(
    'cancellation during the rate-limit delay prevents another request',
    () async {
      var current = true, calls = 0;
      final batch = MemberLookupBatch(
        wait: (_) async {
          current = false;
        },
      );
      final result = await batch.run(
        players,
        lookup: (id) async {
          calls++;
          return member(id);
        },
        isCurrent: () => current,
        onFound: (_, _) {},
        onFailure: (_, _, _) => fail('Unexpected error'),
      );
      expect(result, MemberBatchOutcome.cancelled);
      expect(calls, 1);
    },
  );

  test(
    'commit failures propagate instead of becoming network errors',
    () async {
      final diskError = StateError('Could not persist membership');
      var calls = 0;
      await expectLater(
        const MemberLookupBatch().run(
          players,
          lookup: (id) async {
            calls++;
            return member(id);
          },
          isCurrent: () => true,
          onFound: (_, _) => throw diskError,
          onFailure: (_, _, _) =>
              fail('Must not classify a commit error as a lookup error'),
        ),
        throwsA(same(diskError)),
      );
      expect(calls, 1);
    },
  );
}
