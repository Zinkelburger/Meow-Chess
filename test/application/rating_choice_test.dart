import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/member_observation.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/rating_choice.dart';
import '../support.dart';

MemberObservation seen(Player p, int rating) => MemberObservation(
  id: p.memberId,
  name: p.name,
  retrievedAt: '2026-10-05T12:00:00Z',
  supplementDate: '2026-10-01',
  ratings: {'R': rating},
);

void main() {
  test('reviewed and unreviewed players can both be switched afterwards', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final snapshot = c.event!;
    final observations = {
      for (final p in snapshot.players) p.id: seen(p, p.rating + 40),
    };
    // Every lookup is saved; only p0 is ticked in the review.
    c.recordMemberships(snapshot.id, {
      for (final MapEntry(:key, :value) in observations.entries)
        key: value.toJson(),
    });
    c.applyReviewedRatings(
      snapshot: c.event!,
      observations: observations,
      playerIds: {'p0'},
      category: 'R',
    );
    expect(c.event!.player('p0').rating, 2040);
    expect(c.event!.player('p1').rating, 1950);
    expect(ratingChoice(c.event!.player('p0'))!.usingSupplement, true);
    expect(ratingChoice(c.event!.player('p1'))!.usingSupplement, false);

    // One player back to the entered rating, as one undoable step.
    expect(c.chooseRatings(['p0'], supplement: false), 1);
    expect(c.event!.player('p0').rating, 2000);
    c.undo();
    expect(c.event!.player('p0').rating, 2040);

    // Everyone onto the supplement: only those not already on it change.
    final ids = [for (final p in c.event!.players) p.id];
    expect(c.chooseRatings(ids, supplement: true), 3);
    expect(
      [for (final p in c.event!.players) p.rating],
      [2040, 1990, 1940, 1890],
    );
    expect(c.chooseRatings(ids, supplement: true), 0);
    expect(c.chooseRatings(ids, supplement: false), 4);
    expect(
      [for (final p in c.event!.players) p.rating],
      [2000, 1950, 1900, 1850],
    );
    // Saved, not just in memory.
    expect(c.repository.load()!.player('p2').rating, 1900);
    expect(ratingChoice(c.repository.load()!.player('p2'))!.supplement, 1940);
  });

  test('a typed rating becomes the entered one; the supplement stays', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final p = c.event!.player('p0');
    c.applyReviewedRatings(
      snapshot: c.event!,
      observations: {'p0': seen(p, 2040)},
      playerIds: {'p0'},
      category: 'R',
    );
    c.savePlayer(c.event!.player('p0').copy(rating: 1975));
    final typed = c.event!.player('p0');
    expect(typed.ratingEvidence['kind'], 'TD-assigned');
    final choice = ratingChoice(typed)!;
    expect((choice.entered, choice.supplement), (1975, 2040));
    expect(choice.usingSupplement, false);
    // A new ID makes the supplement somebody else's.
    c.savePlayer(typed.copy(memberId: '99887766'));
    expect(ratingChoice(c.event!.player('p0')), isNull);
  });

  test('a paired section keeps its pairing ratings', () async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final p = c.event!.player('p0');
    c.recordMembership(c.event!.id, 'p0', seen(p, 2040).toJson());
    c.post(await c.propose());
    expect(c.event!.sections.first.rounds, isNotEmpty);
    expect(
      () => c.chooseRatings(['p0'], supplement: true),
      throwsA(isA<TournamentException>()),
    );
    expect(c.event!.player('p0').rating, 2000);
  });
}
