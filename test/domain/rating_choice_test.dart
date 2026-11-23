import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/member_observation.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/rating_choice.dart';
import 'package:meow_chess/domain/rating_system.dart';
import 'package:meow_chess/domain/rating_update.dart';

const seen = MemberObservation(
  id: '12345678',
  name: 'Player',
  retrievedAt: '2026-10-05T12:00:00Z',
  supplementDate: '2026-10-01',
  ratings: {'R': 1650, 'Q': 1580},
);

void main() {
  final entered = Player(
    id: 'p',
    name: 'Player',
    memberId: '12345678',
    rating: 1500,
    ratingEvidence: const {
      'source': 'https://example.org/entries',
      'kind': 'self-reported registration',
      'registrationRating': 1500,
    },
  );

  test('one rating on its own is not a choice', () {
    expect(ratingChoice(entered), isNull);
    expect(useSupplementRating(entered), same(entered));
    expect(useEnteredRating(entered), same(entered));
  });

  test('an applied supplement keeps the entered rating to switch back to', () {
    final applied = applyRatingObservation(entered, seen, 'R');
    final choice = ratingChoice(applied)!;
    expect(choice.usingSupplement, true);
    expect((choice.entered, choice.supplement), (1500, 1650));
    expect(choice.supplementDate, '2026-10-01');

    final back = useEnteredRating(applied);
    expect(back.rating, 1500);
    expect(usesSupplement(back), false);
    // The entered rating has its own evidence again.
    expect(plainRatingEvidence(back.ratingEvidence), entered.ratingEvidence);
    final kept = ratingChoice(back)!;
    expect(kept.usingSupplement, false);
    expect((kept.entered, kept.supplement), (1500, 1650));

    // And forward again, to exactly what the review applied.
    final again = useSupplementRating(back);
    expect(again.rating, 1650);
    expect(again.ratingEvidence, applied.ratingEvidence);
    expect(seen.alreadyApplied(again, 'R'), true);
  });

  test('a lookup leaves its supplement on file beside the entered rating', () {
    final looked = entered.copy(
      ratingEvidence: withSupplementOnFile(entered, {
        ...seen.toJson(),
        'category': 'Q',
      }),
    );
    expect(looked.rating, 1500);
    expect(usesSupplement(looked), false);
    final choice = ratingChoice(looked)!;
    expect(choice.usingSupplement, false);
    expect(choice.system, RatingSystem.quick);
    expect(choice.supplement, 1580);
    final switched = useSupplementRating(looked);
    expect(switched.rating, 1580);
    expect(switched.ratingEvidence['category'], 'Q');
    expect(switched.ratingEvidence['kind'], 'monthly supplement');
    expect(useEnteredRating(switched).rating, 1500);
  });

  test('nothing is kept without a dated supplement or for a rating in use', () {
    expect(
      withSupplementOnFile(entered, {...seen.toJson(), 'supplementDate': null}),
      isNull,
    );
    final applied = applyRatingObservation(entered, seen, 'R');
    expect(withSupplementOnFile(applied, seen.toJson()), isNull);
  });

  test('a supplement for another ID, or without a rating, is no choice', () {
    final looked = entered.copy(
      ratingEvidence: withSupplementOnFile(entered, seen.toJson()),
    );
    expect(ratingChoice(looked.copy(memberId: '87654321')), isNull);
    final blitz = entered.copy(
      ratingEvidence: withSupplementOnFile(entered, {
        ...seen.toJson(),
        'category': 'B',
      }),
    );
    expect(ratingChoice(blitz), isNull);
  });

  test('a newer supplement keeps the entered rating already on file', () {
    final applied = applyRatingObservation(entered, seen, 'R');
    final quick = applyRatingObservation(applied, seen, 'Q');
    expect(quick.rating, 1580);
    expect(ratingChoice(quick)!.entered, 1500);
    expect(useEnteredRating(quick).rating, 1500);
  });

  test('events saved before the choice fall back to the registration '
      'rating', () {
    final old = entered.copy(
      rating: 1650,
      ratingEvidence: {
        ...entered.ratingEvidence,
        ...seen.toJson(),
        'kind': 'monthly supplement',
        'category': 'R',
      },
    );
    final choice = ratingChoice(old)!;
    expect((choice.entered, choice.supplement), (1500, 1650));
    final back = useEnteredRating(old);
    expect(back.rating, 1500);
    expect(back.ratingEvidence['kind'], 'self-reported registration');
    expect(useSupplementRating(back).rating, 1650);
  });

  test('an unrated entry can take the supplement and go back to unrated', () {
    final unrated = Player(id: 'u', name: 'New', memberId: '12345678');
    final applied = applyRatingObservation(unrated, seen, 'R');
    expect(ratingChoice(applied)!.entered, 0);
    expect(useEnteredRating(applied).rating, 0);
  });
}
