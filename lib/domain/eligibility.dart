import 'model.dart';

/// [section]'s announced rating range in words, as it completes "for
/// players rated …": `800–1999`, `under 1000`, `800 and over`. Empty when
/// the section is open.
String ratingRangeText(Section section) {
  final floor = section.ratingFloor, ceiling = section.ratingCeiling;
  if (floor > 0 && ceiling > 0) return '$floor–${ceiling - 1}';
  if (ceiling > 0) return 'under $ceiling';
  if (floor > 0) return '$floor and over';
  return '';
}

/// Rule 28H / K03: why [player]'s rating keeps them out of [section], in
/// the director's words, or null when it does not. Eligibility goes by the
/// rating the player pairs with: an unrated player is below any floor and
/// under any ceiling. A recorded exception, a house player and a withdrawn
/// player are never flagged.
String? ratingRangeProblem(Player player, Section section) {
  if (section.ratingFloor == 0 && section.ratingCeiling == 0) return null;
  if (player.house || player.withdrawn) return null;
  if (section.rangeExceptions.containsKey(player.id)) return null;
  final rating = player.effectivePairingRating;
  final below = section.ratingFloor > 0 && rating < section.ratingFloor;
  final above = section.ratingCeiling > 0 && rating >= section.ratingCeiling;
  if (!below && !above) return null;
  return '${player.unrated ? 'Unrated' : 'Rated $rating'}: '
      '${section.name} is for players rated ${ratingRangeText(section)}.';
}

/// Every entrant of [section] outside its rating range, by player ID.
Map<String, String> sectionRangeProblems(Event event, Section section) => {
  for (final id in section.players)
    id: ?ratingRangeProblem(event.player(id), section),
};

/// Every entrant of [event] outside their section's rating range.
Map<String, String> eventRangeProblems(Event event) => {
  for (final s in event.sections) ...sectionRangeProblems(event, s),
};
