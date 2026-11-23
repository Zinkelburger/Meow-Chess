import '../../domain/posted_results.dart';

/// A club website that shows a round's pairings with the results players
/// enter there. Adapters own URL conventions and the page format, never
/// network requests. Register new ones in registry.dart; see
/// docs/CLUB_ROSTER_ADAPTERS.md.
abstract interface class ClubResultsSource {
  String get name;

  /// Whether [url] is one of this club's pairing or results pages.
  bool matches(Uri url);

  /// The page to read for [url], which [matches].
  Uri resultsUrl(Uri url);

  /// The rounds the page lists. An unreadable page is a [FormatException],
  /// never an empty list: a page with no rounds yet reads as none.
  List<PostedRound> parse(String source);

  /// The results page that goes with an entry list at [rosterUrl], offered
  /// to the director as a starting point; null for another club's list.
  Uri? resultsUrlForRoster(Uri rosterUrl);
}
