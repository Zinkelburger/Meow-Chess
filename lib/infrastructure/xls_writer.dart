import 'dart:typed_data';

/// One sheet of an old-format Excel workbook. A cell is a [String], a [num]
/// (stored as a floating-point number), a [bool], or null for no cell at all.
class XlsSheet {
  const XlsSheet(this.name, this.rows);
  final String name;
  final List<List<Object?>> rows;
}

/// An Excel 97 `.xls` workbook (BIFF8 records in an OLE2 compound file) with
/// plain, unformatted cells. SwissSys 9 keeps its section files in this
/// format, and the record layout here follows the files it writes: the same
/// workbook and sheet settings, shared strings for text, and one default
/// cell style.
Uint8List xlsWorkbook(List<XlsSheet> sheets) {
  final strings = <String, int>{};
  int shared(String text) {
    if (text.length > _longestString) {
      throw ArgumentError('A cell holds more text than an .xls file allows.');
    }
    return strings.putIfAbsent(text, () => strings.length);
  }

  final bodies = [
    for (final (i, sheet) in sheets.indexed)
      _sheet(sheet, shared, first: i == 0),
  ];
  final opening = _Records()
    ..hex(0x0809, '000605004618cd07c140000006010000') // BOF, workbook globals.
    ..hex(0x00e1, 'b004')
    ..hex(0x00c1, '')
    ..hex(0x00e2, '')
    ..hex(0x01c0, '')
    ..hex(0x0161, '0000')
    ..add(0x013d, _words([for (var i = 0; i < sheets.length; i++) i]))
    ..hex(0x003d, '68010f004c2c8b1a38000000000001005802') // Window.
    ..hex(0x008d, '0000')
    ..hex(0x0022, '0000') // Dates count from 1900.
    ..hex(0x0019, '0000')
    ..hex(0x0012, '0000')
    ..hex(0x0031, 'c800000040009001000000000100050141007200690061006c00');
  // The style table SwissSys writes. Every cell uses the last one (21).
  for (var i = 0; i < 15; i++) {
    opening.hex(0x00e0, '00000000f5ff200000000000000000000000c020');
  }
  opening.hex(0x00e0, '000000000100200000000000000000000000c020');
  for (final format in ['2c', '2a', '09', '2b', '29']) {
    opening.hex(0x00e0, '0100${format}00f5ff200000f80000000000000000c020');
  }
  opening.hex(0x00e0, '000000000100200000040000000000000000c020');
  for (final style in [
    '108004ff',
    '118007ff',
    '008000ff',
    '128005ff',
    '138003ff',
    '148006ff',
  ]) {
    opening.hex(0x0293, style);
  }

  final closing = _Records()
    ..add(0x01ae, _words([sheets.length, 0x0401]))
    ..add(
      0x0017,
      _words([
        sheets.length,
        for (var i = 0; i < sheets.length; i++) ...[0, i, i],
      ]),
    )
    ..hex(0x01c1, 'c101000060690100');
  _sharedStrings(closing, strings.keys.toList());
  closing
    ..hex(0x00ff, '0000')
    ..hex(0x000a, '');

  // Each sheet's directory entry holds where its records start, so the
  // entries' own size has to be known before the offsets can be.
  final names = [for (final sheet in sheets) _utf16(sheet.name)];
  var offset =
      opening.length +
      closing.length +
      names.fold<int>(0, (sum, name) => sum + 4 + 8 + name.length);
  final directory = _Records();
  for (final (i, sheet) in sheets.indexed) {
    if (sheet.name.isEmpty || sheet.name.length > 31) {
      throw ArgumentError('A sheet name must have 1 to 31 characters.');
    }
    directory.add(
      0x0085,
      (BytesBuilder()
            ..add(_dword(offset))
            ..add([0, 0, sheet.name.length, 1])
            ..add(names[i]))
          .takeBytes(),
    );
    offset += bodies[i].length;
  }

  final stream = BytesBuilder()
    ..add(opening.bytes())
    ..add(directory.bytes())
    ..add(closing.bytes());
  for (final body in bodies) {
    stream.add(body);
  }
  return _compoundFile(stream.takeBytes());
}

