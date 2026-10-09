import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import '../domain/model.dart';
import 'roster_import.dart';
import 'roster_sources/html_table.dart';
import 'roster_sources/registry.dart';
import 'roster_sources/source.dart';

export 'roster_sources/html_table.dart' show parseWebRoster;

class WebRoster {
  WebRoster(this.client, {this.sources = clubRosterSources});
  final http.Client client;
  final List<ClubRosterSource> sources;

  Uri _validatedUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const TournamentException(
        'Enter an HTTPS event or entry-list URL without a login or fragment.',
      );
    }
    return uri;
  }

  Future<List<ImportRow>> fetch(String url) async {
    final supplied = _validatedUrl(url);
    final source =
        sources.where((source) => source.matches(supplied)).firstOrNull ??
        const HtmlTableRosterSource();
    final uri = _validatedUrl(source.entryListUrl(supplied).toString());
    final request = http.Request('GET', uri)..followRedirects = false;
    final unreachable =
        'Could not reach ${uri.host}. Check the internet connection and the '
        'URL, then try again. Your roster is unchanged.';
    final http.StreamedResponse response;
    final bytes = <int>[];
    try {
      response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw TournamentException(
          'Could not read the entry list (HTTP ${response.statusCode}). For a redirect, paste the final page URL. Your roster is unchanged.',
        );
      }
      const limit = 2 * 1024 * 1024;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > limit) {
          throw const TournamentException(
            'This page is too large. Import a CSV instead.',
          );
        }
      }
    } on TimeoutException {
      throw TournamentException(
        'Could not reach ${uri.host}: no response within 20 seconds. Try '
        'again later. Your roster is unchanged.',
      );
    } on http.ClientException {
      throw TournamentException(unreachable);
    } on IOException {
      throw TournamentException(unreachable);
    }
    return source.parse(
      decodeWebText(bytes, contentType: response.headers['content-type']),
    );
  }
}

/// Page text in the character set the server or the page declares; without
/// one (or with one this cannot read), as [decodeRosterText] reads files.
String decodeWebText(List<int> bytes, {String? contentType}) {
  String? charset(String text) => RegExp(
    r'''charset\s*=\s*["']?\s*([A-Za-z0-9._:\-]+)''',
    caseSensitive: false,
  ).firstMatch(text)?.group(1);
  var declared = contentType == null ? null : charset(contentType);
  if (declared == null) {
    // A page's <meta charset> must appear within its first 1024 bytes.
    final head = String.fromCharCodes(
      bytes.take(1024).map((b) => b < 0x80 ? b : 0x3F),
    );
    for (final meta in RegExp(
      r'<meta\b[^>]*>',
      caseSensitive: false,
    ).allMatches(head)) {
      if (charset(meta.group(0)!) case final found?) {
        declared = found;
        break;
      }
    }
  }
  return decodeRosterText(bytes, charset: declared);
}

class RosterChange {
  const RosterChange(
    this.incoming,
    this.existing, {
    this.problem,
    this.sourceChanged = true,
  });
  final Player incoming;
  final Player? existing;
  final String? problem;
  final bool sourceChanged;
  bool get changed =>
      existing == null ||
      (sourceChanged &&
          (existing!.name != incoming.name ||
              existing!.rating != incoming.rating ||
              existing!.registrationNote != incoming.registrationNote));
  String get key => incoming.id;
}

