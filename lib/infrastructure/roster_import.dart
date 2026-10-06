import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';
import '../domain/model.dart';

class ImportRow {
  const ImportRow(this.line, this.raw, this.player, this.error);
  final int line;
  final String raw;
  final Player? player;
  final String? error;
}

enum RosterField {
  name,
  firstName,
  lastName,
  rating,
  memberId,
  club,
  team,
  state,
  registrationNote,
}

/// Decoded cells are kept as strings so IDs retain their leading zeroes.
class RosterTable {
  RosterTable(String source, {String? delimiter})
    : rows = Csv(
        dynamicTyping: false,
        skipEmptyLines: false,
        autoDetect: delimiter == null,
        fieldDelimiter: delimiter ?? ',',
      ).decode(source.replaceFirst(RegExp(r'^\uFEFF'), ''));

  /// Splits [source] the way a spreadsheet's text import does: any of
  /// [separators] ends a cell, [quote] (null for none) wraps cells that
  /// contain separators or line breaks, and [merge] treats a run of
  /// separators as one.
  RosterTable.split(
    String source, {
    required Set<String> separators,
    String? quote = '"',
    bool merge = false,
  }) : rows = splitDelimited(
         source.replaceFirst(RegExp(r'^\uFEFF'), ''),
         separators: separators,
         quote: quote,
         merge: merge,
       );

  final List<List<dynamic>> rows;

  int get columnCount =>
      rows.fold(0, (n, row) => row.length > n ? row.length : n);

  static const aliases = {
    RosterField.name: ['name', 'player', 'playername', 'fullname'],
    RosterField.firstName: ['first', 'firstname', 'givenname'],
    RosterField.lastName: ['last', 'lastname', 'surname', 'familyname'],
    RosterField.memberId: ['id', 'uscf', 'uscfid', 'uschessid', 'memberid'],
    RosterField.rating: ['rating', 'rtg', 'uscfrating', 'pairingrating'],
    RosterField.club: ['club'],
    RosterField.team: ['team', 'teamname', 'mixeddoubles'],
    RosterField.state: ['state', 'st'],
    // Boylston labels its free-form registration note column "Byes".
    // Keep it as text; it must never automatically assign requested byes.
    RosterField.registrationNote: [
      'note',
      'notes',
      'registrationnote',
      'registrationnotes',
      'byes',
    ],
  };

  Map<RosterField, int> get headerColumns {
    if (rows.isEmpty) return {};
    final header = rows.first
        .map(
          (v) => v.toString().trim().toLowerCase().replaceAll(
            RegExp(r'[^a-z0-9]'),
            '',
          ),
        )
        .toList();
    return {
      for (final field in RosterField.values)
        if (header.indexWhere(aliases[field]!.contains) case final index
            when index >= 0)
          field: index,
    };
  }

  bool get suggestsHeader => headerColumns.isNotEmpty;

  Map<RosterField, int> suggestColumns(bool hasHeader) => hasHeader
      ? headerColumns
      : {
          if (columnCount > 0) RosterField.name: 0,
          if (columnCount > 1) RosterField.memberId: 1,
          if (columnCount > 2) RosterField.rating: 2,
        };

