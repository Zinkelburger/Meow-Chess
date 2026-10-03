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

  final List<List<dynamic>> rows;

  int get columnCount =>
      rows.fold(0, (n, row) => row.length > n ? row.length : n);

  static const aliases = {
    RosterField.name: ['name', 'player', 'playername', 'fullname'],
    RosterField.firstName: ['first', 'firstname', 'givenname'],
    RosterField.lastName: ['last', 'lastname', 'surname', 'familyname'],
    RosterField.memberId: ['id', 'uscf', 'uscfid', 'uschessid', 'memberid'],
    RosterField.rating: ['rating', 'rtg', 'uscfrating', 'pairingrating'],
    RosterField.club: ['club', 'team'],
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
