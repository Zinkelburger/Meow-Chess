# Add your club’s website

**Refresh from URL** selects a club adapter by URL. If none matches, it reads
the exact supplied page and looks for one HTML table with Name, Rating and
USCF ID columns. Column order does not matter; aliases such as Player Name,
RTG and US Chess ID also work. The generic importer does not follow entry-list
links or invent URL paths. Paste the page containing the actual table.

Boylston’s adapter accepts both:

- `https://boylstonchess.org/events/1563/october-quads`
- `https://boylstonchess.org/tournament/entries/1563`

Both fetch `https://boylstonchess.org/tournament/entries/1563`. Event IDs and
slugs can vary; `www`, trailing slashes and event URLs without a slug also work.
The URL entered by the director is saved after confirmation and resolved again
on later refreshes.

## Contributing an adapter

1. Add a file under `lib/infrastructure/roster_sources/`, using `boylston.dart`
   as a small example. Extend `HtmlTableRosterSource` if the club uses standard
   columns, or implement `ClubRosterSource` for a custom format.
2. Implement `matches` with exact host names and the supported path shapes.
   Do not match arbitrary hosts that merely contain your club’s domain.
3. Implement `entryListUrl` to convert a supported event URL to its roster URL.
   Return the input unchanged for direct roster URLs when appropriate. All
   input and resolved URLs must be HTTPS without credentials or fragments.
4. For custom layouts, override `parse` to return `List<ImportRow>`. You can
   select a known table from the HTML and pass its `outerHtml` to
   `parseWebRoster`, or translate club-specific columns and call `parseRoster`.
   Keep IDs as strings to preserve leading zeroes, retain raw source rows, and
   report invalid rows instead of silently inventing names, IDs or ratings.
5. Import and add the adapter to `clubRosterSources` in `registry.dart`.
   The first matching adapter wins; the generic fallback is automatic.
6. Add tests using synthetic HTML and `MockClient`: both URL forms, another
   tournament ID, unrecognized hosts/paths, custom columns, empty tables and
   invalid IDs/ratings. Run `flutter test test/infrastructure/web_roster_test.dart`
   along with your new tests.

For example, a club with `/events/<id>` and `/entries/<id>` could use:

```dart
import 'html_table.dart';

class ExampleClubSource extends HtmlTableRosterSource {
  const ExampleClubSource();

  static final path = RegExp(r'^/(?:events|entries)/(\d+)/?$');

  @override
  String get name => 'Example Chess Club';

  @override
  bool matches(Uri url) =>
      url.host == 'chess.example.org' && path.hasMatch(url.path);

  @override
  Uri entryListUrl(Uri url) => Uri.https(
    'chess.example.org',
    '/entries/${path.firstMatch(url.path)![1]}',
  );
}
```

Adapters are contributed Dart code shipped with the app. They do not execute
website scripts or download parser code. `WebRoster` handles the shared HTTP
client, timeouts, response size limit and redirect policy. Tests can inject
adapters through `WebRoster(client, sources: [ExampleClubSource()])`;
`sources: []` selects generic parsing for every URL.

## Parsing and review

The generic parser searches each table for a header row, allowing a title row
before it. Unrelated tables are ignored. Multiple matching player tables are
ambiguous and require CSV import or a club adapter that selects the correct
one. Empty tables and JavaScript-only pages cannot become roster updates.

Blank/UNR/Unrated ratings become zero. Missing IDs remain blank; malformed IDs
and ratings produce row errors using the existing roster validation. Note, Notes,
and Boylston’s free-form Byes column populate the Players tab’s Note column.
These registration notes are separate from private player notes and never assign
byes automatically. Note changes appear in the refresh review, including cleared
notes; posted sections can update notes while keeping their names and ratings.
Section columns remain in the raw rows for manual review.

Fetching only creates a proposal. The director still reviews and confirms it;
existing identity checks, rating protections and Undo apply to every adapter.
See [website roster behavior](ROSTER_AND_HELP.md) for the full review workflow.
