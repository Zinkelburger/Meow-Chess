import 'fide.dart';
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
    this.fideId,
    this.fideTitle,
    this.fideCountry,
    this.gender,
  });
  final String id, name, retrievedAt;
  final String? expiration, status, state;
  final String? supplementDate;
  final String provider;

  /// FIDE identity as US Chess records it: the FIDE ID, the one-letter title
  /// code (`G`, `I`, `F`, …), the FIDE federation and `Male`/`Female`.
  final String? fideId, fideTitle, fideCountry, gender;

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

  /// [player] with the FIDE identity US Chess holds for this member; see
  /// [withUsChessFideIdentity].
  Player fideIdentityInto(Player player, {bool replaceFideId = false}) =>
      withUsChessFideIdentity(
        player,
        fideId: fideId,
        fideTitle: fideTitle,
        fideCountry: fideCountry,
        gender: gender,
        replaceFideId: replaceFideId,
      );

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
    if (fideId != null) 'fideId': fideId,
    if (fideTitle != null) 'fideTitle': fideTitle,
    if (fideCountry != null) 'fideCountry': fideCountry,
    if (gender != null) 'gender': gender,
  };
}

/// [player] with the FIDE identity US Chess holds for the member: the
/// FIDE ID, the title code, the federation and the gender fill blank fields
/// only. With [replaceFideId] (the TD chose this ID), the ID replaces the
/// stored one.
Player withUsChessFideIdentity(
  Player player, {
  String? fideId,
  String? fideTitle,
  String? fideCountry,
  String? gender,
  bool replaceFideId = false,
}) {
  final id = fideId?.trim() ?? '';
  final country = fideCountry?.trim() ?? '';
  return player.copy(
    fideId: (replaceFideId || player.fideId.isEmpty) && isFideId(id)
        ? id
        : null,
    title: player.title.isEmpty ? fideTitleFromCode(fideTitle) : null,
    federation: player.federation.isEmpty && isFederationCode(country)
        ? country
        : null,
    sex: player.sex.isEmpty ? sexFromUsChessGender(gender) : null,
  );
}

/// FIDE's `m`/`w` for the gender US Chess records (`Male`, `Female`, or
/// their initials); null when it says neither.
String? sexFromUsChessGender(String? gender) =>
    switch ((gender ?? '').trim().toLowerCase()) {
      'male' || 'm' => 'm',
      'female' || 'f' || 'w' => 'w',
      _ => null,
    };
