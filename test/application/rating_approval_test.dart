import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/member_observation.dart';

import '../support.dart';

MemberObservation observed(
  Player player, {
  String? date = '2026-10-01',
  int rating = 1600,
}) => MemberObservation(
  id: player.memberId,
  name: player.name,
  retrievedAt: '2026-10-02',
  supplementDate: date,
  ratings: {'R': rating},
  expiration: '2026-12-31',
);

void main() {
  test('one stale approval rejects the entire transaction', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final snapshot = c.event!;
    final observations = {for (final p in snapshot.players) p.id: observed(p)};
    c.savePlayer(snapshot.players.last.copy(rating: 1700));
    final before = c.event!.encode();
    expect(
      () => c.applyReviewedRatings(
        snapshot: snapshot,
        observations: observations,
        playerIds: observations.keys.toSet(),
        category: 'R',
      ),
      throwsA(isA<TournamentException>()),
    );
    expect(c.event!.encode(), before);
    expect(c.repository.load()!.encode(), before);
  });

  test(
    'unrelated edits and newer membership evidence survive a rating approval',
    () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final snapshot = c.event!;
      final player = snapshot.players.first;
      c.savePlayer(
        player.copy(
          notes: 'Keep this note',
          membershipEvidence: {
            'id': player.memberId,
            'retrievedAt': '2026-10-04',
            'expiration': '2028-12-31',
          },
        ),
      );
      final revision = c.event!.revision;
      expect(
        c.applyReviewedRatings(
          snapshot: snapshot,
          observations: {player.id: observed(player)},
          playerIds: {player.id},
          category: 'R',
        ),
        1,
      );
      expect(c.event!.revision, revision + 1);
      final saved = c.event!.player(player.id);
      expect(saved.rating, 1600);
      expect(saved.notes, 'Keep this note');
      expect(saved.membershipEvidence['expiration'], '2028-12-31');
      c.undo();
      expect(c.event!.player(player.id).rating, player.rating);
    },
  );

  test(
    'posted sections and unusable observations are rejected by the command',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final snapshot = c.event!;
      final player = snapshot.players.first;
      for (final observation in [
        observed(player, date: null),
        observed(player, rating: 0),
        observed(player, rating: 5000),
      ]) {
        expect(
          () => c.applyReviewedRatings(
            snapshot: snapshot,
            observations: {player.id: observation},
            playerIds: {player.id},
            category: 'R',
          ),
          throwsA(isA<TournamentException>()),
        );
      }
      c.post(await c.propose());
      expect(
        () => c.applyReviewedRatings(
          snapshot: snapshot,
          observations: {player.id: observed(player)},
          playerIds: {player.id},
          category: 'R',
        ),
        throwsA(isA<TournamentException>()),
      );
      expect(c.event!.player(player.id).rating, player.rating);
    },
  );
}
