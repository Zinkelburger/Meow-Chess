import 'dart:convert';
import 'dart:typed_data';

/// A minimal independent reader: field layout and trimmed values per record.
(List<(String, String, int)>, List<Map<String, String>>) readDbf(
  Uint8List bytes,
) {
  final view = ByteData.sublistView(bytes);
  final count = view.getUint32(4, Endian.little),
      header = view.getUint16(8, Endian.little),
      size = view.getUint16(10, Endian.little);
  final fields = <(String, String, int)>[];
  for (var at = 32; bytes[at] != 13; at += 32) {
    final name = ascii.decode(
      bytes.sublist(at, at + 11).takeWhile((b) => b != 0).toList(),
    );
    fields.add((name, String.fromCharCode(bytes[at + 11]), bytes[at + 16]));
  }
  final rows = <Map<String, String>>[];
  for (var r = 0; r < count; r++) {
    var at = header + r * size + 1;
    final row = <String, String>{};
    for (final (name, _, width) in fields) {
      row[name] = ascii.decode(bytes.sublist(at, at + width)).trimRight();
      at += width;
    }
    rows.add(row);
  }
  return (fields, rows);
}
