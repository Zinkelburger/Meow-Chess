import 'model.dart';
import 'rating_system.dart';

/// The two ratings a director can switch a player between before pairing:
/// the one entered for them (registration, import or typed) and the US
/// Chess supplement rating last looked up. Whichever is not in use stays in
/// the player's rating evidence, so switching needs no new lookup.
///
/// A supplement in use keeps today's evidence shape (`supplementDate`,
/// `ratings`, `category` at the top) plus `entered`: the rating it replaced
/// and that rating's own evidence. An entered rating in use keeps its own
/// evidence plus `supplement`: the looked-up record and its rating system.
class RatingChoice {
  const RatingChoice({
    required this.entered,
    required this.supplement,
    required this.supplementDate,
    required this.system,
    required this.usingSupplement,
  });

  /// 0 when the player was entered as unrated.
  final int entered;
  final int supplement;
  final String supplementDate;
  final RatingSystem system;
  final bool usingSupplement;
}

/// The player's rating is a US Chess supplement rating.
bool usesSupplement(Player p) => p.ratingEvidence['supplementDate'] != null;

/// Rating evidence without the rating kept on file beside the one in use.
Json plainRatingEvidence(Json evidence) => {
  for (final MapEntry(:key, :value) in evidence.entries)
    if (key != 'entered' && key != 'supplement') key: value,
};

/// The fields of a US Chess lookup kept with a supplement on file.
const _supplementKeys = [
  'id',
  'name',
  'retrievedAt',
  'ratings',
  'expiration',
  'status',
  'state',
  'reportName',
  'supplementDate',
  'provider',
  'fideId',
  'fideTitle',
  'fideCountry',
  'gender',
];

/// The rating a supplement replaced, with its evidence. Events saved before
/// the choice existed kept only the registration rating.
(int, Json)? _entered(Json evidence) {
  if (evidence['entered'] case {'rating': final int rating} && final kept) {
    return (
      rating,
      kept['evidence'] is Map
          ? Map<String, dynamic>.from(kept['evidence'] as Map)
          : const {},
    );
  }
  if (evidence['registrationRating'] case final int rating) {
    return (
      rating,
      {
        'source': ?evidence['source'],
        'kind': 'self-reported registration',
        'registrationRating': rating,
      },
    );
  }
  return null;
}

/// What [p] can be switched between; null when only one rating is known.
RatingChoice? ratingChoice(Player p) {
  final evidence = p.ratingEvidence;
  if (usesSupplement(p)) {
    final entered = _entered(evidence);
    final system = RatingSystem.parse(evidence['category']);
    final date = evidence['supplementDate'];
    if (entered == null || system == null || date is! String || p.rating <= 0) {
      return null;
    }
    return RatingChoice(
      entered: entered.$1,
      supplement: p.rating,
      supplementDate: date,
      system: system,
      usingSupplement: true,
    );
  }
  final onFile = evidence['supplement'];
  // A supplement looked up for another ID is not this player's.
  if (onFile is! Map || onFile['id'] != p.memberId) return null;
  final system = RatingSystem.parse(onFile['category']) ?? RatingSystem.regular;
  final ratings = onFile['ratings'];
  final rating = ratings is Map ? ratings[system.code] : null;
  final date = onFile['supplementDate'];
  if (rating is! int || rating <= 0 || rating > 4000 || date is! String) {
    return null;
  }
  return RatingChoice(
    entered: p.rating,
    supplement: rating,
    supplementDate: date,
    system: system,
    usingSupplement: false,
  );
}

/// The evidence for a supplement rating replacing [player]'s rating, with
/// the rating it replaces kept so the director can switch back. A newer
/// supplement over an older one keeps the entered rating already on file.
Json supplementEvidence(Player player, Json supplement, RatingSystem system) {
  final evidence = player.ratingEvidence;
  final plain = plainRatingEvidence(evidence);
  final entered = usesSupplement(player)
      ? evidence['entered']
      : {'rating': player.rating, 'evidence': plain};
  return {
    ...plain,
    ...supplement,
    'kind': 'monthly supplement',
    'category': system.code,
    'entered': ?entered,
  };
}

/// [p] on the US Chess supplement rating on file.
Player useSupplementRating(Player p) {
  final choice = ratingChoice(p);
  if (choice == null || choice.usingSupplement) return p;
  final onFile = Map<String, dynamic>.from(
    p.ratingEvidence['supplement'] as Map,
  )..remove('category');
  return p.copy(
    rating: choice.supplement,
    ratingEvidence: supplementEvidence(p, onFile, choice.system),
  );
}

/// [p] back on the rating entered for them, the supplement kept on file.
Player useEnteredRating(Player p) {
  final choice = ratingChoice(p);
  if (choice == null || !choice.usingSupplement) return p;
  final (rating, evidence) = _entered(p.ratingEvidence)!;
  return p.copy(
    rating: rating,
    ratingEvidence: {
      ...evidence,
      'supplement': _onFile(p.ratingEvidence, choice.system),
    },
  );
}

/// The supplement record [p] holds, in use or not, as it is kept on file
/// beside an entered rating; null when no supplement was ever looked up.
Json? supplementOnFile(Player p) {
  final evidence = p.ratingEvidence;
  if (usesSupplement(p)) {
    return _onFile(
      evidence,
      RatingSystem.parse(evidence['category']) ?? RatingSystem.regular,
    );
  }
  final onFile = evidence['supplement'];
  return onFile is Map ? Map<String, dynamic>.from(onFile) : null;
}

Json _onFile(Json lookup, RatingSystem system) => {
  for (final key in _supplementKeys)
    if (lookup.containsKey(key)) key: lookup[key],
  'category': system.code,
};

/// [player]'s rating evidence with the supplement in [lookup] on file as
/// the alternative to their entered rating; null when there is nothing to
/// add: no dated supplement, or the supplement is already their rating.
/// [lookup] is a member observation, with `category` when the director
/// reviewed a particular rating system.
Json? withSupplementOnFile(Player player, Json lookup) {
  if (usesSupplement(player) ||
      lookup['supplementDate'] is! String ||
      lookup['ratings'] is! Map) {
    return null;
  }
  final before = player.ratingEvidence['supplement'];
  final system =
      RatingSystem.parse(lookup['category']) ??
      RatingSystem.parse(before is Map ? before['category'] : null) ??
      RatingSystem.regular;
  return {
    ...plainRatingEvidence(player.ratingEvidence),
    'supplement': _onFile(lookup, system),
  };
}
