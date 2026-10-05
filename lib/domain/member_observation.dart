import 'model.dart';
import 'rating_system.dart';

/// Provider evidence kept separate from the locally approved player fields.
class MemberObservation {
  const MemberObservation({
    required this.id,
    required this.name,
    required this.retrievedAt,
    required this.ratings,
    this.expiration,
    this.status,
    this.state,
    this.reportName,
    this.supplementDate,
    this.provider = 'US Chess',
  });
  final String id, name, retrievedAt;
  final String? expiration, status, state;
  final String? supplementDate;
  final String provider;

  /// `LAST, FIRST` from the separate US Chess name fields.
  final String? reportName;
  final Map<String, int?> ratings;
  bool alreadyApplied(Player player, String category) {
    final system = RatingSystem.parse(category);
    return system != null &&
        player.rating == ratings[system.code] &&
        player.ratingEvidence['id'] == id &&
        RatingSystem.parse(player.ratingEvidence['category']) == system &&
        supplementDate != null &&
        player.ratingEvidence['supplementDate'] == supplementDate;
  }

  Json toJson() => {
    'id': id,
    'name': name,
    'retrievedAt': retrievedAt,
    'ratings': ratings,
    'expiration': expiration,
    'status': status,
    'state': state,
    'reportName': reportName,
    'supplementDate': supplementDate,
    'provider': provider,
  };
}
