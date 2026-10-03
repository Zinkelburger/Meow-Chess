import '../roster_import.dart';

/// Club adapters own URL conventions and page formats, never network requests.
/// Register new adapters in registry.dart; see docs/CLUB_ROSTER_ADAPTERS.md.
abstract interface class ClubRosterSource {
  String get name;
  bool matches(Uri url);
  Uri entryListUrl(Uri url);
  List<ImportRow> parse(String source);
}
