import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../domain/announcement.dart';
import '../domain/model.dart';
import '../domain/rating_choice.dart';
import '../domain/section_placement.dart';
import '../domain/us_chess.dart';
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

  ClubRosterSource _sourceFor(Uri supplied) =>
      sources.where((source) => source.matches(supplied)).firstOrNull ??
      const HtmlTableRosterSource();

  Future<List<ImportRow>> fetch(String url) async {
    final supplied = _validatedUrl(url);
    final source = _sourceFor(supplied);
    final uri = _validatedUrl(source.entryListUrl(supplied).toString());
    final (:status, :text, location: _) = await _get(uri);
    if (status != 200) {
      throw TournamentException(
        'Could not read the entry list (HTTP $status). For a redirect, paste the final page URL. Your roster is unchanged.',
      );
    }
    return source.parse(text);
  }

  /// What the club's event page announces for the event of [url]: rounds,
  /// time control and its play-up and merge rules. Null when the club has
  /// no such page or it could not be read; an entry list imports without
  /// it. One redirect is followed, and only to another of the club's event
  /// pages (a short address to the full one).
  Future<Announcement?> fetchAnnouncement(String url) async {
    try {
      final supplied = _validatedUrl(url);
      final source = _sourceFor(supplied);
      final page = source.eventPageUrl(supplied);
      if (page == null) return null;
      var response = await _get(_validatedUrl(page.toString()));
      if (response.status >= 301 &&
          response.status <= 308 &&
          response.location != null) {
        final next = page.resolve(response.location!);
        if (!source.isEventPage(next)) return null;
        response = await _get(_validatedUrl(next.toString()));
      }
      return response.status == 200 ? source.parseEvent(response.text) : null;
    } on TournamentException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// One page of at most 2 MB, without following redirects.
  Future<({int status, String text, String? location})> _get(Uri uri) async {
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
    return (
      status: response.statusCode,
      text: response.statusCode == 200
          ? decodeWebText(bytes, contentType: response.headers['content-type'])
          : '',
      location: response.headers['location'],
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
  RosterReview(Event event, this.url, this.rows, {this.announcement})
    : eventId = event.id,
      revision = event.revision,
      fetchedAt = DateTime.now().toUtc().toIso8601String() {
    final players = rows.map((r) => r.player).whereType<Player>().toList();
    for (final p in players) {
      // Rule 28S: a re-entry shares its ID with the entry it replaced; the
      // list row is the person's latest entry.
      final matches = event.players
          .where(
            (old) =>
                isMemberId(p.memberId) &&
                old.memberId == p.memberId &&
                !event.players.any(
                  (later) =>
                      later.reentryOf == old.id &&
                      later.memberId == old.memberId,
                ),
          )
          .toList();
      final duplicate =
          players
              .where(
                (other) => isMemberId(p.memberId)
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
      final baseline =
          event.rosterSource['url'] == url && isMemberId(p.memberId)
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

  /// What the club's event page announces, when it could be read.
  final Announcement? announcement;
  final changes = <RosterChange>[];
  late final List<Player> missing;

  /// The section labels of the selected rows, by the ID of the player they
  /// place: the incoming entry when new, else the local one, which only
  /// moves if it is in no section yet.
  Map<String, String> _labels(Set<String> selected) => {
    for (final r in rows)
      if (r.player case final p? when r.section.trim().isNotEmpty)
        for (final change in changes)
          if (change.incoming.id == p.id && selected.contains(change.key))
            (change.existing?.id ?? p.id): r.section,
  };

  /// Where the Section column puts the [selected] changes once applied.
  SectionPlan sectionPlan(Event event, Set<String> selected) => planSections(
    event.copy(
      players: [
        ...event.players,
        for (final change in changes)
          if (change.existing == null && selected.contains(change.key))
            change.incoming,
      ],
    ),
    _labels(selected),
  );

  /// Applies the [selected] changes. Sections named by the list that the
  /// event does not have start as Swiss sections: of the announced number
  /// of rounds when the event page states one, otherwise with their rounds
  /// still to be set. An event with no players and no sections yet also
  /// takes the announced time control and play-up rule.
  Event apply(Event event, Set<String> selected, {String Function()? newId}) {
    final fresh = event.players.isEmpty && event.sections.isEmpty;
    final placed = _apply(event, selected);
    final rounds = announcement?.rounds ?? 0;
    final sectioned = applySectionPlan(
      placed,
      planSections(placed, _labels(selected)),
      rounds: rounds > 0 ? rounds : null,
      newId: newId ?? const Uuid().v4,
    );
    final announced = announcement;
    if (!fresh || announced == null) return sectioned;
    return sectioned.copy(
      timeControl: announced.timeControl.isEmpty ? null : announced.timeControl,
      playUpLimit: announced.playUpLimit > 0 ? announced.playUpLimit : null,
    );
  }

  Event _apply(Event event, Set<String> selected) {
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
        final registration = {
          'source': url,
          'kind': 'self-reported registration',
          'retrievedAt': fetchedAt,
          'registrationRating': incoming.rating,
        };
        result[result.indexWhere((p) => p.id == old.id)] = old.copy(
          name: incoming.name,
          registrationNote: incoming.registrationNote,
          rating: usesSupplement(old) ? old.rating : incoming.rating,
          // Either way the rating not in use stays on file: the website's
          // number beside a supplement, the supplement beside the website's.
          ratingEvidence: usesSupplement(old)
              ? {
                  ...old.ratingEvidence,
                  'registrationRating': incoming.rating,
                  'entered': {
                    'rating': incoming.rating,
                    'evidence': registration,
                  },
                }
              : {
                  ...registration,
                  'supplement': ?old.ratingEvidence['supplement'],
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
              .where((r) => isMemberId(r.incoming.memberId))
              .map((r) => r.incoming.memberId),
        }.toList(),
        'entries': {
          for (final change in changes)
            if (isMemberId(change.incoming.memberId))
              change.incoming.memberId: {
                'name': change.incoming.name,
                'rating': change.incoming.rating,
                'registrationNote': change.incoming.registrationNote,
              },
        },
        'rows': rows
            .map((r) => {'line': r.line, 'raw': r.raw, 'error': r.error})
            .toList(),
        if (announcement != null)
          'announced': announcement!.toJson()
        else if (event.rosterSource['url'] == url &&
            event.rosterSource['announced'] != null)
          'announced': event.rosterSource['announced'],
      },
    );
  }
}
