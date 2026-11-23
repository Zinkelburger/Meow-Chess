import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/model.dart';
import '../domain/posted_results.dart';
import 'results_sources/registry.dart';

export 'results_sources/registry.dart' show defaultResultsPage;
import 'results_sources/source.dart';
import 'web_roster.dart' show decodeWebText;

/// The page read for [url], or a plain refusal when it is not a results
/// page this app knows how to read.
Uri resolveResultsUrl(
  String url, {
  List<ClubResultsSource> sources = clubResultsSources,
}) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw const TournamentException(
      'Enter the HTTPS address of the club\'s results page.',
    );
  }
  final source = sources.where((s) => s.matches(uri)).firstOrNull;
  if (source == null) {
    throw TournamentException(
      'Results cannot be read from this page. Pages that can: '
      '${sources.map((s) => s.name).join(', ')} '
      '($defaultResultsPage).',
    );
  }
  return source.resultsUrl(uri);
}

/// The results page that goes with the entry list at [rosterUrl], if it is
/// a club's whose results can be read.
String? suggestResultsUrl(
  String rosterUrl, {
  List<ClubResultsSource> sources = clubResultsSources,
}) {
  final uri = Uri.tryParse(rosterUrl.trim());
  if (uri == null || uri.scheme != 'https') return null;
  for (final source in sources) {
    if (source.resultsUrlForRoster(uri) case final page?) {
      return page.toString();
    }
  }
  return null;
}

/// Reads the results a club's website shows for the rounds being played.
/// It only reads: nothing is ever sent to the website.
class WebResults {
  WebResults(this.client, {this.sources = clubResultsSources});
  final http.Client client;
  final List<ClubResultsSource> sources;

  /// The rounds the page at [url] lists now. One page of at most 2 MB,
  /// without following redirects.
  Future<List<PostedRound>> fetch(String url) async {
    final page = resolveResultsUrl(url, sources: sources);
    final source = sources.firstWhere((s) => s.matches(page));
    final request = http.Request('GET', page)..followRedirects = false;
    final unreachable =
        'Could not reach ${page.host}. Check the internet connection.';
    final http.StreamedResponse response;
    final bytes = <int>[];
    try {
      response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      const limit = 2 * 1024 * 1024;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > limit) {
          throw TournamentException(
            'The results page of ${page.host} is too large to read.',
          );
        }
      }
    } on TimeoutException {
      throw TournamentException(
        'Could not reach ${page.host}: no response within 20 seconds.',
      );
    } on http.ClientException {
      throw TournamentException(unreachable);
    } on IOException {
      throw TournamentException(unreachable);
    }
    if (response.statusCode != 200) {
      throw TournamentException(
        'Could not read the results page of ${page.host} '
        '(HTTP ${response.statusCode}).',
      );
    }
    try {
      return source.parse(
        decodeWebText(bytes, contentType: response.headers['content-type']),
      );
    } on FormatException {
      throw TournamentException(
        'The results page of ${page.host} has no pairings on it, or its '
        'layout has changed.',
      );
    }
  }
}
