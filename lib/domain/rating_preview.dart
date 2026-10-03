import 'dart:math' as math;

import 'model.dart';
import 'us_chess.dart';

/// A display-only, single-pass Regular rating estimate. Never a pairing input.
class RatingPreview {
  const RatingPreview({this.rating, this.change, this.games = 0, this.reason});

  final int? rating, change;
  final int games;
  final String? reason;
}

/// Uses the US Chess standard formula (April 2026, sections 3 and 4.2):
/// https://new.uschess.org/sites/default/files/media/documents/us_chess_rating_system_specs-2026-04-06.pdf
///
/// We do not have lifetime game counts or personal floors. Assume 50 prior
/// games and use starting opponent ratings, not the official second pass.
/// Recompute from all completed games in this section, never from a previous
/// preview. Unrated opponents make the entire estimate unavailable.
RatingPreview previewRating(Event event, Section? section, Player player) {
  if (section == null) {
    return const RatingPreview(reason: 'No section assigned.');
  }
  RatingCategory? category;
  try {
    category = TimeControl.parse(section.effectiveTimeControl(event)).category;
  } on TournamentException {
    return const RatingPreview(reason: 'A recognized time control is needed.');
  }
  if (category != RatingCategory.regular && category != RatingCategory.dual) {
    return const RatingPreview(
      reason: 'Regular rating previews require a Regular or Dual time control.',
    );
  }
  bool regularRating(Player p) =>
      p.rating > 0 &&
      (p.ratingEvidence['category'] == null ||
          p.ratingEvidence['category'] == 'regular');
  if (!regularRating(player)) {
    return const RatingPreview(reason: 'A starting Regular rating is needed.');
  }
  final games = section.rounds
      .expand((r) => r.games)
      .where(
        (g) =>
            g.outcome.played && (g.white == player.id || g.black == player.id),
      )
      .toList();
  if (games.isEmpty) {
    return const RatingPreview(
      reason: 'No completed played games in this section.',
    );
  }
  final opponents = <String, int>{};
  var score = 0.0, expected = 0.0;
  for (final game in games) {
    final white = game.white == player.id;
    final opponent = event.player(white ? game.black : game.white);
    if (!regularRating(opponent)) {
      return RatingPreview(
        games: games.length,
        reason: '${opponent.name} needs a starting Regular rating.',
      );
    }
    opponents.update(opponent.id, (n) => n + 1, ifAbsent: () => 1);
    score += (white ? game.outcome.whiteScore : game.outcome.blackScore) / 2;
    expected += 1 / (1 + math.pow(10, (opponent.rating - player.rating) / 400));
  }
  final prior = player.rating;
  final effectiveGames = prior > 2355
      ? 50.0
      : math.min(
          50.0,
          50 / math.sqrt(0.662 + 0.00000739 * math.pow(2569 - prior, 2)),
        );
  var k = 800 / (effectiveGames + games.length);
  if (category == RatingCategory.dual && prior > 2200) {
    k *= prior >= 2500 ? 0.25 : 6.5 - 0.0025 * prior;
  }
  final baseChange = k * (score - expected);
  final bonusEligible =
      games.length >= 3 &&
      opponents.values.every((n) => n <= (games.length == 3 ? 1 : 2));
  final bonus = bonusEligible
      ? math.max(0.0, baseChange - 10 * math.sqrt(math.max(games.length, 4)))
      : 0.0;
  final rating = math.max(100, (prior + baseChange + bonus).round());
  return RatingPreview(
    rating: rating,
    change: rating - prior,
    games: games.length,
  );
}
