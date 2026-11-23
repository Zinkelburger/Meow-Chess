import 'dart:typed_data';

/// A minimal independent reader for the .xls workbooks the SwissSys export
/// writes: sheet names in order, each with its cells by (row, column). Text
/// comes back as a [String], numbers as a [double] and true/false as a
/// [bool]; a cell that is not in the file is absent from the map.
Map<String, Map<(int, int), Object>> readXls(Uint8List file) {
  final view = ByteData.sublistView(file);
  int u16(int at) => view.getUint16(at, Endian.little);
  int u32(int at) => view.getUint32(at, Endian.little);
  if (u32(0) != 0xe011cfd0 || u32(4) != 0xe11ab1a1) {
    throw const FormatException('Not an OLE2 compound file.');
  }
  const sector = 512, end = 0xfffffffe;
  int at(int index) => (index + 1) * sector;
  // Follow the allocation table from the header's list of table sectors.
  final table = <int>[
    for (var i = 0; i < u32(0x2c); i++)
      for (var j = 0; j < sector ~/ 4; j++) u32(at(u32(0x4c + i * 4)) + j * 4),
  ];
  // The directory's second entry is the Workbook stream.
  final entry = at(u32(0x30)) + 128;
  final name = String.fromCharCodes([
    for (var i = 0; i < u16(entry + 0x40) - 2; i += 2) u16(entry + i),
  ]);
  if (name != 'Workbook') throw FormatException('Found stream "$name".');
  final length = u32(entry + 0x78);
  final stream = BytesBuilder();
  for (var s = u32(entry + 0x74); s != end; s = table[s]) {
    stream.add(file.sublist(at(s), at(s) + sector));
  }
  final bytes = stream.takeBytes().sublist(0, length);
  final data = ByteData.sublistView(bytes);

  final records = <(int, Uint8List)>[];
  for (var i = 0; i + 4 <= bytes.length;) {
    final id = data.getUint16(i, Endian.little),
        size = data.getUint16(i + 2, Endian.little);
    records.add((id, bytes.sublist(i + 4, i + 4 + size)));
    i += 4 + size;
  }
  final strings = <String>[], names = <String>[];
  final sheets = <Map<(int, int), Object>>[];
  for (var k = 0; k < records.length; k++) {
    final (id, body) = records[k];
    final b = ByteData.sublistView(body);
    switch (id) {
      case 0x00fc: // Shared strings, continued in 0x003c records.
        final parts = [body];
        while (k + 1 < records.length && records[k + 1].$1 == 0x003c) {
          parts.add(records[++k].$2);
        }
        final count = b.getUint32(4, Endian.little);
        var part = 0, p = 8;
        while (strings.length < count) {
          if (p >= parts[part].length) {
            part++;
            p = 0;
          }
          final chunk = parts[part];
          final size = chunk[p] | chunk[p + 1] << 8, wide = chunk[p + 2] == 1;
          p += 3;
          strings.add(
            String.fromCharCodes([
              for (var i = 0; i < size; i++)
                wide
                    ? chunk[p + i * 2] | chunk[p + i * 2 + 1] << 8
                    : chunk[p + i],
            ]),
          );
          p += wide ? size * 2 : size;
        }
      case 0x0085:
        names.add(
          String.fromCharCodes([
            for (var i = 0; i < body[6]; i++)
              b.getUint16(8 + i * 2, Endian.little),
          ]),
        );
      case 0x0809 when b.getUint16(2, Endian.little) == 0x10:
        sheets.add({});
      case 0x00fd:
        sheets.last[(
              b.getUint16(0, Endian.little),
              b.getUint16(2, Endian.little),
            )] =
            strings[b.getUint32(6, Endian.little)];
      case 0x0203:
        sheets.last[(
          b.getUint16(0, Endian.little),
          b.getUint16(2, Endian.little),
        )] = b.getFloat64(
          6,
          Endian.little,
        );
      case 0x0205:
        sheets.last[(
              b.getUint16(0, Endian.little),
              b.getUint16(2, Endian.little),
            )] =
            body[6] == 1;
    }
  }
  return {for (final (i, name) in names.indexed) name: sheets[i]};
}

/// A sheet as rows of cells, null where the file has no cell.
List<List<Object?>> xlsRows(Map<(int, int), Object> cells) {
  var rows = 0, columns = 0;
  for (final (r, c) in cells.keys) {
    if (r >= rows) rows = r + 1;
    if (c >= columns) columns = c + 1;
  }
  return [
    for (var r = 0; r < rows; r++)
      [for (var c = 0; c < columns; c++) cells[(r, c)]],
  ];
}
