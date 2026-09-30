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

List<ImportRow> parseRoster(String source) {
  final text = source.replaceFirst('\uFEFF', '');
  final rows = Csv(dynamicTyping: false).decode(text);
  if (rows.isEmpty) return [];
  final header = rows.first
      .map(
        (v) => v.toString().trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        ),
      )
      .toList();
  int column(List<String> names) => header.indexWhere(names.contains);
  var nameIndex = column(['name', 'player', 'playername', 'fullname']);
  final first = column(['first', 'firstname']),
      last = column(['last', 'lastname']);
  final hasHeader = nameIndex >= 0 || first >= 0 || last >= 0;
  if (!hasHeader) nameIndex = 0;
  final idIndex = column(['id', 'uscf', 'uscfid', 'uschessid', 'memberid']);
  final ratingIndex = column(['rating', 'rtg', 'uscf rating', 'pairingrating']);
  final clubIndex = column(['club', 'team']);
  final stateIndex = hasHeader ? column(['state', 'st']) : -1;
  final result = <ImportRow>[];
  for (final (offset, row) in rows.skip(hasHeader ? 1 : 0).indexed) {
    if (row.every((v) => v.toString().trim().isEmpty)) continue;
    String value(int index) =>
        index >= 0 && index < row.length ? row[index].toString().trim() : '';
    final name = nameIndex >= 0
        ? value(nameIndex)
        : '${value(first)} ${value(last)}'.trim();
    final member = value(
      hasHeader
          ? idIndex
          : row.length > 1
          ? 1
          : -1,
    );
    final rawRating = value(
      hasHeader
          ? ratingIndex
          : row.length > 2
          ? 2
          : -1,
    );
    final rating =
        rawRating.isEmpty ||
            rawRating.toLowerCase() == 'unrated' ||
            rawRating.toLowerCase() == 'unr'
        ? 0
        : int.tryParse(rawRating);
    final state = value(stateIndex).toUpperCase();
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
                club: value(clubIndex),
                state: state,
                source: raw,
              ),
        error,
      ),
    );
  }
  return result;
}