/// The longest text a shared string may hold here: one that always fits in
/// a single record, so strings only ever break between records.
const _longestString = 4000;
const _recordLimit = 8224;
const _sector = 512;

/// Streams shorter than this live in a second, finer-grained allocation
/// table. Padding past it keeps the file to the one simple table.
const _smallStreamLimit = 4096;

Uint8List _sheet(
  XlsSheet sheet,
  int Function(String) shared, {
  required bool first,
}) {
  final rows = sheet.rows;
  final columns = rows.fold<int>(
    0,
    (m, row) => row.length > m ? row.length : m,
  );
  if (rows.length > 65536 || columns > 256) {
    throw ArgumentError('${sheet.name} is too large for an .xls file.');
  }
  final records = _Records()
    ..hex(0x0809, '000610004618cd07c140000006010000') // BOF, worksheet.
    ..hex(0x020b, '0000000000000000ffff000000000000')
    ..hex(0x001b, '0000')
    ..hex(0x001a, '0000')
    ..hex(
      0x00a1,
      '00006400ffff01000100020000000000000000000000e03f000000000000e03f0000',
    )
    ..hex(0x0081, 'c004')
    ..hex(0x002a, '0000')
    ..hex(0x002b, '0000')
    ..hex(0x0080, '0000000000000000')
    ..hex(0x0028, '000000000000f03f')
    ..hex(0x0029, '000000000000f03f')
    ..hex(0x0026, '9a9999999999e93f')
    ..hex(0x0027, '9a9999999999e93f')
    ..hex(0x0083, '0000')
    ..hex(0x0084, '0000')
    ..add(
      0x0200,
      (BytesBuilder()
            ..add(_dword(0))
            ..add(_dword(rows.length))
            ..add(_words([0, columns, 0])))
          .takeBytes(),
    )
    ..hex(0x0225, '0000ff00');
  const style = 21;
  for (final (r, row) in rows.indexed) {
    for (final (c, value) in row.indexed) {
      final at = _words([r, c, style]);
      switch (value) {
        case null:
          break;
        case final String text:
          records.add(0x00fd, [...at, ..._dword(shared(text))]);
        case final bool flag:
          records.add(0x0205, [...at, flag ? 1 : 0, 0]);
        case final num number:
          final data = ByteData(8)
            ..setFloat64(0, number.toDouble(), Endian.little);
          records.add(0x0203, [...at, ...data.buffer.asUint8List()]);
        default:
          throw ArgumentError('Cells hold text, numbers or true/false.');
      }
    }
  }
  records
    ..hex(0x023e, '${first ? 'b606' : 'b604'}${'00' * 16}') // Sheet view.
    ..hex(0x000a, '');
  return records.bytes();
}

/// The shared string table. A record holds 8224 bytes at most, so a long
/// table continues in further records, always starting on a new string.
void _sharedStrings(_Records out, List<String> strings) {
  var id = 0x00fc;
  final record = BytesBuilder()
    ..add(_dword(strings.length))
    ..add(_dword(strings.length));
  for (final text in strings) {
    final wide = text.codeUnits.any((unit) => unit > 0xff);
    final entry = [
      ..._words([text.length]),
      wide ? 1 : 0,
      ...wide ? _utf16(text) : text.codeUnits,
    ];
    if (record.length + entry.length > _recordLimit) {
      out.add(id, record.takeBytes());
      id = 0x003c;
    }
    record.add(entry);
  }
  out.add(id, record.takeBytes());
}

