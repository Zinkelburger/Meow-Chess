import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../domain/posted_results.dart';
import 'source.dart';

/// The Boylston Chess Foundation's live pairings, where players enter their
/// own results: `/results` (also reached as `/result`), and the `/monitor`
/// screen that shows the same boards. The site lists whatever is being
/// played at the club now, so the address names no event.
///
/// It lists the current round only. Once the club posts the next round the
/// earlier one is gone from the page, so results cannot be backfilled or
/// re-checked for a past round from here.
///
/// Each section is a heading, `Open - Round 1`, over a table whose rows
/// carry `board-number`, `white-result`, `white-name`, `black-result` and
/// `black-name` cells. A name is followed by the rating and score in
/// brackets. A bye is a row whose opponent is "bye".
class BoylstonResultsSource implements ClubResultsSource {
  const BoylstonResultsSource();

  /// The live pages are on the club's beta site only, for now.
  static const _hosts = {
    'beta.boylstonchess.org',
    'boylstonchess.org',
    'www.boylstonchess.org',
  };
  static final _page = RegExp(r'^/(?:results?|monitor)/?$');
  static final _heading = RegExp(r'^(.*\S)\s*-\s*Round\s+(\d+)$');

  @override
  String get name => 'Boylston Chess Foundation';

  @override
  bool matches(Uri url) =>
      _hosts.contains(url.host) && _page.hasMatch(url.path);

  @override
  Uri resultsUrl(Uri url) => Uri.https(url.host, '/results');

  @override
  Uri? resultsUrlForRoster(Uri rosterUrl) => _hosts.contains(rosterUrl.host)
      ? Uri.https('beta.boylstonchess.org', '/results')
      : null;

  @override
  List<PostedRound> parse(String source) => parseBoylstonResults(source);
}

String _text(dom.Element? cell) =>
    (cell?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// The rounds a Boylston results or monitor page lists. Byes are left out:
/// they are not games.
///
/// Before the club posts a round, and between rounds, the page is the
/// club's own page with no pairings table: that is no rounds yet, not a
/// broken page. Anything else without a table (a sign-in form, another
/// site's page) is a [FormatException].
List<PostedRound> parseBoylstonResults(String source) {
  final document = html.parse(source);
  if (document.querySelector('table.pairings') == null) {
    final clubPage =
        _text(
          document.querySelector('title'),
        ).contains('Boylston Chess Foundation') &&
        (document.querySelector('#main') != null ||
            document.querySelector('#pairings-column') != null) &&
        document.querySelector('input[type=password]') == null;
    if (clubPage) return const [];
    throw const FormatException('No pairings table on this page.');
  }
  final rounds = <PostedRound>[];
  String? section;
  var number = 0;
  var games = <PostedGame>[];
  void close() {
    if (section != null) {
      rounds.add(PostedRound(section: section!, round: number, games: games));
    }
    section = null;
    games = [];
  }

  // Headings and rows in page order: a heading opens a round, and the rows
  // up to the next heading are its boards.
  for (final node in document.querySelectorAll('h2, tr')) {
    final isRow = node.localName == 'tr';
    final white = isRow ? node.querySelector('.white-name') : null;
    if (white == null) {
      // The monitor page puts the heading in a row of its own.
      final title = isRow
          ? (node.classes.contains('no-border') ? _text(node) : '')
          : _text(node);
      final match = BoylstonResultsSource._heading.firstMatch(title);
      if (match != null) {
        close();
        section = match[1]!;
        number = int.parse(match[2]!);
      } else if (!isRow) {
        // Another heading ends the round above it.
        close();
      }
      continue;
    }
    if (section == null) continue;
    String player(dom.Element? cell) =>
        _text(cell).replaceFirst(RegExp(r'\s*\([^()]*\)$'), '');
    final blackCell = node.querySelector('.black-name');
    final black = player(blackCell);
    if (black.isEmpty || black.toLowerCase() == 'bye') continue;
    games.add(
      PostedGame(
        board: int.tryParse(_text(node.querySelector('.board-number'))),
        white: player(white),
        black: black,
        whiteResult: _text(node.querySelector('.white-result')),
        blackResult: _text(node.querySelector('.black-result')),
      ),
    );
  }
  close();
  return rounds;
}
