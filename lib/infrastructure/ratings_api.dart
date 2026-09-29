import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/model.dart';

class MemberObservation {
  const MemberObservation({
    required this.id,
    required this.name,
    required this.retrievedAt,
    required this.ratings,
    this.expiration,
    this.status,
    this.state,
  });
  final String id, name, retrievedAt;
  final String? expiration, status, state;
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
    final response = await client
        .get(
          Uri.https('ratings-api.uschess.org', '/api/v2/members/$id'),
          headers: {'X-Api-Key': key, 'Accept': 'application/json'},
        )
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
    final decoded = jsonDecode(response.body);
    if (decoded is! Json) {
      throw const TournamentException('Unexpected US Chess response.');
    }
    final result = MemberObservation.parse(decoded, DateTime.now());
    if (result.id != id) {
      throw const TournamentException(
        'The provider returned a different identity. No local data was changed.',
      );
    }
    return result;
  }
}
