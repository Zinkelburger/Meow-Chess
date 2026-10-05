import 'member_observation.dart';
import 'model.dart';
import 'rating_system.dart';

/// Explains why an observed rating cannot replace the reviewed local value.
/// Unrelated edits do not invalidate a review; identity, rating and pairings do.
String? ratingUpdateProblem({
  required Event current,
  required Event snapshot,
  required Player player,
  required MemberObservation observation,
  required String category,
}) {
  if (current.id != snapshot.id) return 'Event changed. Refresh again.';
  final original = snapshot.players.where((p) => p.id == player.id).firstOrNull;
  if (original == null) {
    return 'Added after this refresh. Refresh again to include.';
  }
  if (original.memberId != player.memberId ||
      original.rating != player.rating) {
    return 'Edited since lookup. Refresh again to review this player.';
  }
  if (observation.id != player.memberId) {
    return 'The returned member does not match the requested ID.';
  }
  final system = RatingSystem.parse(category);
  if (system == null) return 'Choose a recognized rating system.';
  final rating = observation.ratings[system.code];
  if (rating == null || rating <= 0 || rating > 4000) {
    return 'No ${system.label} rating. Current rating kept.';
  }
  if (observation.supplementDate == null) {
    return 'No dated supplement. Retry later.';
  }
  if (current.sectionOf(player.id)?.rounds.isNotEmpty ?? false) {
    return 'Pairings posted. Pairing rating kept.';
  }
  if (observation.alreadyApplied(player, category)) {
    return 'Already up to date.';
  }
  return null;
}

/// Applies approved evidence without discarding a more recent membership check.
Player applyRatingObservation(
  Player player,
  MemberObservation observation,
  String category,
) {
  final system = RatingSystem.parse(category);
  if (system == null) {
    throw const TournamentException('Choose a recognized rating system.');
  }
  final previous = DateTime.tryParse(
    '${player.membershipEvidence['retrievedAt']}',
  );
  final retrieved = DateTime.tryParse(observation.retrievedAt);
  return player.copy(
    rating: observation.ratings[system.code],
    ratingEvidence: {
      ...player.ratingEvidence,
      ...observation.toJson(),
      'kind': 'monthly supplement',
      'category': system.code,
    },
    membershipEvidence:
        previous != null && (retrieved == null || previous.isAfter(retrieved))
        ? player.membershipEvidence
        : observation.toJson(),
  );
}
