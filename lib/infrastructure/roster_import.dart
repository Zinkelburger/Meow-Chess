import 'dart:convert';

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
  factory RosterTable(String source, {String? delimiter}) {
    source = source.replaceFirst(RegExp(r'^\uFEFF'), '');
    // A one-column "Last, First" list is not comma-separated; split on a
    // character the text does not contain.
    final separator =
        delimiter ?? (_looksLikeLastFirst(source, '"') ? '\t' : null);
    final rows = Csv(
      dynamicTyping: false,
      skipEmptyLines: false,
      autoDetect: separator == null,
      fieldDelimiter: separator ?? ',',
    ).decode(source);
    // The CSV decoder does not report where each record starts; count the
    // same records here and fall back to record numbers if they disagree.
    final split = _splitDelimited(
      source,
      separators: {separator ?? detectSeparator(source) ?? ','},
      quote: '"',
      merge: false,
    );
    return RosterTable._(
      rows,
      split.rows.length == rows.length
          ? split.lines
          : [for (var i = 1; i <= rows.length; i++) i],
    );
  }

  RosterTable._(this.rows, this.lines);

  /// Splits [source] the way a spreadsheet's text import does: any of
  /// [separators] ends a cell, [quote] (null for none) wraps cells that
  /// contain separators or line breaks, and [merge] treats a run of
  /// separators as one.
  factory RosterTable.split(
    String source, {
    required Set<String> separators,
    String? quote = '"',
    bool merge = false,
  }) {
    final split = _splitDelimited(
      source,
      separators: separators,
      quote: quote,
      merge: merge,
    );
    return RosterTable._(split.rows, split.lines);
  }

  final List<List<dynamic>> rows;

  /// The file line on which each of [rows] starts. A quoted cell may span
  /// lines, so this is not always the record number.
  final List<int> lines;

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
    for (var index = hasHeader ? 1 : 0; index < rows.length; index++) {
      final row = rows[index];
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
          lines[index],
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
}) => _splitDelimited(
  source,
  separators: separators,
  quote: quote,
  merge: merge,
).rows;

/// Cells of delimited text and the file line each row starts on.
({List<List<String>> rows, List<int> lines}) _splitDelimited(
  String source, {
  required Set<String> separators,
  required String? quote,
  required bool merge,
}) {
  final rows = <List<String>>[];
  final lines = <int>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false, cellStarted = false;
  var line = 1, rowStart = 1;
  void endCell() {
    row.add(cell.toString());
    cell.clear();
    cellStarted = false;
  }

  void endRow() {
    endCell();
    rows.add(row);
    lines.add(rowStart);
    row = <String>[];
  }

  final chars = source.split('');
  for (var i = 0; i < chars.length; i++) {
    final ch = chars[i];
    // A byte-order mark is invisible: one may remain from a file pasted or
    // concatenated after another.
    if (ch == '\uFEFF') continue;
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
        if (ch == '\n' ||
            (ch == '\r' && chars.elementAtOrNull(i + 1) != '\n')) {
          line++;
        }
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
      rowStart = ++line;
    } else {
      cell.write(ch);
      if (ch != ' ' && ch != '\t') cellStarted = true;
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return (rows: rows, lines: lines);
}

/// The separator a text file most likely uses: the candidate that appears
/// the same number of times on the most lines. Null for a single column.
/// A one-column "Last, First" list is not comma-separated.
String? detectSeparator(String source, {String? quote = '"'}) {
  const candidates = ['\t', ',', ';', '|'];
  final lines = _sampleLines(source);
  if (_looksLikeLastFirst(source, quote)) return null;
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

List<String> _sampleLines(String source) => source
    .replaceAll('\uFEFF', '')
    .split(RegExp(r'\r\n|\r|\n'))
    .where((l) => l.trim().isNotEmpty)
    .take(20)
    .toList();

/// Every line is `Last, First`: one comma followed by a space, with given
/// names after it. Spreadsheets do not pad the commas they write, and a second
/// column of IDs, ratings or state codes does not look like a given name.
bool _looksLikeLastFirst(String source, String? quote) {
  bool heading(String cell) => RosterTable.aliases.values.any(
    (names) => names.contains(
      cell.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''),
    ),
  );
  var lines = _sampleLines(source);
  // A single "Name" heading may sit above the list.
  if (lines.isNotEmpty && heading(lines.first)) lines = lines.sublist(1);
  if (lines.isEmpty) return false;
  final given = RegExp(r"^\p{Lu}[\p{L}\p{M}.'’\- ]*$", unicode: true);
  for (final line in lines) {
    if (line.contains(RegExp(r'[\t;|]')) ||
        (quote != null && line.contains(quote))) {
      return false;
    }
    final parts = line.split(',');
    if (parts.length != 2 || !parts[1].startsWith(' ')) return false;
    final last = parts[0].trim(), first = parts[1].trim();
    // "Last, First" as column headings names two columns.
    if (last.isEmpty ||
        last.contains(RegExp(r'\d')) ||
        !given.hasMatch(first) ||
        RegExp(r'^[A-Z]{2}$').hasMatch(first) ||
        (heading(last) && heading(first))) {
      return false;
    }
  }
  return true;
}

/// Text of a roster file in the encoding a spreadsheet most likely saved it
/// with. A byte-order mark decides first (Excel's "Unicode Text" is UTF-16
/// with one), then [charset] when the source declares one; otherwise the
/// bytes are read as UTF-8, or as Windows-1252 if they are not valid UTF-8
/// (Excel's "CSV" on Windows).
String decodeRosterText(List<int> bytes, {String? charset}) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return _utf8OrWindows1252(bytes.sublist(3));
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes, 2, littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes, 2, littleEndian: false);
  }
  switch (charset?.trim().toLowerCase().replaceAll(
    RegExp('^["\']|["\']\$'),
    '',
  )) {
    case 'utf-16le' || 'utf-16':
      return _utf16(bytes, 0, littleEndian: true);
    case 'utf-16be':
      return _utf16(bytes, 0, littleEndian: false);
    // Browsers read every Latin-1 label as Windows-1252, its superset.
    case 'windows-1252' ||
        'cp1252' ||
        'x-cp1252' ||
        'iso-8859-1' ||
        'iso8859-1' ||
        'latin1' ||
        'l1' ||
        'us-ascii' ||
        'ascii':
      return _windows1252(bytes);
  }
  return _utf8OrWindows1252(bytes);
}

String _utf8OrWindows1252(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return _windows1252(bytes);
  }
}

String _utf16(List<int> bytes, int start, {required bool littleEndian}) {
  final units = <int>[
    for (var i = start; i + 1 < bytes.length; i += 2)
      littleEndian
          ? bytes[i] | bytes[i + 1] << 8
          : bytes[i] << 8 | bytes[i + 1],
  ];
  // An odd final byte cannot be a character.
  if ((bytes.length - start).isOdd) units.add(0xFFFD);
  return String.fromCharCodes(units);
}

/// Windows-1252 differs from Latin-1 only in 0x80–0x9F; its five unassigned
/// bytes keep their Latin-1 control characters, as browsers decode them.
String _windows1252(List<int> bytes) => String.fromCharCodes([
  for (final b in bytes)
    b >= 0x80 && b <= 0x9F ? _windows1252High[b - 0x80] : b,
]);

const _windows1252High = [
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F, //
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, //
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178, //
];
