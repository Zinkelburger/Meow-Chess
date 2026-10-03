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
}
