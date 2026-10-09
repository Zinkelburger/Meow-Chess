import 'package:csv/csv.dart';
import 'package:html/dom.dart' as dom;
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
              .map(
                (cell) =>
                    _cellText(cell).replaceAll(RegExp(r'\s+'), ' ').trim(),
              )
              .toList(),
        )
        .where((row) => row.isNotEmpty)
        .toList();
    // A caption or section heading may precede the actual column headings.
    for (var i = 0; i < rows.length; i++) {
      final header = RosterTable(
        Csv().encode([rows[i]]),
        delimiter: ',',
      ).headerColumns;
      if ([RosterField.name, RosterField.rating].every(header.containsKey)) {
        candidates.add(
          RosterTable(Csv().encode(rows.skip(i).toList()), delimiter: ','),
        );
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

/// A cell's text with a space where a line break or block ended, so
/// "John<br>Smith" reads "John Smith", as a browser shows it.
String _cellText(dom.Node node) {
  const breaks = {'br', 'p', 'div', 'li', 'tr', 'td', 'th'};
  final text = StringBuffer();
  void visit(dom.Node node) {
    if (node is dom.Text) {
      text.write(node.data);
    } else if (node is dom.Element && breaks.contains(node.localName)) {
      text.write(' ');
      node.nodes.forEach(visit);
      text.write(' ');
    } else {
      node.nodes.forEach(visit);
    }
  }

  node.nodes.forEach(visit);
  return text.toString();
}