/// Wraps [workbook] as the single `Workbook` stream of an OLE2 compound
/// file: a header, the sector allocation table, one directory sector, then
/// the stream.
Uint8List _compoundFile(Uint8List workbook) {
  var size = workbook.length < _smallStreamLimit
      ? _smallStreamLimit
      : workbook.length;
  size = (size + _sector - 1) ~/ _sector * _sector;
  final streamSectors = size ~/ _sector;
  const perTable = _sector ~/ 4;
  var tables = 1;
  while (tables * perTable < tables + 1 + streamSectors) {
    tables++;
  }
  if (tables > 109) {
    throw ArgumentError('The workbook is too large for this .xls writer.');
  }
  const free = 0xffffffff, endOfChain = 0xfffffffe, tableSector = 0xfffffffd;
  final directoryAt = tables, streamAt = tables + 1;

  final header = ByteData(_sector)
    ..setUint32(0x00, 0xe011cfd0, Endian.little)
    ..setUint32(0x04, 0xe11ab1a1, Endian.little)
    ..setUint16(0x18, 0x003e, Endian.little)
    ..setUint16(0x1a, 0x0003, Endian.little)
    ..setUint16(0x1c, 0xfffe, Endian.little)
    ..setUint16(0x1e, 9, Endian.little) // 512-byte sectors.
    ..setUint16(0x20, 6, Endian.little)
    ..setUint32(0x2c, tables, Endian.little)
    ..setUint32(0x30, directoryAt, Endian.little)
    ..setUint32(0x38, _smallStreamLimit, Endian.little)
    ..setUint32(0x3c, endOfChain, Endian.little)
    ..setUint32(0x44, endOfChain, Endian.little);
  for (var i = 0; i < 109; i++) {
    header.setUint32(0x4c + i * 4, i < tables ? i : free, Endian.little);
  }

  final table = ByteData(tables * _sector);
  for (var i = 0; i < tables * perTable; i++) {
    final next = i < tables
        ? tableSector
        : i == directoryAt
        ? endOfChain
        : i < streamAt + streamSectors - 1
        ? i + 1
        : i == streamAt + streamSectors - 1
        ? endOfChain
        : free;
    table.setUint32(i * 4, next, Endian.little);
  }

  final directory = ByteData(_sector);
  void entry(
    int index,
    String name, {
    required int type,
    required int color,
    required int child,
    required int start,
    required int length,
  }) {
    final at = index * 128;
    for (final (i, unit) in name.codeUnits.indexed) {
      directory.setUint16(at + i * 2, unit, Endian.little);
    }
    directory
      ..setUint16(
        at + 0x40,
        name.isEmpty ? 0 : name.length * 2 + 2,
        Endian.little,
      )
      ..setUint8(at + 0x42, type)
      ..setUint8(at + 0x43, color)
      ..setUint32(at + 0x44, free, Endian.little)
      ..setUint32(at + 0x48, free, Endian.little)
      ..setUint32(at + 0x4c, child, Endian.little)
      ..setUint32(at + 0x74, start, Endian.little)
      ..setUint32(at + 0x78, length, Endian.little);
  }

  entry(
    0,
    'Root Entry',
    type: 5,
    color: 0,
    child: 1,
    start: endOfChain,
    length: 0,
  );
  entry(
    1,
    'Workbook',
    type: 2,
    color: 1,
    child: free,
    start: streamAt,
    length: size,
  );
  entry(2, '', type: 0, color: 0, child: free, start: 0, length: 0);
  entry(3, '', type: 0, color: 0, child: free, start: 0, length: 0);

  return (BytesBuilder()
        ..add(header.buffer.asUint8List())
        ..add(table.buffer.asUint8List())
        ..add(directory.buffer.asUint8List())
        ..add(workbook)
        ..add(Uint8List(size - workbook.length)))
      .takeBytes();
}

class _Records {
  final _out = BytesBuilder();
  int get length => _out.length;

  void add(int id, List<int> data) {
    if (data.length > _recordLimit) {
      throw ArgumentError('A record is too long for an .xls file.');
    }
    _out
      ..add(_words([id, data.length]))
      ..add(data);
  }

  void hex(int id, String data) => add(id, [
    for (var i = 0; i < data.length; i += 2)
      int.parse(data.substring(i, i + 2), radix: 16),
  ]);

  Uint8List bytes() => _out.toBytes();
}

List<int> _words(List<int> values) => [
  for (final v in values) ...[v & 0xff, (v >> 8) & 0xff],
];

List<int> _dword(int v) => [
  v & 0xff,
  (v >> 8) & 0xff,
  (v >> 16) & 0xff,
  (v >> 24) & 0xff,
];

List<int> _utf16(String text) => _words(text.codeUnits);