/// A proposal against one event revision. Never infers identity from a name.
class RosterReview {
  RosterReview(Event event, this.url, this.rows)
    : eventId = event.id,
      revision = event.revision,
      fetchedAt = DateTime.now().toUtc().toIso8601String() {
    final players = rows.map((r) => r.player).whereType<Player>().toList();
    for (final p in players) {
      final matches = event.players
          .where((old) => p.memberId.isNotEmpty && old.memberId == p.memberId)
          .toList();
      final duplicate =
          players
              .where(
                (other) => p.memberId.isNotEmpty
                    ? other.memberId == p.memberId
                    : other.name.toLowerCase() == p.name.toLowerCase(),
              )
              .length >
          1;
      final ambiguous =
          matches.isEmpty &&
          event.players.any(
            (old) =>
                old.name.trim().toLowerCase() == p.name.trim().toLowerCase(),
          );
      final baseline = event.rosterSource['url'] == url && p.memberId.isNotEmpty
          ? ((event.rosterSource['entries'] as Map?)?[p.memberId] as Map?)
          : null;
      changes.add(
        RosterChange(
          p,
          matches.firstOrNull,
          sourceChanged:
              baseline == null ||
              baseline['name'] != p.name ||
              baseline['rating'] != p.rating ||
              (baseline['registrationNote'] ?? '') != p.registrationNote,
          problem: duplicate || matches.length > 1
              ? 'Duplicate ID/name in this list. Resolve before importing.'
              : ambiguous
              ? 'A local player has this name. Resolve the identity manually.'
              : null,
        ),
      );
    }
    final prior = event.rosterSource['url'] == url
        ? (event.rosterSource['memberIds'] as List? ?? [])
              .whereType<String>()
              .toSet()
        : <String>{};
    final present = players.map((p) => p.memberId).toSet();
    missing = event.players
        .where(
          (p) => prior.contains(p.memberId) && !present.contains(p.memberId),
        )
        .toList();
  }
  final int revision;
  final String eventId;
  final String url, fetchedAt;
  final List<ImportRow> rows;
  final changes = <RosterChange>[];
  late final List<Player> missing;
  Event apply(Event event, Set<String> selected) {
    if (event.id != eventId || event.revision != revision) {
      throw const TournamentException(
        'The event changed. Fetch and review the entry list again.',
      );
    }
    if (rows.every((r) => r.player == null)) {
      throw const TournamentException(
        'No readable players. The saved source is unchanged.',
      );
    }
    final result = [...event.players];
    for (final item in changes.where((r) => selected.contains(r.key))) {
      if (item.problem != null) throw TournamentException(item.problem!);
      final old = item.existing, incoming = item.incoming;
      if (old == null) {
        result.add(
          incoming.copy(
            ratingEvidence: {
              'source': url,
              'kind': 'self-reported registration',
              'retrievedAt': fetchedAt,
              'registrationRating': incoming.rating,
            },
          ),
        );
      } else {
        if (event.sectionOf(old.id)?.rounds.isNotEmpty ?? false) {
          if (old.registrationNote == incoming.registrationNote) {
            throw const TournamentException(
              'Pairings are posted. Keep the current rating; review changes before the event starts.',
            );
          }
          result[result.indexWhere((p) => p.id == old.id)] = old.copy(
            registrationNote: incoming.registrationNote,
          );
          continue;
        }
        result[result.indexWhere((p) => p.id == old.id)] = old.copy(
          name: incoming.name,
          registrationNote: incoming.registrationNote,
          rating: old.ratingEvidence['supplementDate'] != null
              ? old.rating
              : incoming.rating,
          ratingEvidence: old.ratingEvidence['supplementDate'] != null
              ? {...old.ratingEvidence, 'registrationRating': incoming.rating}
              : {
                  'source': url,
                  'kind': 'self-reported registration',
                  'retrievedAt': fetchedAt,
                  'registrationRating': incoming.rating,
                },
        );
      }
    }
    return event.copy(
      players: result,
      rosterSource: {
        'url': url,
        'fetchedAt': fetchedAt,
        'memberIds': {
          if (event.rosterSource['url'] == url)
            ...(event.rosterSource['memberIds'] as List? ?? [])
                .whereType<String>(),
          ...changes
              .where((r) => r.incoming.memberId.isNotEmpty)
              .map((r) => r.incoming.memberId),
        }.toList(),
        'entries': {
          for (final change in changes)
            if (change.incoming.memberId.isNotEmpty)
              change.incoming.memberId: {
                'name': change.incoming.name,
                'rating': change.incoming.rating,
                'registrationNote': change.incoming.registrationNote,
              },
        },
        'rows': rows
            .map((r) => {'line': r.line, 'raw': r.raw, 'error': r.error})
            .toList(),
      },
    );
  }
}
