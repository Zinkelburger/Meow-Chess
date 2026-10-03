import 'package:csv/csv.dart';
import 'package:html/parser.dart' as html;

import '../../domain/model.dart';
import '../roster_import.dart';
import 'source.dart';

/// Uses only the supplied page; does not discover links or run JavaScript.
class HtmlTableRosterSource implements ClubRosterSource {
  const HtmlTableRosterSource();

  @override
  String get name => 'Generic HTML table';
  @override
  bool matches(Uri url) => true;
  @override
  Uri entryListUrl(Uri url) => url;
  @override
  List<ImportRow> parse(String source) => parseWebRoster(source);
}

/// Finds a table by column names, independent of column order and page styling.
List<ImportRow> parseWebRoster(String source) {
  final document = html.parse(source);
  final candidates = <RosterTable>[];
  for (final table in document.querySelectorAll('table')) {
    final rows = table
        .querySelectorAll('tr')
        .where((row) {
          var parent = row.parent;
          while (parent != null && parent.localName != 'table') {
            parent = parent.parent;
          }
          return parent == table;
        })
        .map(
          (row) => row.children
              .where((cell) => cell.localName == 'th' || cell.localName == 'td')
              .map((cell) => cell.text.replaceAll(RegExp(r'\s+'), ' ').trim())
              .toList(),
        )
        .where((row) => row.isNotEmpty)
        .toList();
    // A caption or section heading may precede the actual column headings.
    for (var i = 0; i < rows.length; i++) {
      final header = RosterTable(Csv().encode([rows[i]])).headerColumns;
      if ([RosterField.name, RosterField.rating].every(header.containsKey)) {
        candidates.add(RosterTable(Csv().encode(rows.skip(i).toList())));
        break;
      }
    }
  }
  if (candidates.length != 1) {
    throw const TournamentException(
      'Expected one player table with Name and Rating columns (USCF ID is optional). '
      'For other club websites, paste the page containing the table. '
      'Use a CSV for multiple player tables or tables loaded by JavaScript.',
    );
  }
  final table = candidates.single;
  final rows = table.interpret(hasHeader: true, columns: table.headerColumns);
  if (rows.isEmpty) {
    throw const TournamentException(
      'The player table is empty. Nothing was changed; try again later.',
    );
  }
  return rows;
}
