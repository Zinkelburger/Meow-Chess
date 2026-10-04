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
  bool alreadyApplied(Player player, String category) =>
      player.rating == ratings[category] &&
      player.ratingEvidence['id'] == id &&
      player.ratingEvidence['category'] == category &&
      supplementDate != null &&
      player.ratingEvidence['supplementDate'] == supplementDate;

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

class RatingsApi {
  RatingsApi(this.client);
  final http.Client client;

  /// Bounded name search. Results are candidates, never an identity decision.
  Future<List<MemberObservation>> search(String name, {String key = ''}) async {
    final query = name.trim();
    if (query.length < 2) {
      throw const TournamentException('Enter at least two letters of a name.');
    }
    final publicAccess = key.trim().isEmpty;
    final request =
        http.Request(
            'GET',
            Uri.https(
              'ratings-api.uschess.org',
              '/api/${publicAccess ? 'v1' : 'v2'}/members',
              {'Fuzzy': query, 'Offset': '0', 'Size': '10'},
            ),
          )
          ..followRedirects = false
          ..headers.addAll({
            if (!publicAccess) 'X-Api-Key': key,
            'Accept': 'application/json',
          });
    final response = await client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw _requestFailure(response.statusCode, publicAccess);
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Json || decoded['items'] is! List) {
        throw const FormatException();
      }
      final results = <MemberObservation>[];
      for (final row in (decoded['items'] as List).take(10)) {
        if (row is! Json) throw const FormatException();
        final member = MemberObservation.parse(row, DateTime.now());
        if (!isMemberId(member.id) || member.name.trim().isEmpty) {
          throw const FormatException();
        }
        results.add(member);
      }
      return List.unmodifiable(results);
    } catch (_) {
      throw const TournamentException(
        'Unreadable US Chess search results. Try again later.',
      );
    }
  }

  TournamentException _requestFailure(
    int status,
    bool publicAccess,
  ) => TournamentException(switch (status) {
    401 || 403 =>
      publicAccess
          ? 'Public US Chess access is unavailable. Add an API key in Data sources or try later.'
          : 'US Chess rejected this API key. Update it in Data sources.',
    429 =>
      'US Chess rate limit reached. Retry later; local operation remains available.',
    _ => 'US Chess lookup failed (HTTP $status). No local record was changed.',
  });

  /// The public v1 route is an observed service capability, not an access guarantee.
  /// A dated supplement is required; a profile timestamp cannot date a rating.
  Future<MemberObservation> supplement(String id, {String key = ''}) async {
    final publicAccess = key.trim().isEmpty;
    final profile = await member(id, key, publicAccess: publicAccess);
    final request =
        http.Request(
            'GET',
            Uri.https(
              'ratings-api.uschess.org',
              '/api/${publicAccess ? 'v1' : 'v2'}/members/$id/rating-supplements',
              {'Offset': '0', 'Size': '24'},
            ),
          )
          ..followRedirects = false
          ..headers.addAll({
            if (!publicAccess) 'X-Api-Key': key,
            'Accept': 'application/json',
          });
    final response = await client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw TournamentException(
        'Monthly supplement lookup failed (HTTP ${response.statusCode}). No rating changed.',
      );
    }
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final now = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final items =
          (decoded['items'] as List).whereType<Map<String, dynamic>>().where((
            item,
          ) {
            final date = item['ratingSupplementDate'];
            return date is String &&
                isEventDate(date) &&
                date.compareTo(now) <= 0;
          }).toList()..sort(
            (a, b) => (b['ratingSupplementDate'] as String).compareTo(
              a['ratingSupplementDate'] as String,
            ),
          );
      // A successful empty response is normal for an unrated member. Do not
      // substitute the live profile rating for a dated monthly supplement.
      if ((decoded['items'] as List).isEmpty) {
        return MemberObservation(
          id: profile.id,
          name: profile.name,
          retrievedAt: profile.retrievedAt,
          ratings: const {},
          expiration: profile.expiration,
          status: profile.status,
          state: profile.state,
          reportName: profile.reportName,
          provider: publicAccess ? 'US Chess public v1' : 'US Chess API v2',
        );
      }
      if (items.isEmpty) throw const FormatException();
      final latest = items.first;
      final ratings = <String, int?>{};
      for (final row in latest['ratings'] as List) {
        final value = row['rating'];
        if (row['source'] is String) {
          ratings[row['source']] = value is int && value >= 0 && value <= 4000
              ? value
              : null;
        }
      }
      return MemberObservation(
        id: profile.id,
        name: profile.name,
        retrievedAt: profile.retrievedAt,
        ratings: Map.unmodifiable(ratings),
        expiration: profile.expiration,
        status: profile.status,
        state: profile.state,
        reportName: profile.reportName,
        supplementDate: latest['ratingSupplementDate'],
        provider: publicAccess ? 'US Chess public v1' : 'US Chess API v2',
      );
    } catch (_) {
      throw const TournamentException(
        'No readable dated monthly supplement was returned. Keep the local rating and try again later.',
      );
    }
  }

  Future<MemberObservation> member(
    String id,
    String key, {
    bool publicAccess = false,
  }) async {
    if (!isMemberId(id)) {
      throw const TournamentException('Enter an eight-digit ID first.');
    }
    if (key.trim().isEmpty && !publicAccess) {
      throw const TournamentException(
        'An operator-provided US Chess API key is required.',
      );
    }
    // Custom API-key headers are not stripped by Dart's cross-origin redirect
    // handling. Refuse redirects so a provider response cannot forward the key.
    final request =
        http.Request(
            'GET',
            Uri.https(
              'ratings-api.uschess.org',
              '/api/${publicAccess ? 'v1' : 'v2'}/members/$id',
            ),
          )
          ..followRedirects = false
          ..headers.addAll({
            if (!publicAccess) 'X-Api-Key': key,
            'Accept': 'application/json',
          });
    final response = await client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      if (response.statusCode == 404) throw const MemberNotFound();
      throw _requestFailure(response.statusCode, publicAccess);
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
    return MemberObservation(
      id: result.id,
      name: result.name,
      retrievedAt: result.retrievedAt,
      ratings: result.ratings,
      expiration: result.expiration,
      status: result.status,
      state: result.state,
      reportName: result.reportName,
      provider: publicAccess ? 'US Chess public v1' : 'US Chess API v2',
    );
  }
}

class MemberNotFound extends TournamentException {
  const MemberNotFound()
    : super('Member ID not found. No local record was changed.');
}
