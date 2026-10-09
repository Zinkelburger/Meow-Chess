import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/ui/rating_refresh.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import '../support.dart';

MemberObservation observation(String id, int? rating) => MemberObservation(
  id: id,
  name: 'Player',
  retrievedAt: '2026-10-03',
  supplementDate: '2026-10-01',
  ratings: {'R': rating},
  expiration: '2027-01-31',
);

class _BrokenObservation extends MemberObservation {
  _BrokenObservation(String id)
    : super(
        id: id,
        name: 'Player',
        retrievedAt: '2026-10-03',
        ratings: const {},
      );

  @override
  Json toJson() => throw StateError('Unexpected shape');
}

class _FailingRepository extends SqliteEventRepository {
  _FailingRepository() : super(':memory:');
  bool failWrites = false;

  @override
  Event commit(
    Event next, {
    required int expectedRevision,
    required String action,
  }) {
    if (failWrites) throw const TournamentException('Disk is full.');
    return super.commit(
      next,
      expectedRevision: expectedRevision,
      action: action,
    );
  }
}

void main() {
  test(
    'keeping current ratings mid-lookup saves completed checks and ignores late results',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final reached = Completer<void>();
      final pending = Completer<MemberObservation?>();
      final draft = RatingRefresh(
        c,
        lookup: (id) {
          if (id == '12000000') return Future.value(observation(id, 1500));
          if (!reached.isCompleted) reached.complete();
          return pending.future;
        },
      );
      addTearDown(draft.dispose);
      final work = draft.fetch();
      await reached.future;
      expect(draft.busy, true);
      expect(draft.observations.keys, ['p0']);
      draft.discard();
      expect(draft.active, false);
      expect(c.event!.player('p0').membershipEvidence['id'], '12000000');
      expect(c.event!.player('p0').membershipEvidence['expiration'], isNotNull);
      final revision = c.event!.revision;
      pending.complete(observation('12000001', 1600));
      await work;
      expect(draft.observations, isEmpty);
      expect(c.event!.player('p1').membershipEvidence, isEmpty);
      expect(c.event!.revision, revision);
      expect(c.event!.player('p0').rating, 2000);
    },
  );

  test(
    'a failed save on keep leaves the review open with completed checks',
    () async {
      final repository = _FailingRepository();
      final c = TournamentController(repository)..create('Ratings');
      addTearDown(c.dispose);
      c.importPlayers([
        Player(id: 'p', name: 'Player', memberId: '12000000', rating: 1000),
      ]);
      final draft = RatingRefresh(
        c,
        lookup: (id) async => observation(id, 1500),
      );
      addTearDown(draft.dispose);
      repository.failWrites = true;
      await draft.fetch();
      draft.discard();
      expect(draft.active, true);
      expect(draft.busy, false);
      expect(draft.notice, contains('Disk is full'));
      expect(draft.observations, hasLength(1));
      repository.failWrites = false;
      draft.discard();
      expect(draft.active, false);
      expect(c.event!.player('p').membershipEvidence['id'], '12000000');
      expect(c.event!.player('p').rating, 1000);
    },
  );

  test('an unexpected lookup error is not called a save failure', () async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final draft = RatingRefresh(
      c,
      lookup: (id) async => _BrokenObservation(id),
    );
    addTearDown(draft.dispose);
    await draft.fetch();
    expect(draft.busy, false);
    expect(draft.notice, isNot(contains('Could not save')));
    expect(draft.notice, contains('Unexpected shape'));
  });
}
