import '../../domain/announcement.dart';
import '../roster_import.dart';

/// Club adapters own URL conventions and page formats, never network requests.
/// Register new adapters in registry.dart; see docs/CLUB_ROSTER_ADAPTERS.md.
abstract interface class ClubRosterSource {
  String get name;
  bool matches(Uri url);
  Uri entryListUrl(Uri url);
  List<ImportRow> parse(String source);

  /// The page that announces the event of [url] (format, rounds, time
  /// control), or null when the club has none this adapter can read.
  Uri? eventPageUrl(Uri url);

  /// Whether [url] is one of this club's event pages. A redirect from
  /// [eventPageUrl] is only followed to such a page.
  bool isEventPage(Uri url);

  /// What the event page's text announces, or null when nothing was found.
  Announcement? parseEvent(String source);
}
