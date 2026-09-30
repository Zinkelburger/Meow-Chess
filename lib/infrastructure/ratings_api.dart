import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/model.dart';
import '../domain/us_chess.dart';

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
  });
  final String id, name, retrievedAt;
  final String? expiration, status, state;

  /// `LAST, FIRST` from the separate US Chess name fields.
  final String? reportName;
  final Map<String, int?> ratings;
  factory MemberObservation.parse(Json json, DateTime retrieved) {
    if (json['id'] is! String) {
      throw const TournamentException(
        'Provider response is missing a member identity.',
      );
    }
    final ratings = <String, int?>{};
    for (final value in (json['ratings'] as List? ?? [])) {
      if (value is Map && value['ratingSystem'] is String) {
        final rating = value['rating'];
        ratings[value['ratingSystem']] = rating is int ? rating : null;
      }
    }
    return MemberObservation(
      id: json['id'],
      name: [json['firstName'], json['lastName']].whereType<String>().join(' '),
      retrievedAt: retrieved.toUtc().toIso8601String(),
      ratings: Map.unmodifiable(ratings),
      expiration: json['expirationDate'] as String?,
      status: json['status'] as String?,
      state: json['stateRep'] as String?,
      reportName: json['lastName'] is String
          ? reportText(
              [
                json['lastName'] as String,
                if (json['firstName'] case final String first) first,
              ].where((x) => x.trim().isNotEmpty).join(', '),
            )?.toUpperCase()
          : null,
    );
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
  };
}

class RatingsApi {
  RatingsApi(this.client);
  final http.Client client;
  Future<MemberObservation> member(String id, String key) async {
    if (!RegExp(r'^\d{8}$').hasMatch(id)) {
      throw const TournamentException('Enter an eight-digit ID first.');
    }
    if (key.trim().isEmpty) {
      throw const TournamentException(
        'An operator-provided US Chess API key is required.',
      );
    }
    // Custom API-key headers are not stripped by Dart's cross-origin redirect
    // handling. Refuse redirects so a provider response cannot forward the key.
    final request =
        http.Request(
            'GET',
            Uri.https('ratings-api.uschess.org', '/api/v2/members/$id'),
          )
          ..followRedirects = false
          ..headers.addAll({'X-Api-Key': key, 'Accept': 'application/json'});
    final response = await client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw TournamentException(switch (response.statusCode) {
        401 ||
        403 => 'US Chess rejected this API key. Update it in Data sources.',
        404 => 'Member ID not found. No local record was changed.',
        429 =>
          'US Chess rate limit reached. Retry later; local operation remains available.',
        _ =>
          'US Chess lookup failed (HTTP ${response.statusCode}). No local record was changed.',
      });
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      // FormatException includes the response body; it may echo credentials.
      throw const TournamentException('Invalid JSON in the US Chess response.');
    }
    if (decoded is! Json) {
      throw const TournamentException('Unexpected US Chess response.');
    }
    final MemberObservation result;
    try {
      result = MemberObservation.parse(decoded, DateTime.now());
    } on TypeError {
      throw const TournamentException('Unexpected US Chess member fields.');
    }
    if (result.id != id) {
      throw const TournamentException(
        'The provider returned a different identity. No local data was changed.',
      );
    }
    return result;
  }
}