  List<ImportRow> interpret({
    required bool hasHeader,
    required Map<RosterField, int> columns,
  }) {
    final result = <ImportRow>[];
    for (final (offset, row) in rows.skip(hasHeader ? 1 : 0).indexed) {
      if (row.every((v) => v.toString().trim().isEmpty)) continue;
      String value(RosterField field) {
        final index = columns[field] ?? -1;
        return index >= 0 && index < row.length
            ? row[index].toString().trim()
            : '';
      }

      final name = columns.containsKey(RosterField.name)
          ? value(RosterField.name)
          : '${value(RosterField.firstName)} ${value(RosterField.lastName)}'
                .trim();
      final member = value(RosterField.memberId);
      final rawRating = value(RosterField.rating);
      final rating =
          rawRating.isEmpty ||
              ['unrated', 'unr'].contains(rawRating.toLowerCase())
          ? 0
          : int.tryParse(rawRating);
      final state = value(RosterField.state).toUpperCase();
      final error = name.isEmpty
          ? 'Missing name'
          : member.isNotEmpty && !RegExp(r'^\d{8}$').hasMatch(member)
          ? 'US Chess ID must be eight digits'
          : rating == null || rating < 0 || rating > 4000
          ? 'Rating must be 0–4000; assign provisional values explicitly'
          : state.isNotEmpty && !RegExp(r'^[A-Z]{2}$').hasMatch(state)
          ? 'State must be two letters'
          : null;
      final raw = Csv().encode([row]);
      result.add(
        ImportRow(
          offset + (hasHeader ? 2 : 1),
          raw,
          error != null
              ? null
              : Player(
                  id: const Uuid().v4(),
                  name: name,
                  memberId: member,
                  rating: rating!,
                  club: value(RosterField.club),
                  team: value(RosterField.team),
                  state: state,
                  registrationNote: value(RosterField.registrationNote),
                  source: raw,
                ),
          error,
        ),
      );
    }
    return result;
  }
}

List<ImportRow> parseRoster(
  String source, {
  String? delimiter,
  bool? hasHeader,
  Map<RosterField, int>? columns,
}) {
  final table = RosterTable(source, delimiter: delimiter);
  final header = hasHeader ?? table.suggestsHeader;
  return table.interpret(
    hasHeader: header,
    columns: columns ?? table.suggestColumns(header),
  );
}

/// Cells of delimited text. See [RosterTable.split].
List<List<String>> splitDelimited(
  String source, {
  required Set<String> separators,
  String? quote = '"',
  bool merge = false,
}) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false, cellStarted = false;
  void endCell() {
    row.add(cell.toString());
    cell.clear();
    cellStarted = false;
  }

  void endRow() {
    endCell();
    rows.add(row);
    row = <String>[];
  }

  final chars = source.split('');
  for (var i = 0; i < chars.length; i++) {
    final ch = chars[i];
    if (quoted) {
      if (ch == quote) {
        if (i + 1 < chars.length && chars[i + 1] == quote) {
          cell.write(ch);
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (quote != null && ch == quote && !cellStarted) {
      // `a, "b, c"`: spaces before an opening quote are padding.
      cell.clear();
      quoted = cellStarted = true;
    } else if (separators.contains(ch)) {
      endCell();
      if (merge) {
        while (i + 1 < chars.length && separators.contains(chars[i + 1])) {
          i++;
        }
      }
    } else if (ch == '\r' || ch == '\n') {
      if (ch == '\r' && i + 1 < chars.length && chars[i + 1] == '\n') i++;
      endRow();
    } else {
      cell.write(ch);
      if (ch != ' ' && ch != '\t') cellStarted = true;
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// The separator a text file most likely uses: the candidate that appears
/// the same number of times on the most lines. Null for a single column.
String? detectSeparator(String source, {String? quote = '"'}) {
  const candidates = ['\t', ',', ';', '|'];
  final lines = source
      .split(RegExp(r'\r\n|\r|\n'))
      .where((l) => l.trim().isNotEmpty)
      .take(20)
      .toList();
  String? best;
  var bestScore = 0;
  for (final candidate in candidates) {
    final counts = <int>[];
    for (final line in lines) {
      var n = 0, inQuotes = false;
      for (final ch in line.split('')) {
        if (ch == quote) {
          inQuotes = !inQuotes;
        } else if (ch == candidate && !inQuotes) {
          n++;
        }
      }
      counts.add(n);
    }
    final tally = <int, int>{};
    for (final n in counts.where((n) => n > 0)) {
      tally[n] = (tally[n] ?? 0) + 1;
    }
    if (tally.isEmpty) continue;
    // Lines that agree on the count, weighted slightly by how many cells.
    final agree = tally.values.reduce((a, b) => a > b ? a : b);
    final score = agree * 100 + counts.fold(0, (a, b) => a + b).clamp(0, 99);
    if (score > bestScore) {
      best = candidate;
      bestScore = score;
    }
  }
  return best;
}
