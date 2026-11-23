import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../domain/announcement.dart';
import '../../domain/model.dart';
import 'html_table.dart';

/// Boylston event pages and entry lists share a numeric tournament ID.
class BoylstonRosterSource extends HtmlTableRosterSource {
  const BoylstonRosterSource();

  static final _event = RegExp(r'^/events/(\d+)(?:/[^/]+)?/?$');
  static final _entries = RegExp(r'^/tournament/entries/(\d+)/?$');

  @override
  String get name => 'Boylston Chess Foundation';

  @override
  bool matches(Uri url) =>
      (url.host == 'boylstonchess.org' ||
          url.host == 'www.boylstonchess.org') &&
      (_event.hasMatch(url.path) || _entries.hasMatch(url.path));

  @override
  Uri entryListUrl(Uri url) {
    final match = _event.firstMatch(url.path) ?? _entries.firstMatch(url.path);
    return Uri.https('boylstonchess.org', '/tournament/entries/${match![1]}');
  }

  /// The event page as pasted, or the short `/events/<id>` form for an
  /// entry-list URL, which the site redirects to the full address.
  @override
  Uri? eventPageUrl(Uri url) {
    if (_event.hasMatch(url.path)) {
      return Uri.https('boylstonchess.org', url.path);
    }
    final match = _entries.firstMatch(url.path);
    return match == null
        ? null
        : Uri.https('boylstonchess.org', '/events/${match[1]}');
  }

  @override
  bool isEventPage(Uri url) =>
      (url.host == 'boylstonchess.org' ||
          url.host == 'www.boylstonchess.org') &&
      _event.hasMatch(url.path);

  @override
  Announcement? parseEvent(String source) => parseBoylstonEvent(source);
}

const _numberWords = {
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
};

/// Reads the labelled facts of a Boylston event page: "Event Format"
/// ("4SS", "3RR"), "Time Control", and in the description the club's
/// play-up and section-merge rules. Null when the page states none.
Announcement? parseBoylstonEvent(String source) {
  final document = html.parse(source);
  final facts = <String, String>{};
  String? label;
  for (final node
      in document.querySelector('dl.event-info')?.children ??
          const <dom.Element>[]) {
    final text = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (node.localName == 'dt') {
      label = text.toLowerCase();
    } else if (node.localName == 'dd' && label != null && label.isNotEmpty) {
      facts.putIfAbsent(label, () => text);
    }
  }
  final format = RegExp(
    r'^(\d{1,2})\s*-?\s*(SS|RR)\b',
    caseSensitive: false,
  ).firstMatch(facts['event format'] ?? '');
  final rounds = format == null ? 0 : int.parse(format[1]!);
  final description = facts['description'] ?? '';
  final playUp = RegExp(
    r'within (\d{2,3}) points of the lower section',
    caseSensitive: false,
  ).firstMatch(description);
  final merge = RegExp(
    r'fewer than (\w+) players may be merged',
    caseSensitive: false,
  ).firstMatch(description);
  final mergeWord = merge?[1]?.toLowerCase() ?? '';
  final announcement = Announcement(
    rounds: rounds >= 1 && rounds <= 32 ? rounds : 0,
    format: switch (format?[2]?.toUpperCase()) {
      'SS' => Format.swiss,
      'RR' => Format.roundRobin,
      _ => null,
    },
    timeControl: facts['time control'] ?? '',
    playUpLimit: playUp == null ? 0 : int.parse(playUp[1]!),
    mergeBelow: _numberWords[mergeWord] ?? int.tryParse(mergeWord) ?? 0,
  );
  return announcement.isEmpty ? null : announcement;
}
