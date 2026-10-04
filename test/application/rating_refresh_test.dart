import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/ui/rating_refresh.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import '../support.dart';

MemberObservation observation(String id, int? rating) => MemberObservation(
  id: id,
  name: 'Official Name',
  retrievedAt: '2026-10-03',
  supplementDate: '2026-10-01',
  ratings: {'R': rating},
  state: 'NH',
);

void main() {
  test(
    'review skips missing IDs and unrated, applies only approvals, supports undo',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.savePlayer(c.event!.player('p1').copy(memberId: ''));
      final revision = c.event!.revision;
      final called = <String>[];
      final draft = RatingRefresh(
        c,
        lookup: (id) async {
          called.add(id);
          return observation(id, id == '12000002' ? 0 : 1300);
        },
      );
      addTearDown(draft.dispose);
      await draft.fetch();
      expect(called, hasLength(3));
      expect(c.event!.revision, greaterThan(revision));
      expect(c.event!.player('p0').rating, 2000);
      expect(c.event!.player('p0').state, 'NH');
      expect(c.event!.player('p2').state, 'NH');
      expect(c.event!.player('p1').state, isEmpty);
      expect(draft.foundCount, 2);
      expect(draft.problem(c.event!.player('p1')), contains('No USCF ID'));
      expect(draft.problem(c.event!.player('p2')), contains('Unrated'));
      draft.select(c.event!.player('p3'), false);
      expect(draft.apply(), 1);
      expect(c.event!.player('p0').rating, 1300);
      expect(c.event!.player('p2').rating, 1900);
      expect(c.event!.player('p3').rating, 1850);
      expect(draft.active, false);
      c.undo();
      expect(c.event!.player('p0').rating, 2000);
    },
  );

  test('no IDs is a no-op, and rejecting a draft never saves', () async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    for (final p in c.event!.players) {
      c.savePlayer(p.copy(memberId: ''));
    }
    final revision = c.event!.revision;
    final draft = RatingRefresh(
      c,
      lookup: (_) async => fail('Must skip missing IDs'),
    );
    addTearDown(draft.dispose);
    await draft.fetch();
    expect(draft.notice, contains('Nothing changed'));
    expect(draft.approved, isEmpty);
    draft.discard();
    expect(c.event!.revision, revision);
  });

  test(
    'strictly over 50 points in either direction and unrated are highlighted',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.savePlayer(c.event!.player('p3').copy(rating: 0));
      final values = {
        '12000000': 2050,
        '12000001': 1899,
        '12000002': 1951,
        '12000003': 40,
      };
      final draft = RatingRefresh(
        c,
        lookup: (id) async => observation(id, values[id]),
      );
      addTearDown(draft.dispose);
      await draft.fetch();
      expect(draft.largeChange(c.event!.player('p0')), false);
      for (final id in ['p1', 'p2', 'p3']) {
        expect(draft.largeChange(c.event!.player(id)), true);
      }
    },
  );

  test(
    'manual rating or ID edits and posted pairings cannot be overwritten',
    () async {
      final c = fixture(count: 8);
      addTearDown(c.dispose);
      final draft = RatingRefresh(
        c,
        lookup: (id) async => observation(id, 1300),
      );
      addTearDown(draft.dispose);
      await draft.fetch();
      c.savePlayer(c.event!.player('p0').copy(rating: 1700));
      c.savePlayer(c.event!.player('p1').copy(memberId: '99887766'));
      c.savePlayer(c.event!.player('p2').copy(notes: 'Keep this manual note'));
      c.post(await c.propose(sectionId: c.event!.sections[1].id));
      expect(draft.approved.map((p) => p.id), ['p2', 'p3']);
      expect(draft.apply(), 2);
      expect(c.event!.player('p0').rating, 1700);
      expect(c.event!.player('p1').rating, 1950);
      expect(c.event!.player('p2').notes, 'Keep this manual note');
      expect(c.event!.player('p4').rating, 1800);
    },
  );

  test(
    'cancel ignores late results; provider stop explains unchecked rows',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final pending = Completer<MemberObservation?>();
      final draft = RatingRefresh(c, lookup: (_) => pending.future);
      addTearDown(draft.dispose);
      final work = draft.fetch();
      draft.discard();
      pending.complete(observation('12000000', 1500));
      await work;
      expect(draft.active, false);
      expect(draft.observations, isEmpty);
      final limited = RatingRefresh(
        c,
        lookup: (id) async {
          if (id == '12000001') {
            throw const MemberLookupFailure(
              MemberLookupFailureKind.rateLimited,
              'Provider limit reached',
              statusCode: 429,
            );
          }
          return observation(id, 1500);
        },
      );
      addTearDown(limited.dispose);
      await limited.fetch();
      expect(limited.foundCount, 1);
      expect(limited.notice, contains('retry later'));
      expect(limited.problem(c.event!.player('p2')), contains('Not checked'));
    },
  );
}
