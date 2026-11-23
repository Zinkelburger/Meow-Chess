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

/// The section one step down from [section] by announced rating cap: the
/// capped section with the highest ceiling below [section]'s own, or below
/// an open section, any capped one. Null when [section] is the lowest.
Section? sectionBelow(Event event, Section section) {
  Section? below;
  for (final s in event.sections) {
    if (s.id == section.id || s.sideGames || s.ratingCeiling == 0) continue;
    if (section.ratingCeiling > 0 && s.ratingCeiling >= section.ratingCeiling) {
      continue;
    }
    if (below == null || s.ratingCeiling > below.ratingCeiling) below = s;
  }
  return below;
}

/// The lowest rating that may play up into [section] under the event's
/// announced play-up rule ([Event.playUpLimit] points below the cap of the
/// section beneath it); zero when there is no rule or no section beneath.
int playUpFloor(Event event, Section section) {
  if (event.playUpLimit <= 0 || section.sideGames) return 0;
  final below = sectionBelow(event, section);
  if (below == null) return 0;
  final floor = below.ratingCeiling - event.playUpLimit;
  return floor > 0 ? floor : 0;
}

/// Why [player] is rated too low to play up into [section], or null.
/// Unrated players may enter any section; a recorded exception, a house
/// player and a withdrawn player are never flagged.
String? playUpProblem(Event event, Player player, Section section) {
  final floor = playUpFloor(event, section);
  if (floor == 0 || player.unrated) return null;
  if (player.house || player.withdrawn) return null;
  if (section.rangeExceptions.containsKey(player.id)) return null;
  final rating = player.effectivePairingRating;
  if (rating >= floor) return null;
  return 'Rated $rating: playing up into ${section.name} takes $floor or '
      'more, within ${event.playUpLimit} points of the '
      '${sectionBelow(event, section)!.name} cap.';
}

/// Why [player] does not belong in [section]: outside its announced rating
/// range, or rated too low to play up into it. Null when they belong.
String? eligibilityProblem(Event event, Player player, Section section) =>
    ratingRangeProblem(player, section) ??
    playUpProblem(event, player, section);

/// What [section] asks of a rating, in sentences for the roster: its
/// announced range, then the play-up rule and who that rule leaves alone.
/// Empty when anyone may enter.
String eligibilityRule(Event event, Section section) {
  final range = ratingRangeText(section);
  final floor = playUpFloor(event, section);
  return [
    if (range.isNotEmpty) '${section.name} is for players rated $range.',
    if (floor > 0) 'Playing up into ${section.name} takes $floor or more.',
    if (floor > 0 && section.ratingFloor == 0) 'Unrated players may enter.',
  ].join(' ');
}

/// The section [player]'s rating puts them in: the lowest-capped section
/// that admits them, else an open one that does. Null when none does, or
/// when the only one is where they already are.
Section? sectionByRating(Event event, Player player) {
  final current = event.sectionOf(player.id);
  final fits = [
    for (final s in event.sections)
      if (!s.sideGames &&
          s.id != current?.id &&
          eligibilityProblem(
                event,
                player,
                s.copy(rangeExceptions: const {}),
              ) ==
              null)
        s,
  ];
  if (fits.isEmpty) return null;
  int cap(Section s) => s.ratingCeiling == 0 ? 1 << 30 : s.ratingCeiling;
  return fits.reduce((a, b) => cap(b) < cap(a) ? b : a);
}

/// A rating cap a section's name announces: "U1800", "Under 1800" and
/// "u-1800" all say 1800. Zero when the name states none.
int ratingCapInName(String name) {
  final match = RegExp(
    r'^\s*(?:u|under)[\s\-]*(\d{3,4})\b',
    caseSensitive: false,
  ).firstMatch(name);
  return match == null ? 0 : int.parse(match[1]!);
}

/// Every entrant of [section] who does not belong in it, by player ID.
Map<String, String> sectionRangeProblems(Event event, Section section) => {
  for (final id in section.players)
    id: ?eligibilityProblem(event, event.player(id), section),
};

/// Every entrant of [event] outside their section's rating range.
Map<String, String> eventRangeProblems(Event event) => {
  for (final s in event.sections) ...sectionRangeProblems(event, s),
};
